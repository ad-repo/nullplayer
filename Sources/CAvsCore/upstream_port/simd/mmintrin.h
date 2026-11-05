// NullPlayer: upstream AVS includes x86 intrinsic headers unconditionally. This search
// path sits in front of the compiler's own, so on arm64 the SSE code compiles through
// sse2neon (v1.8.0, MIT); on x86_64 the real header is used.
#pragma once
#if defined(__aarch64__)
#include "sse2neon.h"
// sse2neon v1.8.0 lacks these MMX setters (Convolution Filter computes its kernel with them).
#define _mm_set1_pi16(w) vreinterpret_s64_s16(vdup_n_s16(w))
#define _mm_setzero_si64() vcreate_s64(0)
#else
#include_next <mmintrin.h>
#endif
