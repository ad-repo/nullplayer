#include "smear.h"

FunctionList	functionList[] =
{
	{ FN_DECLARE,	"DECLARE",	0,	9999,	fnExecute	},
	{ FN_BLOCK,	"BLOCK",	0,	9999,	fnExecute	},
	{ FN_PLUS,	"+",		2,	9999,	fnPlus		},
	{ FN_MINUS,	"-",		2,	2,	fnMinus		},
	{ FN_TIMES,	"*",		2,	9999,	fnTimes		},
	{ FN_DIVIDE,	"/",		2,	2,	fnDivide	},
	{ FN_MOD,	"%",		2,	2,	fnMod		},
	{ FN_LAND,	"&&",		2,	9999,	fnLAnd		},
	{ FN_LOR,	"||",		2,	9999,	fnLOr		},
	{ FN_NOT,	"!",		1,	1,	fnNot		},
	{ FN_EQUAL,	"==",		2,	2,	fnEqual		},
	{ FN_NOTEQUAL,	"!=",		2,	2,	fnNotEqual	},
	{ FN_LT,	"<",		2,	2,	fnLessThan	},
	{ FN_LTEQUAL,	"<=",		2,	2,	fnLessThanEqual	},
	{ FN_GT,	">",		2,	2,	fnGreaterThan	},
	{ FN_GTEQUAL,	">=",		2,	2,	fnGreaterThanEqual},
	{ FN_SIN,	"SIN",		1,	1,	fnSin		},
	{ FN_COS,	"COS",		1,	1,	fnCos		},
	{ FN_TAN,	"TAN",		1,	1,	fnTan		},
	{ FN_ECHO,	"ECHO",		1,	1,	fnEcho		},
	{ FN_IF,	"IF",		2,	3,	fnIf		},
	{ FN_RND,	"RND",		0,	2,	fnRnd		},
	{ FN_WRAP,	"WRAP",		1,	3,	fnWrap		},
	{ FN_ABS,	"ABS",		1,	1,	fnAbs		},
	{ FN_TRUNC,	"TRUNC",	1,	1,	fnTrunc		},
	{ FN_SQRT,	"SQRT",		1,	1,	fnSqrt		},
	{ FN_ATAN,	"ATAN",		1,	1,	fnAtan		},
	{ FN_ASIN,	"ASIN",		1,	1,	fnAsin		},
	{ FN_ACOS,	"ACOS",		1,	1,	fnAcos		},
	{ FN_SIGN,	"SIGN",		1,	1,	fnSign		},
	{ FN_LOG,	"LOG",		1,	1,	fnLog		},
	{ FN_EXP,	"EXP",		1,	1,	fnExp		},
	{ FN_POW,	"POW",		2,	2,	fnPow		},
	{ FN_MOD,	"MOD",		2,	2,	fnMod		},
	{ FN_CLAMP,	"CLAMP",	1,	3,	fnClamp		},
	{ FN_POS,	"POS",		1,	1,	fnPos		},
	{ FN_SET,	"SET",		2,	2,	fnSet		},
	{ FN_SET_2,	"=",		2,	2,	fnSet		},
	{ FN_SET_PLUS,	"+=",		2,	2,	fnSetPlus	},
	{ FN_SET_MINUS,	"-=",		2,	2,	fnSetMinus	},
	{ FN_SET_DIV,	"/=",		2,	2,	fnSetDiv	},
	{ FN_SET_MULT,	"*=",		2,	2,	fnSetMult	},
	{ FN_SET_MOD,	"%=",		2,	2,	fnSetMod	},
	{ FN_LOOP,	"LOOP",		4,	4,	fnLoop		},
	{ FN_WHILE,	"WHILE",	2,	2,	fnWhile		},
	{ FN_POLAR,	"POLAR",	4,	4,	fnPolar		},
	{ FN_CART,	"CART",		4,	4,	fnCart		},
	{ FN_LSPECT,	"LSPECT",	1,	1,	fnLSpect	},
	{ FN_RSPECT,	"RSPECT",	1,	1,	fnRSpect	},
	{ FN_LWAVE,	"LWAVE",	1,	1,	fnLWave		},
	{ FN_RWAVE,	"RWAVE",	1,	1,	fnRWave		},
	{ FN_BITAND,	"&",		2,	9999,	fnBitAnd	},
	{ FN_BITOR,	"|",		2,	9999,	fnBitOr		},
	{ FN_BITLEFT,	"<<",		2,	2,	fnBitLeft	},
	{ FN_BITRIGHT,	">>",		2,	2,	fnBitRight	},
	{ FN_NEG,	"NEG",		1,	1,	fnNeg		},
	{ FN_CASE,	"CASE",		1,	9999,	fnCase		},
	{ FN_3DSETUP,	"3DSETUP",	3,	3,	fn3DSetup	},
	{ FN_3DROTATE,	"3DROTATE",	6,	6,	fn3DRotate	},
	{ 0,		0,		0,	0,	(flFuncType)0	}
};

int
RecogniseFunctionType(char *token)
{
	char		c = *token;
	FunctionList	*flp;

	if (c >= 'a' && c <= 'z')
		c = c - 'a' + 'A';

	for (flp = functionList; flp->flNumber != 0; flp++)
	{
		if (c == flp->flName[0] && stricmp(token, flp->flName) == 0)
			return flp->flNumber;
	}

	return -1;
}


FunctionList *
GetFunctionInfo(int number)
{
	FunctionList	*flp;

	for (flp = functionList; flp->flNumber != 0; flp++)
		if (flp->flNumber == number)
			return flp;

	return (FunctionList *)0;
}
