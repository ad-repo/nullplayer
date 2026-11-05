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
#include "e_timescope.h"

#include "blend.h"

#include <stdio.h>
#include <stdlib.h>

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

constexpr Parameter Timescope_Info::parameters[];

E_Timescope::E_Timescope(AVS_Instance* avs) : Configurable_Effect(avs), position(0) {}

int E_Timescope::render(char visdata[2][2][576],
                        int is_beat,
                        int* framebuffer,
                        int*,
                        int w,
                        int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }

    uint8_t* audio_data;
    int8_t center_channel[576];
    if (this->config.audio_channel == AUDIO_CENTER) {
        for (int32_t i = 0; i < 576; i++) {
            center_channel[i] =
                (uint8_t)visdata[0][0][i] / 2 + (uint8_t)visdata[0][1][i] / 2;
        }
        audio_data = (uint8_t*)center_channel;
    } else {
        audio_data = (uint8_t*)visdata[0][this->config.audio_channel];
    }

    this->position++;
    this->position %= w;
    auto fb = (uint32_t*)framebuffer + this->position;
    uint32_t r, g, b;
    r = (uint32_t)this->config.color & 0xff;
    g = ((uint32_t)this->config.color >> 8) & 0xff;
    b = ((uint32_t)this->config.color >> 16) & 0xff;
    for (int32_t i = 0; i < h; i++) {
        uint32_t px;
        px = audio_data[(i * this->config.bands) / h] & 0xFF;
        px = (r * px) / 256 + (((g * px) / 256) << 8) + (((b * px) / 256) << 16);
        switch (this->config.blend_mode) {
            default:
            case TIMESCOPE_BLEND_DEFAULT: blend_default_1px(&px, fb, fb); break;
            case TIMESCOPE_BLEND_ADDITIVE: blend_add_1px(&px, fb, fb); break;
            case TIMESCOPE_BLEND_5050: blend_5050_1px(&px, fb, fb); break;
            case TIMESCOPE_BLEND_REPLACE: blend_replace_1px(&px, fb); break;
        }
        fb += w;
    }

    return 0;
}

void E_Timescope::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.color = GET_INT();
        pos += 4;
    }
    int32_t blend = 0;
    if (len - pos >= 4) {
        blend = GET_INT();
        pos += 4;
    }
    int32_t blend_5050 = 0;
    if (len - pos >= 4) {
        blend_5050 = GET_INT();
        pos += 4;
    }
    if (blend_5050) {
        this->config.blend_mode = TIMESCOPE_BLEND_5050;
    } else {
        switch (blend) {
            default:
            case 0: this->config.blend_mode = TIMESCOPE_BLEND_REPLACE; break;
            case 1: this->config.blend_mode = TIMESCOPE_BLEND_ADDITIVE; break;
            case 2: this->config.blend_mode = TIMESCOPE_BLEND_DEFAULT; break;
        }
    }
    if (len - pos >= 4) {
        this->config.audio_channel = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.bands = GET_INT();
        pos += 4;
    }
}

int E_Timescope::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->enabled);
    pos += 4;
    PUT_INT(this->config.color);
    pos += 4;
    switch (this->config.blend_mode) {
        case TIMESCOPE_BLEND_REPLACE:
            PUT_INT(0);
            pos += 4;
            PUT_INT(0);
            break;
        case TIMESCOPE_BLEND_ADDITIVE:
            PUT_INT(1);
            pos += 4;
            PUT_INT(0);
            break;
        case TIMESCOPE_BLEND_5050:
            PUT_INT(0);
            pos += 4;
            PUT_INT(1);
            break;
        case TIMESCOPE_BLEND_DEFAULT:
            PUT_INT(2);
            pos += 4;
            PUT_INT(0);
            break;
    }
    pos += 4;
    PUT_INT(this->config.audio_channel);
    pos += 4;
    PUT_INT(this->config.bands);
    pos += 4;
    return pos;
}

Effect_Info* create_Timescope_Info() { return new Timescope_Info(); }
Effect* create_Timescope(AVS_Instance* avs) { return new E_Timescope(avs); }
void set_Timescope_desc(char* desc) { E_Timescope::set_desc(desc); }
