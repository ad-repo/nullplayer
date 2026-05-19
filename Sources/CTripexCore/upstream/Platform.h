#pragma once

typedef signed char int8;
typedef unsigned char uint8;

typedef signed short int16;
typedef unsigned short uint16;

typedef signed int int32;
typedef unsigned int uint32;

#ifdef _MSC_VER

	#define WIN32_LEAN_AND_MEAN
	#define NOMINMAX
	#define  _CRT_SECURE_NO_WARNINGS

	#pragma warning(error: 4305)
	#pragma warning(disable:4100) // unreferenced formal parameter
	#pragma warning(disable:4244) // 'conversion' conversion from 'type1' to 'type2', possible loss of data

#else

	#error Unsupported compiler.

#endif
