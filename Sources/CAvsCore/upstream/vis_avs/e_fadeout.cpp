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
// alphachannel safe 11/21/99
#include "e_fadeout.h"

#include <immintrin.h>

constexpr Parameter Fadeout_Info::parameters[];

void maketab(Effect* component, const Parameter*, const std::vector<int64_t>&) {
    E_Fadeout* fadeout = (E_Fadeout*)component;
    fadeout->maketab();
}

void E_Fadeout::maketab(void) {
    int rseek = this->config.color & 0xff;
    int gseek = (this->config.color >> 8) & 0xff;
    int bseek = (this->config.color >> 16) & 0xff;
    int x;
    for (x = 0; x < 256; x++) {
        int r = x;
        int g = x;
        int b = x;
        if (r <= rseek - this->config.fadelen) {
            r += this->config.fadelen;
        } else if (r >= rseek + this->config.fadelen) {
            r -= this->config.fadelen;
        } else {
            r = rseek;
        }

        if (g <= gseek - this->config.fadelen) {
            g += this->config.fadelen;
        } else if (g >= gseek + this->config.fadelen) {
            g -= this->config.fadelen;
        } else {
            g = gseek;
        }
        if (b <= bseek - this->config.fadelen) {
            b += this->config.fadelen;
        } else if (b >= bseek + this->config.fadelen) {
            b -= this->config.fadelen;
        } else {
            b = bseek;
        }

        fadtab[0][x] = r;
        fadtab[1][x] = g;
        fadtab[2][x] = b;
    }
}

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255
#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))
void E_Fadeout::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->config.fadelen = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.color = GET_INT();
        pos += 4;
    }
    maketab();
}

int E_Fadeout::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->config.fadelen);
    pos += 4;
    PUT_INT(this->config.color);
    pos += 4;
    return pos;
}

E_Fadeout::E_Fadeout(AVS_Instance* avs) : Configurable_Effect(avs) {
    this->config.color = 0;
    this->config.fadelen = 16;
    maketab();
}

E_Fadeout::~E_Fadeout() {}

int E_Fadeout::render(char[2][2][576],
                      int is_beat,
                      int* framebuffer,
                      int*,
                      int w,
                      int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }
    if (!this->config.fadelen) {
        return 0;
    }
    if (this->config.color) {
        unsigned char* t = (unsigned char*)framebuffer;
        int x = w * h;
        while (x--) {
            t[0] = fadtab[0][t[0]];
            t[1] = fadtab[1][t[1]];
            t[2] = fadtab[2][t[2]];
            t += 4;
        }
    } else {
        uint32_t fadelen_noalpha = this->config.fadelen | (this->config.fadelen << 8)
                                   | (this->config.fadelen << 16);
        __m128i adj = _mm_set1_epi32(fadelen_noalpha);
        for (size_t i = 0; i < w * h; i += 4) {
            __m128i fb_4px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
            _mm_storeu_si128((__m128i*)&framebuffer[i], _mm_subs_epu8(fb_4px, adj));
        }
    }
    return 0;
}

Effect_Info* create_Fadeout_Info() { return new Fadeout_Info(); }
Effect* create_Fadeout(AVS_Instance* avs) { return new E_Fadeout(avs); }
void set_Fadeout_desc(char* desc) { E_Fadeout::set_desc(desc); }
