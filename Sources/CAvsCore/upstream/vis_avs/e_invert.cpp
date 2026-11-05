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
#include "e_invert.h"

#include <immintrin.h>
#include <stdlib.h>

E_Invert::E_Invert(AVS_Instance* avs) : Configurable_Effect(avs) {}
E_Invert::~E_Invert() {}

static void render_c(int* framebuffer, int length) {
    for (int i = 0; i < length; i++) {
        framebuffer[i] ^= 0xffffff;
    }
}

static void render_simd(int* framebuffer, int length) {
    __m128i mask = _mm_set1_epi32(0xffffff);
    for (int i = 0; i < length; i += 4) {
        __m128i four_px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
        four_px = _mm_xor_si128(four_px, mask);
        _mm_store_si128((__m128i*)&framebuffer[i], four_px);
    }
}

int E_Invert::render(char[2][2][576],
                     int is_beat,
                     int* framebuffer,
                     int*,
                     int w,
                     int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }
    if (!enabled) {
        return 0;
    }
#ifdef SIMD_MODE_X86_SSE
    render_simd(framebuffer, w * h);
#else
    render_c(framebuffer, w * h);
#endif
    return 0;
}

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))
void E_Invert::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        enabled = GET_INT();
        pos += 4;
    }
}

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255
int E_Invert::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(enabled);
    pos += 4;
    return pos;
}

Effect_Info* create_Invert_Info() { return new Invert_Info(); }
Effect* create_Invert(AVS_Instance* avs) { return new E_Invert(avs); }
void set_Invert_desc(char* desc) { E_Invert::set_desc(desc); }
