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
#include "e_onbeatclear.h"

#include "blend.h"
#include "effect_common.h"
#include "pixel_format.h"

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255
#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter OnBeatClear_Info::parameters[];

E_OnBeatClear::E_OnBeatClear(AVS_Instance* avs)
    : Configurable_Effect(avs), beat_counter(0) {}

int E_OnBeatClear::render(char[2][2][576],
                          int is_beat,
                          int* framebuffer,
                          int*,
                          int w,
                          int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }

    if (is_beat && this->config.every_n_beats > 0) {
        if (++this->beat_counter >= this->config.every_n_beats) {
            this->beat_counter = 0;
            int i = w * h;
            auto dest = (uint32_t*)framebuffer;
            uint32_t c = this->config.color & AVS_PIXEL_COLOR_MASK_RGB0_8;
            switch (this->config.blend_mode) {
                default:
                case BLEND_SIMPLE_REPLACE: blend_replace_fill(c, dest, i); break;
                case BLEND_SIMPLE_5050: blend_5050_fill(c, dest, i); break;
            }
        }
    }
    return 0;
}

void E_OnBeatClear::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->config.color = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.blend_mode = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.every_n_beats = GET_INT();
        pos += 4;
    }
}

int E_OnBeatClear::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->config.color);
    pos += 4;
    PUT_INT(this->config.blend_mode);
    pos += 4;
    PUT_INT(this->config.every_n_beats);
    pos += 4;
    return pos;
}

Effect_Info* create_OnBeatClear_Info() { return new OnBeatClear_Info(); }
Effect* create_OnBeatClear(AVS_Instance* avs) { return new E_OnBeatClear(avs); }
void set_OnBeatClear_desc(char* desc) { E_OnBeatClear::set_desc(desc); }
