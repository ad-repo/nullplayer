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
#include "e_clearscreen.h"

#include "blend.h"

#include <stdlib.h>

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

constexpr Parameter ClearScreen_Info::parameters[];

void ClearScreen_Info::on_only_first(Effect* component,
                                     const Parameter*,
                                     const std::vector<int64_t>&) {
    ((E_ClearScreen*)component)->reset_fcounter_on_only_first();
}

E_ClearScreen::E_ClearScreen(AVS_Instance* avs)
    : Configurable_Effect(avs), frame_counter(0) {}

void E_ClearScreen::reset_fcounter_on_only_first() {
    if (this->config.only_first) {
        this->frame_counter = 0;
    }
}

int E_ClearScreen::render(char[2][2][576],
                          int is_beat,
                          int* framebuffer,
                          int*,
                          int w,
                          int h) {
    int i = w * h;
    auto p = (uint32_t*)framebuffer;

    if (this->config.only_first && frame_counter) {
        return 0;
    }
    if (is_beat & 0x80000000) {
        return 0;
    }

    frame_counter++;
    auto color_rgb0_8 = (uint32_t)(this->config.color & 0x00ffffff);

    switch (this->config.blend_mode) {
        case CLEAR_BLEND_DEFAULT: blend_default_fill(color_rgb0_8, p, w * h); break;
        case CLEAR_BLEND_ADDITIVE: blend_add_fill(color_rgb0_8, p, w * h); break;
        case CLEAR_BLEND_5050: blend_5050_fill(color_rgb0_8, p, w * h); break;
        default: [[fallthrough]];
        case CLEAR_BLEND_REPLACE: blend_replace_fill(color_rgb0_8, p, w * h); break;
    }
    return 0;
}

void E_ClearScreen::load_legacy(unsigned char* data, int len) {
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
        this->config.blend_mode = CLEAR_BLEND_5050;
    } else {
        switch (blend) {
            default:
            case 0: this->config.blend_mode = CLEAR_BLEND_REPLACE; break;
            case 1: this->config.blend_mode = CLEAR_BLEND_ADDITIVE; break;
            case 2: this->config.blend_mode = CLEAR_BLEND_DEFAULT; break;
        }
    }
    if (len - pos >= 4) {
        this->config.only_first = GET_INT();
        pos += 4;
    }
}

int E_ClearScreen::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->enabled);
    pos += 4;
    PUT_INT(this->config.color);
    pos += 4;
    switch (this->config.blend_mode) {
        case CLEAR_BLEND_REPLACE:
            PUT_INT(0);
            pos += 4;
            PUT_INT(0);
            break;
        case CLEAR_BLEND_ADDITIVE:
            PUT_INT(1);
            pos += 4;
            PUT_INT(0);
            break;
        case CLEAR_BLEND_5050:
            PUT_INT(0);
            pos += 4;
            PUT_INT(1);
            break;
        case CLEAR_BLEND_DEFAULT:
            PUT_INT(2);
            pos += 4;
            PUT_INT(0);
            break;
    }
    pos += 4;
    PUT_INT(this->config.only_first);
    pos += 4;
    return pos;
}

Effect_Info* create_ClearScreen_Info() { return new ClearScreen_Info(); }
Effect* create_ClearScreen(AVS_Instance* avs) { return new E_ClearScreen(avs); }
void set_ClearScreen_desc(char* desc) { E_ClearScreen::set_desc(desc); }
