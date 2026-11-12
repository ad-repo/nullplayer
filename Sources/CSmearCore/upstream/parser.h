//////////////////////////////////////////////////////////////////////
//
// Parser include file
//
// Modified for NullPlayer (2026-11-12): an Environment knows the Smear
// it runs in (eState) and has a sink for variables past MAX_VARIABLES;
// the declarations follow the edits in smear.h and runtime.c.
//
//////////////////////////////////////////////////////////////////////

#ifndef	__PARSER_H__
#define	__PARSER_H__

#define	MAX_ARGUMENTS	256
#define	MAX_VARIABLES	256
#define	MAX_FUNCTIONS	256

#define	CA_LITERAL	0x01
#define	CA_VARIABLE	0x02
#define	CA_COMMAND	0x03
#define	CA_ARRAY	0x04

typedef	struct	__compiled_argument
{
	int	caFlags;
	union
	{
		struct	__compiled_command	*cadCommand;
		double				*cadVariable;
		double				cadValue;
		struct	__array_access		*cadArray;
	}	caData;
}	CompiledArgument;


typedef	struct	__compiled_command
{
	struct	__function_list	*ccFunction;
	int			ccArgumentCount;
	int			ccArgumentAlloc;
	CompiledArgument	*ccArguments;
}	CompiledCommand;


#define	MAX_ARRAY_OFFSET	4096
#define	ARRAY_ALLOCATION_CHUNK	32

typedef	struct	__array_structure
{
	int	asAllocated;
	double	*asData;
}	ArrayStructure;


typedef	struct	__array_access
{
	ArrayStructure		*aaArray;
	CompiledArgument	*aaElement;
}	ArrayAccess;

// The symbol table is extremely simple because there is no scope, and the
// code should be small enough not to require a fast lookup symbol table
#define	STT_DOUBLE	0x01
#define	STT_ARRAY	0x02

typedef	struct	__symbol
{
	char			*sName;
	int			sType;
	union
	{
		double			*sdDouble;
		ArrayStructure		*sdArrayPointer;
	}			sData;
	struct	__symbol	*sNext;
}	Symbol;


#include "eruntime.h"

// This is everything we need to compile and run, so we can have multiple
// bits of code available.  I probably should be doing this as a class, but
// I like C so much more  :)
typedef	struct	__environment
{
	struct SmearState	*eState;
	char			*eFile;
	double			eOverflow;
	Symbol			*eSymbolTable;
	int			eVariableCount;
	double			eVariables[MAX_VARIABLES];
	int			eFunctionCount;
	char			*eFunctionNames[MAX_FUNCTIONS];
	CompiledCommand		*eFunctions[MAX_FUNCTIONS];
	RuntimeEnvironment	eRuntime;
	RuntimeAudio		eAudio;
}	Environment;


typedef	struct	__function_list
{
	int		flNumber;
	char		*flName;
	int		flMinArgs;
	int		flMaxArgs;
	double		(*flFunction)(Environment *, CompiledCommand *);
}	FunctionList;

#define flFuncType      	double (*)(Environment *, CompiledCommand *)
#define	flFuncDeclare(fn)	double fn(Environment *e, CompiledCommand *ccp)
#define	flArgument(n)		EvaluateArgumentNumber(e, ccp, n)
#define	flLValue(n)		GetLValueNumber(e, ccp, n)

typedef	enum
{
	FN_DECLARE = 1,
	FN_PLUS, FN_MINUS, FN_TIMES, FN_DIVIDE, FN_LAND, FN_LOR, FN_NOT,
	FN_EQUAL, FN_NOTEQUAL, FN_LT, FN_LTEQUAL, FN_GT, FN_GTEQUAL,
	FN_SIN, FN_COS, FN_TAN, FN_ECHO, FN_IF, FN_RND, FN_ABS, FN_TRUNC,
	FN_SQRT, FN_ATAN, FN_SIGN, FN_LOG, FN_EXP, FN_POW, FN_MOD, FN_CLAMP,
	FN_POS, FN_WRAP, FN_SET, FN_SET_2, FN_LOOP, FN_WHILE, FN_BLOCK,
	FN_POLAR, FN_CART, FN_LSPECT, FN_RSPECT, FN_LWAVE, FN_RWAVE,
	FN_BITAND, FN_BITOR, FN_BITLEFT, FN_BITRIGHT, FN_NEG, FN_CASE,
	FN_SET_PLUS, FN_SET_MINUS, FN_SET_DIV, FN_SET_MULT, FN_SET_MOD,
	FN_3DSETUP, FN_3DROTATE, FN_ASIN, FN_ACOS

}	FunctionType;

// Function definitions
extern	double	*GetVariablePointer(Environment *, char *);
extern	int	TopLevelCompile(Environment *, FILE *);

extern	double	EvaluateArgument(Environment *, CompiledArgument *);
extern	double	EvaluateArgumentNumber(Environment *, CompiledCommand *, int);
extern	double	*GetLValueNumber(Environment *, CompiledCommand *, int);
extern	double	RunCompiledCommand(Environment *, CompiledCommand *);
extern	int	ExecuteFunction(Environment *e, char *func);

extern	int		RecogniseFunctionType(char *);
extern	FunctionList	*GetFunctionInfo(int);
extern	void	RunTimeError(char *fmt, ...);

extern	void	SetupForRun(Environment *);
extern	int	TimedRunForLine(Environment *, uint32_t *, int, int, int, int *);

extern	void	SetupForColorRun(Environment *);
extern	void	RunForColor(Environment *, uint32_t *, int);

extern	void	SetupForWaveForm(Environment *);
extern	void	RunForWaveForm(Environment *, int, int, int);

extern	void	SetupForParticle(Environment *);
extern	void	RunForParticle(Environment *, int, int, double);

extern	void		ParserSetupDummyScript(char *);
extern	Environment	*ParseFile(const char *);
extern	void		FreeEnvironment(Environment *);

extern	void		SetVariable(Environment *, char *, double);
extern	double		GetVariable(Environment *, char *);

extern	CompiledCommand *FindFunction(Environment *, char *);
extern	void		CalculateAudioData(AudioData *, signed char *, signed char *, unsigned char *, unsigned char *);

extern	ArrayStructure	*arrayAllocateNew(void);
extern	void		arrayFreeAllocation(ArrayStructure *);
extern	ArrayAccess	*arrayAllocateNewAccess(void);
extern	double		*arrayGetEvaluationPointer(ArrayStructure *, double);
extern	double		arrayEvaluate(ArrayStructure *, double);

#endif
