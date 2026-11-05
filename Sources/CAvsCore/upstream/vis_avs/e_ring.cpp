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
#include "e_ring.h"

#include "effect_common.h"
#include "linedraw.h"
#include "pixel_format.h"

#include <math.h>

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter Ring_Info::color_params[];
constexpr Parameter Ring_Info::parameters[];

E_Ring::E_Ring(AVS_Instance* avs) : Configurable_Effect(avs), current_color_pos(0) {}

int E_Ring::render(char visdata[2][2][576],
                   int is_beat,
                   int* framebuffer,
                   int*,
                   int w,
                   int h) {
    uint32_t x;
    pixel_rgb0_8 current_color;
    uint8_t* fa_data;
    int8_t center_channel[576];

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

    if (this->config.audio_channel == AUDIO_CENTER) {
        if (this->config.audio_source == AUDIO_WAVEFORM) {
            for (x = 0; x < 576; x++) {
                center_channel[x] =
                    (int8_t)visdata[1][0][x] / 2 + (int8_t)visdata[1][1][x] / 2;
            }
        } else {
            for (x = 0; x < 576; x++) {
                center_channel[x] =
                    (uint8_t)visdata[0][0][x] / 2 + (uint8_t)visdata[0][1][x] / 2;
            }
        }
        fa_data = (uint8_t*)center_channel;
    } else {
        fa_data =
            (uint8_t*)visdata[!this->config.audio_source][this->config.audio_channel];
    }

    double fsize = this->config.size / 32.0;
    int lx, ly;
    double size_px = min((h * fsize), (w * fsize));
    int c_x;
    int c_y = h / 2;
    if (this->config.position == HPOS_CENTER) {
        c_x = w / 2;
    } else if (this->config.position == HPOS_LEFT) {
        c_x = (w / 4);
    } else {  // HPOS_RIGHT
        c_x = w / 2 + w / 4;
    }
    int q = 0;
    double a = 0.0;
    double sca;
    if (this->config.audio_source == AUDIO_WAVEFORM) {
        sca = 0.1 + ((fa_data[q] ^ 128) / 255.0) * 0.9;
    } else {
        sca = 0.1 + ((fa_data[q * 2] / 2 + fa_data[q * 2 + 1] / 2) / 255.0) * 0.9;
    }
    int n_seg = 1;
    lx = c_x + (cos(a) * size_px * sca);
    ly = c_y + (sin(a) * size_px * sca);

    for (q = 1; q <= 80; q += n_seg) {
        int tx, ty;
        a -= 3.14159 * 2.0 / 80.0 * n_seg;
        if (this->config.audio_source == AUDIO_WAVEFORM) {
            sca = 0.1 + ((fa_data[q > 40 ? 80 - q : q] ^ 128) / 255.0) * 0.90;
        } else {
            sca = 0.1
                  + ((fa_data[q > 40 ? (80 - q) * 2 : q * 2] / 2
                      + fa_data[q > 40 ? (80 - q) * 2 + 1 : q * 2 + 1] / 2)
                     / 255.0)
                        * 0.9;
        }
        tx = c_x + (cos(a) * size_px * sca);
        ty = c_y + (sin(a) * size_px * sca);

        if ((tx >= 0 && tx < w && ty >= 0 && ty < h)
            || (lx >= 0 && lx < w && ly >= 0 && ly < h)) {
            line((uint32_t*)framebuffer,
                 tx,
                 ty,
                 lx,
                 ly,
                 w,
                 h,
                 current_color,
                 (g_line_blend_mode & 0xff0000) >> 16);
        }
        // line((uint32_t*)framebuffer, tx, ty, c_x, c_y, w, h, current_color);
        // if (tx >= 0 && tx < w && ty >= 0 && ty < h) {
        //     framebuffer[tx + ty * w] = current_color;
        // }
        lx = tx;
        ly = ty;
    }
    return 0;
}

void E_Ring::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    uint32_t channel_and_position = 0;
    if (len - pos >= 4) {
        channel_and_position = GET_INT();
        pos += 4;
    }
    switch (channel_and_position & 0b1100) {
        case 0b0000: this->config.audio_channel = AUDIO_LEFT; break;
        case 0b0100: this->config.audio_channel = AUDIO_RIGHT; break;
        default:
        case 0b1000: this->config.audio_channel = AUDIO_CENTER; break;
    }
    switch (channel_and_position & 0b110000) {
        case 0b000000: this->config.position = HPOS_LEFT; break;
        case 0b010000: this->config.position = HPOS_RIGHT; break;
        default:
        case 0b100000: this->config.position = HPOS_CENTER; break;
    }
    uint32_t num_colors = 0;
    if (len - pos >= 4) {
        num_colors = GET_INT();
        pos += 4;
    }
    this->config.colors.clear();
    if (num_colors <= 16) {
        for (uint32_t i = 0; len - pos >= 4 && i < num_colors; i++) {
            uint32_t color = GET_INT();
            this->config.colors.emplace_back(color);
            pos += 4;
        }
    }
    if (len - pos >= 4) {
        this->config.size = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.audio_source = GET_INT() ? AUDIO_SPECTRUM : AUDIO_WAVEFORM;
        pos += 4;
    }
}

int E_Ring::save_legacy(unsigned char* data) {
    int pos = 0;
    uint32_t channel_and_position = 0;
    switch (this->config.audio_channel) {
        case AUDIO_LEFT: break;
        case AUDIO_RIGHT: channel_and_position |= 0b0100; break;
        default:
        case AUDIO_CENTER: channel_and_position |= 0b1000; break;
    }
    switch (this->config.position) {
        case HPOS_LEFT: break;
        case HPOS_RIGHT: channel_and_position |= 0b010000; break;
        default:
        case HPOS_CENTER: channel_and_position |= 0b100000; break;
    }
    PUT_INT(channel_and_position);
    pos += 4;
    PUT_INT(this->config.colors.size());
    pos += 4;
    for (auto const& color : this->config.colors) {
        PUT_INT(color.color);
        pos += 4;
    }
    PUT_INT(this->config.size);
    pos += 4;
    bool audio_source = this->config.audio_source == AUDIO_SPECTRUM;
    PUT_INT(audio_source);
    pos += 4;
    return pos;
}

Effect_Info* create_Ring_Info() { return new Ring_Info(); }
Effect* create_Ring(AVS_Instance* avs) { return new E_Ring(avs); }
void set_Ring_desc(char* desc) { E_Ring::set_desc(desc); }
