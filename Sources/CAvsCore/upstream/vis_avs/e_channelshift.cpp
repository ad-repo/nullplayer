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
#include "e_channelshift.h"

#include "tmmintrin.h"

#include "../util.h"

#include <time.h>

constexpr Parameter ChannelShift_Info::parameters[];

E_ChannelShift::E_ChannelShift(AVS_Instance* avs) : Configurable_Effect(avs) {
    srand(time(0));
}

E_ChannelShift::~E_ChannelShift() {}

void E_ChannelShift::shift(int* framebuffer, int l) {
    uint8_t* pxl;
    uint32_t src_pxl;
    uint8_t* src;
    switch (this->config.mode) {
        default:
        case CHANSHIFT_MODE_RGB: {
            return;
        }
        case CHANSHIFT_MODE_GBR: {
            for (int i = 0; i < l; i++) {
                src_pxl = framebuffer[i];
                pxl = (uint8_t*)&framebuffer[i];
                src = (uint8_t*)&src_pxl;
                pxl[3] = src[3];
                pxl[2] = src[1];
                pxl[1] = src[0];
                pxl[0] = src[2];
            }
            break;
        }
        case CHANSHIFT_MODE_BRG: {
            for (int i = 0; i < l; i++) {
                src_pxl = framebuffer[i];
                pxl = (uint8_t*)&framebuffer[i];
                src = (uint8_t*)&src_pxl;
                pxl[3] = src[3];
                pxl[2] = src[0];
                pxl[1] = src[2];
                pxl[0] = src[1];
            }
            break;
        }
        case CHANSHIFT_MODE_RBG: {
            for (int i = 0; i < l; i++) {
                src_pxl = framebuffer[i];
                pxl = (uint8_t*)&framebuffer[i];
                src = (uint8_t*)&src_pxl;
                pxl[3] = src[3];
                pxl[2] = src[2];
                pxl[1] = src[0];
                pxl[0] = src[1];
            }
            break;
        }
        case CHANSHIFT_MODE_BGR: {
            for (int i = 0; i < l; i++) {
                src_pxl = framebuffer[i];
                pxl = (uint8_t*)&framebuffer[i];
                src = (uint8_t*)&src_pxl;
                pxl[3] = src[3];
                pxl[2] = src[0];
                pxl[1] = src[1];
                pxl[0] = src[2];
            }
            break;
        }
        case CHANSHIFT_MODE_GRB: {
            for (int i = 0; i < l; i++) {
                src_pxl = framebuffer[i];
                pxl = (uint8_t*)&framebuffer[i];
                src = (uint8_t*)&src_pxl;
                pxl[3] = src[3];
                pxl[2] = src[1];
                pxl[1] = src[2];
                pxl[0] = src[0];
            }
            break;
        }
    }
}

void E_ChannelShift::shift_ssse3(int* framebuffer, int l) {
    __m128i four_px;
    switch (this->config.mode) {
        default:
        case CHANSHIFT_MODE_RGB: {
            return;
        }
        case CHANSHIFT_MODE_GBR: {
            static __m128i shuffle_gbr =
                _mm_set_epi32(0x0f0d0c0e, 0x0b09080a, 0x07050406, 0x03010002);
            for (int i = 0; i < l; i += 4) {
                four_px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
                four_px = _mm_shuffle_epi8(four_px, shuffle_gbr);
                _mm_store_si128((__m128i*)&framebuffer[i], four_px);
            }
            break;
        }
        case CHANSHIFT_MODE_BRG: {
            static __m128i shuffle_brg =
                _mm_set_epi32(0x0f0c0e0d, 0x0b080a09, 0x07040605, 0x03000201);
            for (int i = 0; i < l; i += 4) {
                four_px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
                four_px = _mm_shuffle_epi8(four_px, shuffle_brg);
                _mm_store_si128((__m128i*)&framebuffer[i], four_px);
            }
            break;
        }
        case CHANSHIFT_MODE_RBG: {
            static __m128i shuffle_rbg =
                _mm_set_epi32(0x0f0e0c0d, 0x0b0a0809, 0x07060405, 0x03020001);
            for (int i = 0; i < l; i += 4) {
                four_px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
                four_px = _mm_shuffle_epi8(four_px, shuffle_rbg);
                _mm_store_si128((__m128i*)&framebuffer[i], four_px);
            }
            break;
        }
        case CHANSHIFT_MODE_BGR: {
            static __m128i shuffle_bgr =
                _mm_set_epi32(0x0f0c0d0e, 0x0b08090a, 0x07040506, 0x03000102);
            for (int i = 0; i < l; i += 4) {
                four_px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
                four_px = _mm_shuffle_epi8(four_px, shuffle_bgr);
                _mm_store_si128((__m128i*)&framebuffer[i], four_px);
            }
            break;
        }
        case CHANSHIFT_MODE_GRB: {
            static __m128i shuffle_grb =
                _mm_set_epi32(0x0f0d0e0c, 0x0b090a08, 0x07050604, 0x03010200);
            for (int i = 0; i < l; i += 4) {
                four_px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
                four_px = _mm_shuffle_epi8(four_px, shuffle_grb);
                _mm_store_si128((__m128i*)&framebuffer[i], four_px);
            }
            break;
        }
    }
}

int E_ChannelShift::render(char[2][2][576],
                           int is_beat,
                           int* framebuffer,
                           int*,
                           int w,
                           int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }

    if (is_beat && this->config.on_beat_random) {
        this->config.mode = rand() % 6;
    }

    int l = w * h;
    this->shift_ssse3(framebuffer, l);
    return 0;
}

// historically, these were the radio buttons' resource IDs, hence the weird numbers.
enum ChannelShift_Legacy_Modes {
    CHANSHIFT_LEGACY_RBG = 1020,
    CHANSHIFT_LEGACY_BRG = 1019,
    CHANSHIFT_LEGACY_BGR = 1021,
    CHANSHIFT_LEGACY_GBR = 1018,
    CHANSHIFT_LEGACY_GRB = 1022,
    CHANSHIFT_LEGACY_RGB = 1183,
};

void E_ChannelShift::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= ssizeof32(uint32_t)) {
        uint32_t mode = *(uint32_t*)&data[pos];
        switch (mode) {
            case CHANSHIFT_LEGACY_RBG: this->config.mode = CHANSHIFT_MODE_RBG; break;
            case CHANSHIFT_LEGACY_BRG: this->config.mode = CHANSHIFT_MODE_BRG; break;
            case CHANSHIFT_LEGACY_BGR: this->config.mode = CHANSHIFT_MODE_BGR; break;
            case CHANSHIFT_LEGACY_GBR: this->config.mode = CHANSHIFT_MODE_GBR; break;
            case CHANSHIFT_LEGACY_GRB: this->config.mode = CHANSHIFT_MODE_GRB; break;
            default:
            case CHANSHIFT_LEGACY_RGB: this->config.mode = CHANSHIFT_MODE_RGB; break;
        }
        pos += sizeof(uint32_t);
    }
    if (len - pos >= ssizeof32(uint32_t)) {
        this->config.on_beat_random = *(uint32_t*)&data[pos] != 0;
        pos += sizeof(uint32_t);
    }
}

int E_ChannelShift::save_legacy(unsigned char* data) {
    int pos = 0;
    switch (this->config.mode) {
        case CHANSHIFT_MODE_RBG: *(uint32_t*)&data[pos] = CHANSHIFT_LEGACY_RBG; break;
        case CHANSHIFT_MODE_BRG: *(uint32_t*)&data[pos] = CHANSHIFT_LEGACY_BRG; break;
        case CHANSHIFT_MODE_BGR: *(uint32_t*)&data[pos] = CHANSHIFT_LEGACY_BGR; break;
        case CHANSHIFT_MODE_GBR: *(uint32_t*)&data[pos] = CHANSHIFT_LEGACY_GBR; break;
        case CHANSHIFT_MODE_GRB: *(uint32_t*)&data[pos] = CHANSHIFT_LEGACY_GRB; break;
        default:
        case CHANSHIFT_MODE_RGB: *(uint32_t*)&data[pos] = CHANSHIFT_LEGACY_RGB; break;
    }
    pos += sizeof(uint32_t);
    *(uint32_t*)&data[pos] = this->config.on_beat_random;
    pos += sizeof(uint32_t);
    return pos;
}

Effect_Info* create_ChannelShift_Info() { return new ChannelShift_Info(); }
Effect* create_ChannelShift(AVS_Instance* avs) { return new E_ChannelShift(avs); }
void set_ChannelShift_desc(char* desc) { E_ChannelShift::set_desc(desc); }
