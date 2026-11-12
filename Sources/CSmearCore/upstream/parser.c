//////////////////////////////////////////////////////////////////////
//
// This is a very simple lisp style parser/compiler
//
// All commands are in the form of (command arg arg arg..)
// and all commands return a value that can be used
//
// All variables are of the double type and do not need to be
// defined before use
//
// Modified for NullPlayer (2026-11-12): FreeEnvironment, and FreeCC
// frees array accesses too; the tokenizer's state is per
// thread, so two Smears can load at once; a token, a function list and
// a variable table stop at their sizes instead of running past them
// (variables past MAX_VARIABLES share eOverflow); errors go to stderr
// rather than a message box; an Environment starts zeroed.
//
//////////////////////////////////////////////////////////////////////

#include "smear.h"

//////////////////////////////////////////////////////////////////////
//
// Static forward declarations
//
//////////////////////////////////////////////////////////////////////
static int		Expected(char *token, char *expected);
static int		ValidateVariable(char *name);
static void		FreeCC(CompiledCommand *ccp);
static CompiledCommand	*CompileStreamComplete(Environment *e, FILE *fp,
					       FunctionType func);
static CompiledArgument *NewArguement(CompiledCommand *ccp);
static int		CompileArgument(Environment *e, FILE *fp,
					CompiledCommand *ccp);
static void		ParserInit(void);
static char		*GetNextLine(FILE *fp);
static int		GetNextCharacter(FILE *fp);
static char		*GetToken(FILE *fp, int required);
static int		Expected(char *token, char *expected);
static void		CompileError(char *fmt, ...);

static	_Thread_local const char	*_errorScriptName = (char *)0;

//////////////////////////////////////////////////////////////////////
//
// Symbol table handling.  VERY BASIC
//
//////////////////////////////////////////////////////////////////////



ArrayStructure	*
GetArrayPointer(Environment *e, char *name)
{
	Symbol	*sp;

	for (sp = e->eSymbolTable; sp; sp = sp->sNext)
		if (sp->sType == STT_ARRAY && stricmp(sp->sName, name) == 0)
			return sp->sData.sdArrayPointer;

	// Didn't find it, make a new one

	sp = (Symbol *)malloc(sizeof(Symbol));

	sp->sName = (char *)malloc(strlen(name) + 1);
	sp->sType = STT_ARRAY;
	strcpy(sp->sName, name);
	sp->sData.sdArrayPointer = arrayAllocateNew();
	sp->sNext = e->eSymbolTable;

	e->eSymbolTable = sp;

	return sp->sData.sdArrayPointer;
}

double	*
GetVariablePointer(Environment *e, char *name)
{
	Symbol	*sp;

	for (sp = e->eSymbolTable; sp; sp = sp->sNext)
		if (sp->sType == STT_DOUBLE && stricmp(sp->sName, name) == 0)
			return sp->sData.sdDouble;

	// Didn't find it, make a new one

	sp = (Symbol *)malloc(sizeof(Symbol));

	sp->sName = (char *)malloc(strlen(name) + 1);
	sp->sType = STT_DOUBLE;
	strcpy(sp->sName, name);
	if (e->eVariableCount < MAX_VARIABLES)
		sp->sData.sdDouble = &(e->eVariables[e->eVariableCount++]);
	else
		sp->sData.sdDouble = &(e->eOverflow);
	(*sp->sData.sdDouble) = 0.0;
	sp->sNext = e->eSymbolTable;

	e->eSymbolTable = sp;

	return sp->sData.sdDouble;
}

void
SetVariable(Environment *e, char *name, double value)
{
	double	*dp;
	
	if ((dp = GetVariablePointer(e, name)) == (double *)0)
		return;

	*dp = value;
}

double
GetVariable(Environment *e, char *name)
{
	double	*dp;
	
	if ((dp = GetVariablePointer(e, name)) == (double *)0)
		return 0.0;

	return *dp;
}

static int
ValidateVariable(char *name)
{
	if ((*name < 'a' || *name > 'z') &&
	    (*name < 'A' || *name > 'Z') && *name != '_')
		return -1;

	while (*(++name))
		if ((*name < 'a' || *name > 'z') &&
		    (*name < 'A' || *name > 'Z') &&
		    (*name < '0' || *name > '9') && *name != '_')
			return -1;

	return 0;
}


//////////////////////////////////////////////////////////////////////
//
// Build stuff
//
//////////////////////////////////////////////////////////////////////


static void
FreeArgument(CompiledArgument *cap)
{
	ArrayAccess	*aap;

	if (cap->caFlags == CA_COMMAND)
		FreeCC(cap->caData.cadCommand);
	else
	if (cap->caFlags == CA_ARRAY && (aap = cap->caData.cadArray))
	{
		if (aap->aaElement)
		{
			FreeArgument(aap->aaElement);
			free(aap->aaElement);
		}
		free(aap);
	}
}


static void
FreeCC(CompiledCommand *ccp)
{
	int	i;

	for (i = 0; i < ccp->ccArgumentCount; i++)
		FreeArgument(&ccp->ccArguments[i]);

	if (ccp->ccArgumentAlloc)
		free(ccp->ccArguments);

	free(ccp);
}


static	CompiledCommand *
CompileStreamComplete(Environment *e, FILE *fp, FunctionType func)
{
	FunctionList	*flp;
	CompiledCommand	*ccp;
	int		rv;

	if ((flp = GetFunctionInfo(func)) == (FunctionList *)0)
		return (CompiledCommand *)0;

	if ((ccp = (CompiledCommand *)malloc(sizeof(CompiledCommand))) ==
	    (CompiledCommand *)0)
		return (CompiledCommand *)0;

	memset(ccp, 0, sizeof(CompiledCommand));

	ccp->ccFunction = flp;

	while ((rv = CompileArgument(e, fp, ccp)) == 0)
		;

	if (rv == -1)
	{
		FreeCC(ccp);
		return (CompiledCommand *)0;
	}

	if (ccp->ccArgumentCount < flp->flMinArgs)
	{
		if (flp->flMinArgs == flp->flMaxArgs)
			CompileError(
	"Not enough arguments to function '%s' (should be %d)",
				     flp->flName, flp->flMinArgs);
		else
			CompileError(
	"Not enough arguments to function '%s' (should be %d-%d)",
				     flp->flName, flp->flMinArgs,
				     flp->flMaxArgs);
		FreeCC(ccp);
		return (CompiledCommand *)0;
	}

	if (ccp->ccArgumentCount > flp->flMaxArgs)
	{
		if (flp->flMinArgs == flp->flMaxArgs)
			CompileError(
	"Too many arguments to function '%s' (should be %d)",
				     flp->flName, flp->flMinArgs);
		else
			CompileError(
	"Too many arguments to function '%s' (should be %d-%d)",
				     flp->flName, flp->flMinArgs,
				     flp->flMaxArgs);
		FreeCC(ccp);
		return (CompiledCommand *)0;
	}

	return ccp;
}


static	CompiledArgument *
NewArguement(CompiledCommand *ccp)
{
	if (ccp->ccArgumentCount >= ccp->ccArgumentAlloc)
	{
		if (ccp->ccArgumentAlloc)
		{
			if (ccp->ccArgumentAlloc > 16)
				ccp->ccArgumentAlloc += 16;
			else
				ccp->ccArgumentAlloc <<= 1;

			ccp->ccArguments =
				(CompiledArgument *)realloc(ccp->ccArguments,
					ccp->ccArgumentAlloc *
					sizeof(CompiledArgument));
		}
		else
		{
			ccp->ccArgumentAlloc = 4;
			ccp->ccArguments = (CompiledArgument *)malloc(
				ccp->ccArgumentAlloc *
				sizeof(CompiledArgument));
		}
	}

	if (ccp->ccArguments == (CompiledArgument *)0)
		return (CompiledArgument *)0;

	return &(ccp->ccArguments[ccp->ccArgumentCount++]);
}


static	int
CompileArgument(Environment *e, FILE *fp, CompiledCommand *ccp)
{
	char			*token;
	FunctionType		ftype;
	CompiledArgument	*cap;
	CompiledCommand		*tccp;
	double			d;
	CompiledCommand		tempCC;

	if ((token = GetToken(fp, 1)) == (char *)0)
		return -1;

	switch (token[0])
	{
	case '(':
		// Sub-clause
		if ((token = GetToken(fp, 1)) == (char *)0)
			return -1;

		if ((ftype = RecogniseFunctionType(token)) == -1)
		{
			CompileError("Invalid function '%s'", token);
			return -1;
		}

		if ((cap = NewArguement(ccp)) == (CompiledArgument *)0)
		{
			CompileError("Out of memory");
			return -1;
		}

		if ((tccp = CompileStreamComplete(e, fp, ftype))
		    == (CompiledCommand *)0)
			return -1;

		cap->caFlags = CA_COMMAND;
		cap->caData.cadCommand = tccp;

		break;

	case '0': case '1': case '2': case '3': case '4': case '5':
	case '6': case '7': case '8': case '9': case '.': case '-':
		// Literal

		d = strtod(token, NULL);
		// printf("Set literal [%s] [%lf]\n", token, d);

		if ((cap = NewArguement(ccp)) == (CompiledArgument *)0)
		{
			CompileError("Out of memory");
			return -1;
		}

		cap->caFlags = CA_LITERAL;
		// printf("Set literal %lf\n", d);
		cap->caData.cadValue = d;

		break;

	case '[':
		// Array
		if ((token = GetToken(fp, 1)) == (char *)0)
			return -1;

		if (*token != '$')
		{
			CompileError("Variable required", token);
			return -1;
		}

		token++;

		if (ValidateVariable(token) == -1)
		{
			CompileError("Invalid variable '%s'", token);
			return -1;
		}

		if ((cap = NewArguement(ccp)) == (CompiledArgument *)0)
		{
			CompileError("Out of memory");
			return -1;
		}

		cap->caFlags = CA_ARRAY;
		cap->caData.cadArray = arrayAllocateNewAccess();
		cap->caData.cadArray->aaArray = GetArrayPointer(e, token);

		memset(&tempCC, 0, sizeof(CompiledCommand));

		if (CompileArgument(e, fp, &tempCC) != 0)
		{
			CompileError("Invalid Array specification");
			return -1;
		}

		cap->caData.cadArray->aaElement = tempCC.ccArguments;

		if ((token = GetToken(fp, 1)) == (char *)0)
			return -1;

		if (*token != ']')
		{
			CompileError("Expected ']'");
			return -1;
		}

		break;

	case '$':
		// Variable

		token++;

		if (ValidateVariable(token) == -1)
		{
			CompileError("Invalid variable '%s'", token);
			return -1;
		}

		if ((cap = NewArguement(ccp)) == (CompiledArgument *)0)
		{
			CompileError("Out of memory");
			return -1;
		}

		cap->caFlags = CA_VARIABLE;
		cap->caData.cadVariable = GetVariablePointer(e, token);

		break;

	case ')':
		// End of list

		return 1;
	}

	return 0;
}


int
TopLevelCompile(Environment *e, FILE *fp)
{
	char	*token;

	e->eVariableCount = 0;
	e->eFunctionCount = 0;
	e->eSymbolTable = (Symbol *)0;

	while ((token = GetToken(fp, 0)) != (char *)0)
	{
		if (e->eFunctionCount >= MAX_FUNCTIONS)
		{
			CompileError("Too many functions");
			return -1;
		}

		if (Expected(token, "(") == -1)
			return -1;

		if ((token = GetToken(fp, 1)) == (char *)0)
			return -1;

		if (Expected(token, "DECLARE"))
			return -1;

		if ((token = GetToken(fp, 1)) == (char *)0)
			return -1;

		if (ValidateVariable(token) == -1)
		{
			CompileError("Invalid function name");
			return -1;
		}

		e->eFunctionNames[e->eFunctionCount] =
			(char *)malloc(strlen(token) + 1);
		strcpy(e->eFunctionNames[e->eFunctionCount], token);

		if ((e->eFunctions[e->eFunctionCount] =
			CompileStreamComplete(e, fp, FN_DECLARE)) ==
		    		(CompiledCommand *)0)
			return -1;

		e->eFunctionCount++;
	}

	return 0;
}


//////////////////////////////////////////////////////////////////////
//
// Simple token stuff
//
//////////////////////////////////////////////////////////////////////

static	_Thread_local char	gtLine[8192];
static	_Thread_local char	*gtLinePointer = (char *)0;
static	_Thread_local int	gtLineNumber;
static	_Thread_local int	gtEndOfFile;
static	_Thread_local int	gtPushChar = 0;

static	_Thread_local char	gtDummyScript[8192];
static	_Thread_local int	gtHasDummyScript = 0;


void
ParserSetupDummyScript(char *s)
{
	strcpy(gtDummyScript, s);
	gtHasDummyScript = 1;
}


void
ParserInit(void)
{
	gtLinePointer = 0;
	gtEndOfFile = 0;
	gtLineNumber = 0;
	gtPushChar = 0;
}

static char	*
GetNextLine(FILE *fp)
{
	char	*p;

	if (gtEndOfFile)
		return (char *)0;

	if (fp == (FILE *)0)
	{
		if (gtHasDummyScript)
		{
			strcpy(gtLine, gtDummyScript);
			gtHasDummyScript = 0;
		}
		else
		{
			gtEndOfFile = 1;
			return (char *)0;
		}
	}
	else
		if (fgets(gtLine, 8191, fp) == (char *)0)
		{
			gtEndOfFile = 1;
			return (char *)0;
		}

	// Remove C++ style comments
	for (p = gtLine; *p; p++)
	{
		if (*p == '/' && *(p + 1) == '/')
		{
			*p = '\0';
			break;
		}
	}

	// Remove end of line
	while ((p = gtLine + strlen(gtLine)) > gtLine &&
	       (*p == '\n' || *p == '\r'))
		*p = '\0';

	gtLineNumber++;
	gtLinePointer = gtLine;

	return gtLinePointer;
}


static	int
GetNextCharacter(FILE *fp)
{
	int	rc;

	if (gtPushChar != 0)
	{
		rc = gtPushChar;
		gtPushChar = 0;

		return rc;
	}

	while (1)
	{
		if (gtEndOfFile)
			return 0;

		if (gtLinePointer && *gtLinePointer)
			return *(gtLinePointer++);

		GetNextLine(fp);
	}
}


static	char	*
GetToken(FILE *fp, int required)
{
static	_Thread_local char	_token[64];
	char	*tp;
	int	nextChar;

	tp = _token;

	nextChar = GetNextCharacter(fp);

	// Skip white space
	while (!gtEndOfFile && (nextChar == ' ' || nextChar == '\t' ||
				nextChar == '\n' || nextChar == '\r'))
	{
		nextChar = GetNextCharacter(fp);
	}

	if (gtEndOfFile)
	{
		if (required)
			CompileError("Unexpected end of file");

		return (char *)0;
	}

	// The '(' and ')' characters are very special indeed
	// So are '[' and ']'
	if (nextChar == '(' || nextChar == ')' ||
	    nextChar == '[' || nextChar == ']')
	{
		*tp++ = nextChar;
		*tp = '\0';

		return _token;
	}

	while (1)
	{
		if (tp < _token + sizeof(_token) - 1)
			*tp++ = nextChar;
		nextChar = GetNextCharacter(fp);

		if (gtEndOfFile)
			break;

		if (nextChar == ' ' || nextChar == '\n' || nextChar == '\r' ||
		    nextChar == '\t' || nextChar == '(' || nextChar == ')' ||
		    nextChar == '[' || nextChar == ']')
		{
			gtPushChar = nextChar;
			break;
		}
	}

	*tp = '\0';

	return _token;
}

static int
Expected(char *token, char *expected)
{
	if (stricmp(token, expected) == 0)
		return 0;

	CompileError("Expected '%s' but got '%s'", expected, token);

	return -1;
}


static	void
CompileError(char *fmt, ...)
{
	va_list	ap;
	char	_tmp[1024];

	va_start(ap, fmt);
	vsnprintf(_tmp, sizeof(_tmp), fmt, ap);
	va_end(ap);

	fprintf(stderr, "Smear: %s: %d: %s\n", _errorScriptName, gtLineNumber, _tmp);
}

//////////////////////////////////////////////////////////////////////
//
// Execute a function
//
//////////////////////////////////////////////////////////////////////

double
RunCompiledCommand(Environment *e, CompiledCommand *ccp)
{
	double	d = 0.0;

	// printf("RunCompiledCommand(%s)\n", ccp->ccFunction->flName);
	if (ccp->ccFunction && ccp->ccFunction->flFunction)
		d = (*(ccp->ccFunction->flFunction))(e, ccp);

	return d;
}


double
EvaluateArgument(Environment *e, CompiledArgument *cap)
{
	switch (cap->caFlags)
	{
	case CA_LITERAL:
		// printf("Literal: %lf\n", cap->caData.cadValue);
		return cap->caData.cadValue;

	case CA_VARIABLE:
		return *(cap->caData.cadVariable);

	case CA_COMMAND:
		return RunCompiledCommand(e, cap->caData.cadCommand);

	case CA_ARRAY:
		return arrayEvaluate(cap->caData.cadArray->aaArray,
			EvaluateArgument(e, cap->caData.cadArray->aaElement));

	default:
		return 0.0;
	}
}


double
EvaluateArgumentNumber(Environment *e, CompiledCommand *ccp, int n)
{
	if (n >= ccp->ccArgumentCount)
		return 0;

	return EvaluateArgument(e, &(ccp->ccArguments[n]));
}


double	*
GetLValueNumber(Environment *e, CompiledCommand *ccp, int n)
{
	if (n >= ccp->ccArgumentCount)
		return (double *)0;

	if (ccp->ccArguments[n].caFlags == CA_VARIABLE)
		return ccp->ccArguments[n].caData.cadVariable;

	if (ccp->ccArguments[n].caFlags == CA_ARRAY)
		return arrayGetEvaluationPointer(
			ccp->ccArguments[n].caData.cadArray->aaArray,
			EvaluateArgument(e,
				ccp->ccArguments[n].caData.cadArray->aaElement
			));

	RunTimeError("Sciprt: %s\n\nInvalid LValue", e->eFile);

	return (double *)0;
}


int
ExecuteFunction(Environment *e, char *func)
{
	int	i;

	// Find the function
	
	for (i = 0; i < e->eFunctionCount; i++)
	{
		if (stricmp(e->eFunctionNames[i], func) == 0)
		{
			RunCompiledCommand(e, e->eFunctions[i]);
			return 0;
		}
	}

	return -1;
}


CompiledCommand *
FindFunction(Environment *e, char *func)
{
	int	i;

	// Find the function
	
	for (i = 0; i < e->eFunctionCount; i++)
		if (stricmp(e->eFunctionNames[i], func) == 0)
			return e->eFunctions[i];

	return (CompiledCommand *)0;
}


//////////////////////////////////////////////////////////////////////
//
// Extremely simple test main
//
//////////////////////////////////////////////////////////////////////

void
RunTimeError(char *fmt, ...)
{
	// Upstream showed these only with "Debug Scripts" on; a script can
	// raise one per pixel, so they are dropped.
	(void)fmt;
}



Environment	*
ParseFile(const char *fileName)
{
	FILE		*fp;
	Environment	*ep;

	if (fileName)
	{
		_errorScriptName = fileName;
		if ((fp = fopen(fileName, "r")) == (FILE *)0)
			return (Environment *)0;
	}
	else
	{
		_errorScriptName = "Internal";
		fp = (FILE *)0;
	}

	if ((ep = (Environment *)calloc(1, sizeof(Environment))) == (Environment *)0)
	{
		if (fileName)
			fclose(fp);
		return (Environment *)0;
	}

	ParserInit();

	if (TopLevelCompile(ep, fp) == -1)
	{
		free(ep);
		if (fileName)
			fclose(fp);
		return (Environment *)0;
	}

	if (fileName)
		fclose(fp);

	return ep;
}


void
FreeEnvironment(Environment *e)
{
	int	i;
	Symbol	*sp;

	for (i = 0; i < e->eFunctionCount; i++)
	{
		free(e->eFunctionNames[i]);
		FreeCC(e->eFunctions[i]);
	}

	while ((sp = e->eSymbolTable) != (Symbol *)0)
	{
		e->eSymbolTable = sp->sNext;
		if (sp->sType == STT_ARRAY)
		{
			arrayFreeAllocation(sp->sData.sdArrayPointer);
			free(sp->sData.sdArrayPointer);
		}
		free(sp->sName);
		free(sp);
	}

	free(e->eFile);
	free(e);
}
