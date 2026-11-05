// NullPlayer: upstream AVS includes x86 intrinsic headers unconditionally. This search
// path sits in front of the compiler's own, so on arm64 the SSE code compiles through
// sse2neon (v1.8.0, MIT); on x86_64 the real header is used.
#pragma once
#if defined(__aarch64__)
#include "sse2neon.h"
#else
#include_next <pmmintrin.h>
#endif
