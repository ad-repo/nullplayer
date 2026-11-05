/*
  LICENSE
  -------
Copyright 2005 Nullsoft, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.

  * Neither the name of Nullsoft nor the names of its contributors may be used to
    endorse or promote products derived from this software without specific prior
    written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/
#include "e_multiplier.h"

#ifdef SIMD_MODE_X86_SSE
#include <immintrin.h>
#endif

constexpr Parameter Multiplier_Info::parameters[];

E_Multiplier::E_Multiplier(AVS_Instance* avs) : Configurable_Effect(avs) {}

E_Multiplier::~E_Multiplier() {}

#define MULTIPLY_C(NAME, OP, TIMES)                                       \
    inline static void multiply_x##NAME##_rgb0_8_c(uint32_t* framebuffer, \
                                                   size_t length) {       \
        for (size_t i = 0; i < length; i++) {                             \
            uint32_t r = (framebuffer[i] & 0xff0000) OP TIMES;            \
            uint32_t g = (framebuffer[i] & 0xff00) OP TIMES;              \
            uint32_t b = (framebuffer[i] & 0xff) OP TIMES;                \
            r = r > 0xff0000 ? 0xff0000 : r & 0xff0000;                   \
            g = g > 0xff00 ? 0xff00 : g & 0xff00;                         \
            b = b > 0xff ? 0xff : b & 0xff;                               \
            framebuffer[i] = r | g | b;                                   \
        }                                                                 \
    }

// Generates multiply_x8_rgb0_8_c() etc.
MULTIPLY_C(8, *, 8)
MULTIPLY_C(4, *, 4)
MULTIPLY_C(2, *, 2)
MULTIPLY_C(05, >>, 1)
MULTIPLY_C(025, >>, 2)
MULTIPLY_C(0125, >>, 3)

inline static void multiply_infroot_rgb0_8_c(uint32_t* framebuffer, size_t length) {
    for (size_t i = 0; i < length; i++) {
        if ((framebuffer[i] & 0x00ffffff) != 0x00ffffff) {
            framebuffer[i] = 0;
        }
    }
}

inline static void multiply_infsquare_rgb0_8_c(uint32_t* framebuffer, size_t length) {
    for (size_t i = 0; i < length; i++) {
        if ((framebuffer[i] & 0x00ffffff) != 0x00000000) {
            framebuffer[i] = 0x00ffffff;
        }
    }
}

#ifdef SIMD_MODE_X86_SSE
#define REPEAT_1(code)  code
#define REPEAT_2(code)  code code
#define REPEAT_3(code)  code code code
#define REPEAT(code, n) REPEAT_##n(code)
#define MULTIPLY_BRIGHTEN_X86V128(NAME, TIMES)                                  \
    inline static void multiply_x##NAME##_rgb0_8_x86v128(uint32_t* framebuffer, \
                                                         size_t length) {       \
        for (size_t i = 0; i < length; i += 4) {                                \
            __m128i fb_4px = _mm_loadu_si128((__m128i*)&framebuffer[i]);        \
            REPEAT(fb_4px = _mm_adds_epu8(fb_4px, fb_4px);, TIMES)              \
            _mm_storeu_si128((__m128i*)&framebuffer[i], fb_4px);                \
        }                                                                       \
    }

#define MULTIPLY_DARKEN_X86V128(NAME, TIMES, MASK)                              \
    inline static void multiply_x##NAME##_rgb0_8_x86v128(uint32_t* framebuffer, \
                                                         size_t length) {       \
        __m128i mask = _mm_set1_epi32(MASK);                                    \
        for (size_t i = 0; i < length; i += 4) {                                \
            __m128i fb_4px = _mm_loadu_si128((__m128i*)&framebuffer[i]);        \
            fb_4px = _mm_srli_epi32(fb_4px, TIMES);                             \
            fb_4px = _mm_and_si128(fb_4px, mask);                               \
            _mm_storeu_si128((__m128i*)&framebuffer[i], fb_4px);                \
        }                                                                       \
    }

// Generates multiply_x8_rgb0_8_x86v128() etc.
MULTIPLY_BRIGHTEN_X86V128(8, 3)
MULTIPLY_BRIGHTEN_X86V128(4, 2)
MULTIPLY_BRIGHTEN_X86V128(2, 1)
// Generates multiply_x05_rgb0_8_x86v128() etc.
MULTIPLY_DARKEN_X86V128(05, 1, 0x007f7f7f)
MULTIPLY_DARKEN_X86V128(025, 2, 0x003f3f3f)
MULTIPLY_DARKEN_X86V128(0125, 3, 0x001f1f1f)

inline static void multiply_infroot_rgb0_8_x86v128(uint32_t* framebuffer,
                                                   size_t length) {
    __m128i white = _mm_set1_epi32(0x00ffffff);
    for (size_t i = 0; i < length; i += 4) {
        __m128i fb_4px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
        fb_4px = _mm_and_si128(fb_4px, white);
        fb_4px = _mm_cmpeq_epi32(fb_4px, white);
        _mm_storeu_si128((__m128i*)&framebuffer[i], fb_4px);
    }
}

inline static void multiply_infsquare_rgb0_8_x86v128(uint32_t* framebuffer,
                                                     size_t length) {
    __m128i mask = _mm_set1_epi32(0x00ffffff);
    __m128i black = _mm_setzero_si128();
    for (size_t i = 0; i < length; i += 4) {
        __m128i fb_4px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
        fb_4px = _mm_and_si128(fb_4px, mask);
        fb_4px = _mm_cmpgt_epi32(fb_4px, black);
        _mm_storeu_si128((__m128i*)&framebuffer[i], fb_4px);
    }
}
#endif  // SIMD_MODE_X86_SSE

int E_Multiplier::render(char[2][2][576],
                         int is_beat,
                         int* framebuffer,
                         int*,
                         int w,
                         int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }

    size_t length = w * h;
    auto fb = (uint32_t*)framebuffer;
    switch (config.multiply) {
#ifdef SIMD_MODE_X86_SSE
        case MULTIPLY_INF_ROOT: multiply_infroot_rgb0_8_x86v128(fb, length); break;
        case MULTIPLY_X8: multiply_x8_rgb0_8_x86v128(fb, length); break;
        case MULTIPLY_X4: multiply_x4_rgb0_8_x86v128(fb, length); break;
        case MULTIPLY_X2: multiply_x2_rgb0_8_x86v128(fb, length); break;
        case MULTIPLY_X05: multiply_x05_rgb0_8_x86v128(fb, length); break;
        case MULTIPLY_X025: multiply_x025_rgb0_8_x86v128(fb, length); break;
        case MULTIPLY_X0125: multiply_x0125_rgb0_8_x86v128(fb, length); break;
        case MULTIPLY_INF_SQUARE: multiply_infsquare_rgb0_8_x86v128(fb, length); break;
#else
        case MULTIPLY_INF_ROOT: multiply_infroot_rgb0_8_c(fb, length); break;
        case MULTIPLY_X8: multiply_x8_rgb0_8_c(fb, length); break;
        case MULTIPLY_X4: multiply_x4_rgb0_8_c(fb, length); break;
        case MULTIPLY_X2: multiply_x2_rgb0_8_c(fb, length); break;
        case MULTIPLY_X05: multiply_x05_rgb0_8_c(fb, length); break;
        case MULTIPLY_X025: multiply_x025_rgb0_8_c(fb, length); break;
        case MULTIPLY_X0125: multiply_x0125_rgb0_8_c(fb, length); break;
        case MULTIPLY_INF_SQUARE: multiply_infsquare_rgb0_8_c(fb, length); break;
#endif  // SIMD_MODE_...
        default: break;
    }
    return 0;
}

void E_Multiplier::load_legacy(unsigned char* data, int len) {
    if (len == sizeof(uint32_t)) {
        this->config.multiply = *(uint32_t*)data;
    } else {
        this->config.multiply = MULTIPLY_X2;
    }
}

int E_Multiplier::save_legacy(unsigned char* data) {
    *(uint32_t*)data = (uint32_t)this->config.multiply;
    return sizeof(uint32_t);
}

Effect_Info* create_Multiplier_Info() { return new Multiplier_Info(); }
Effect* create_Multiplier(AVS_Instance* avs) { return new E_Multiplier(avs); }
void set_Multiplier_desc(char* desc) { E_Multiplier::set_desc(desc); }
