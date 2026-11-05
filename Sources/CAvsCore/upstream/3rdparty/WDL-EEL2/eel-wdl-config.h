#pragma once

#include "../platform.h"
#include <assert.h>

#define EEL_F_SUFFIX
typedef double EEL_F;

#define WDL_FALLTHROUGH
#define WDL_STATICFUNC_UNUSED __attribute__((unused))
#define WDL_UINT64 uint64_t
#define WDL_UINT64_CONST(x) ((WDL_UINT64)(x))
#define WDL_INT64_CONST(x) ((WDL_INT64)(x))
#define WDL_INT64 int64_t
#define WDL_ASSERT assert
#define WDL_likely
#define WDL_unlikely
#define WDL_NORMALLY
#define WDL_NOT_NORMALLY
#define wdl_min min
#define wdl_max max

#define FUNCTION_MARKER "\n.byte 0x89,0x90,0x90,0x90,0x90,0x90,0x90,0x90,0x90,0x90,0x90,0x90\n"
#define UINT_PTR uintptr_t
#define INT_PTR intptr_t

#define EEL_F_SUFFIX "l"
#define NSEEL_RAM_BLOCKS 128
#define NSEEL_RAM_ITEMSPERBLOCK 65536
#define NSEEL_RAM_ITEMSPERBLOCK_LOG2 16
