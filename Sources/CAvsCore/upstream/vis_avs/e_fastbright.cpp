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
#include "e_fastbright.h"

#include <immintrin.h>

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))
#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

constexpr Parameter FastBright_Info::parameters[];

E_FastBright::E_FastBright(AVS_Instance* avs) : Configurable_Effect(avs) {
#ifndef SIMD_MODE_X86_SSE
    int x;
    for (x = 0; x < 128; x++) {
        tab[0][x] = x + x;
        tab[1][x] = x << 9;
        tab[2][x] = x << 17;
    }
    for (; x < 256; x++) {
        tab[0][x] = 255;
        tab[1][x] = 255 << 8;
        tab[2][x] = 255 << 16;
    }
#endif
}

E_FastBright::~E_FastBright() {}

int E_FastBright::render(char[2][2][576],
                         int is_beat,
                         int* framebuffer,
                         int*,
                         int w,
                         int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }
#ifndef SIMD_MODE_X86_SSE
    // the non simd version really isn't in any terms faster than normal brightness
    // with no exclusions turned on
    {
        unsigned int* t = (unsigned int*)framebuffer;
        int x;
        unsigned int mask = 0x7F7F7F7F;

        x = w * h / 2;
        if (this->config.multiply == FASTBRIGHT_MULTIPLY_DOUBLE) {
            while (x--) {
                unsigned int v1 = t[0];
                unsigned int v2 = t[1];
                v1 = tab[0][v1 & 0xff] | tab[1][(v1 >> 8) & 0xff]
                     | tab[2][(v1 >> 16) & 0xff] | (v1 & 0xff000000);
                v2 = tab[0][v2 & 0xff] | tab[1][(v2 >> 8) & 0xff]
                     | tab[2][(v2 >> 16) & 0xff] | (v2 & 0xff000000);
                t[0] = v1;
                t[1] = v2;
                t += 2;
            }
        } else if (this->config.multiply == FASTBRIGHT_MULTIPLY_HALF) {
            while (x--) {
                unsigned int v1 = t[0] >> 1;
                unsigned int v2 = t[1] >> 1;
                t[0] = v1 & mask;
                t[1] = v2 & mask;
                t += 2;
            }
        }
    }
#else
    size_t len = w * h;
    switch (this->config.multiply) {
        case FASTBRIGHT_MULTIPLY_DOUBLE:
            for (size_t i = 0; i < len; i += 4) {
                __m128i fb_4px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
                fb_4px = _mm_adds_epu8(fb_4px, fb_4px);
                _mm_storeu_si128((__m128i*)&framebuffer[i], fb_4px);
            }
            break;
        case FASTBRIGHT_MULTIPLY_HALF: {
            const __m128i mask = _mm_set1_epi32(0x7F7F7F7F);
            for (size_t i = 0; i < len; i += 4) {
                __m128i fb_4px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
                fb_4px = _mm_srli_epi16(fb_4px, 1);
                fb_4px = _mm_and_si128(fb_4px, mask);
                _mm_storeu_si128((__m128i*)&framebuffer[i], fb_4px);
            }
            break;
        }
        default: break;
    }
#endif
    return 0;
}

void E_FastBright::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    this->config.multiply = FASTBRIGHT_MULTIPLY_DOUBLE;
    if (len - pos >= 4) {
        int64_t multiply = GET_INT();
        if (multiply == 2) {
            this->enabled = false;
        } else if (multiply == 1) {
            this->config.multiply = FASTBRIGHT_MULTIPLY_HALF;
        }
        pos += 4;
    }
}

int E_FastBright::save_legacy(unsigned char* data) {
    int pos = 0;
    if (this->enabled) {
        PUT_INT(this->config.multiply);
    } else {
        PUT_INT(2);
    }
    pos += 4;
    return pos;
}

Effect_Info* create_FastBright_Info() { return new FastBright_Info(); }
Effect* create_FastBright(AVS_Instance* avs) { return new E_FastBright(avs); }
void set_FastBright_desc(char* desc) { E_FastBright::set_desc(desc); }
