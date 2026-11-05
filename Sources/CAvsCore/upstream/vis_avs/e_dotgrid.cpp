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
#include "e_dotgrid.h"

#include "blend.h"
#include "pixel_format.h"

#include <cstdint>

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255
#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter DotGrid_Info::color_params[];
constexpr Parameter DotGrid_Info::parameters[];

void DotGrid_Info::zero_speed_x(Effect* component,
                                const Parameter*,
                                const std::vector<int64_t>&) {
    ((E_DotGrid*)component)->zero_speed_x();
}

void DotGrid_Info::zero_speed_y(Effect* component,
                                const Parameter*,
                                const std::vector<int64_t>&) {
    ((E_DotGrid*)component)->zero_speed_y();
}

E_DotGrid::E_DotGrid(AVS_Instance* avs)
    : Configurable_Effect(avs), current_color_pos(0), xp(0), yp(0) {}

void E_DotGrid::zero_speed_x() { this->config.speed_x = 0; }
void E_DotGrid::zero_speed_y() { this->config.speed_y = 0; }

int E_DotGrid::render(char[2][2][576],
                      int is_beat,
                      int* framebuffer,
                      int*,
                      int w,
                      int h) {
    int32_t x;
    int32_t y;
    uint32_t current_color;

    if (is_beat & 0x80000000) {
        return 0;
    }
    if (this->config.colors.empty()) {
        return 0;
    }
    this->current_color_pos++;
    if (this->current_color_pos >= this->config.colors.size() * 64) {
        this->current_color_pos = 0;
    }

    uint32_t p = this->current_color_pos / 64;
    int32_t r = (int32_t)this->current_color_pos & 63;
    pixel_rgb0_8 c1;
    pixel_rgb0_8 c2;
    int32_t r1;
    int32_t r2;
    int32_t r3;
    c1 = this->config.colors[p].color;
    if (p + 1 < this->config.colors.size()) {
        c2 = this->config.colors[p + 1].color;
    } else {
        c2 = this->config.colors[0].color;
    }

    r1 = (((c1 & 255) * (63 - r)) + ((c2 & 255) * r)) / 64;
    r2 = ((((c1 >> 8) & 255) * (63 - r)) + (((c2 >> 8) & 255) * r)) / 64;
    r3 = ((((c1 >> 16) & 255) * (63 - r)) + (((c2 >> 16) & 255) * r)) / 64;

    current_color = r1 | (r2 << 8) | (r3 << 16);
    if (this->config.spacing < 2) {
        this->config.spacing = 2;
    }
    while (yp < 0) {
        yp += (int32_t)this->config.spacing * 256;
    }
    while (xp < 0) {
        xp += (int32_t)this->config.spacing * 256;
    }

    int32_t sy = (yp >> 8) % (int32_t)this->config.spacing;
    int32_t sx = (xp >> 8) % (int32_t)this->config.spacing;
    auto dest = (uint32_t*)framebuffer;
    dest += sy * w;
    for (y = sy; y < h; y += (int32_t)this->config.spacing) {
        if (this->config.blend_mode == DOTGRID_BLEND_ADDITIVE) {
            for (x = sx; x < w; x += (int32_t)this->config.spacing) {
                blend_add_1px(&current_color, &dest[x], &dest[x]);
            }
        } else if (this->config.blend_mode == DOTGRID_BLEND_5050) {
            for (x = sx; x < w; x += (int32_t)this->config.spacing) {
                blend_5050_1px(&current_color, &dest[x], &dest[x]);
            }
        } else if (this->config.blend_mode == DOTGRID_BLEND_DEFAULT) {
            for (x = sx; x < w; x += (int32_t)this->config.spacing) {
                blend_default_1px(&current_color, &dest[x], &dest[x]);
            }
        } else {  // DOTGRID_BLEND_REPLACE
            for (x = sx; x < w; x += (int32_t)this->config.spacing) {
                blend_replace_1px(&current_color, &dest[x]);
            }
        }
        dest += w * this->config.spacing;
    }
    xp += (int32_t)this->config.speed_x;
    yp += (int32_t)this->config.speed_y;

    return 0;
}

void E_DotGrid::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    uint32_t num_colors = 0;
    if (len - pos >= 4) {
        num_colors = GET_INT();
        pos += 4;
    }
    this->config.colors.clear();
    if (num_colors <= 16) {
        for (uint32_t x = 0; len - pos >= 4 && x < num_colors; x++) {
            uint32_t color = GET_INT();
            this->config.colors.emplace_back(color);
            pos += 4;
        }
    }
    if (len - pos >= 4) {
        this->config.spacing = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.speed_x = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.speed_y = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.blend_mode = GET_INT();
        pos += 4;
    }
}

int E_DotGrid::save_legacy(unsigned char* data) {
    int pos = 0;
    uint32_t num_colors = this->config.colors.size();
    PUT_INT(num_colors);
    pos += 4;
    for (auto const& color : this->config.colors) {
        PUT_INT(color.color);
        pos += 4;
    }
    PUT_INT(this->config.spacing);
    pos += 4;
    PUT_INT(this->config.speed_x);
    pos += 4;
    PUT_INT(this->config.speed_y);
    pos += 4;
    PUT_INT(this->config.blend_mode);
    pos += 4;
    return pos;
}

Effect_Info* create_DotGrid_Info() { return new DotGrid_Info(); }
Effect* create_DotGrid(AVS_Instance* avs) { return new E_DotGrid(avs); }
void set_DotGrid_desc(char* desc) { E_DotGrid::set_desc(desc); }
