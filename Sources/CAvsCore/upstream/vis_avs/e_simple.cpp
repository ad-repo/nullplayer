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
#include "e_simple.h"

#include "linedraw.h"

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255
#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter Simple_Info::parameters[];
constexpr Parameter Simple_Info::color_params[];

E_Simple::E_Simple(AVS_Instance* avs) : Configurable_Effect(avs) {}
E_Simple::~E_Simple() {}

int E_Simple::render(char visdata[2][2][576],
                     int is_beat,
                     int* framebuffer,
                     int*,
                     int w,
                     int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }
    if (this->config.colors.empty()) {
        return 0;
    }
    int x;
    float yscale = (float)h / 2.0f / 256.0f;
    float xscale = 288.0f / w;
    int current_color;
    unsigned char* fa_data;
    char center_channel[576];
    int y_pos;
    switch (this->config.position) {
        case VPOS_TOP: y_pos = 0; break;
        case VPOS_BOTTOM: y_pos = 1; break;
        default:
        case VPOS_CENTER: y_pos = 2; break;
    }

    this->color_pos++;
    if (this->color_pos >= this->config.colors.size() * 64) {
        this->color_pos = 0;
    }
    uint32_t p = this->color_pos / 64;
    int r = this->color_pos & 63;
    int c1, c2;
    int r1, r2, r3;
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
                center_channel[x] = (signed char)visdata[1][0][x] / 2
                                    + (signed char)visdata[1][1][x] / 2;
            }
        } else {
            for (x = 0; x < 576; x++) {
                center_channel[x] = (unsigned char)visdata[0][0][x] / 2
                                    + (unsigned char)visdata[0][1][x] / 2;
            }
        }
        fa_data = (unsigned char*)center_channel;
    } else {
        fa_data = (unsigned char*)
            visdata[!this->config.audio_source][this->config.audio_channel];
    }

    if (this->config.draw_mode == DRAW_DOTS) {
        if (this->config.audio_source == AUDIO_WAVEFORM) {
            int yh = y_pos * h / 2;
            if (y_pos == 2) {
                yh = h / 4;
            }
            for (x = 0; x < w; x++) {
                float r = x * xscale;
                float s1 = r - (int)r;
                float yr = (fa_data[(int)r] ^ 128) * (1.0f - s1)
                           + (fa_data[(int)r + 1] ^ 128) * (s1);
                int y = yh + (int)(yr * yscale);
                if (y >= 0 && y < h) {
                    framebuffer[x + y * w] = current_color;
                }
            }
        } else { /*dot analyzer*/
            int h2 = h / 2;
            float ys = yscale;
            float xs = 200.0f / w;
            int adj = 1;
            if (y_pos != 1) {
                ys = -ys;
                adj = 0;
            }
            if (y_pos == 2) {
                h2 -= (int)(ys * 256 / 2);
            }
            for (x = 0; x < w; x++) {
                float r = x * xs;
                float s1 = r - (int)r;
                float yr = fa_data[(int)r] * (1.0f - s1) + fa_data[(int)r + 1] * (s1);
                int y = h2 + adj + (int)(yr * ys - 1.0f);
                if (y >= 0 && y < h) {
                    framebuffer[x + w * y] = current_color;
                }
            }
        }
    } else if (this->config.draw_mode == DRAW_LINES) {
        if (this->config.audio_source == AUDIO_WAVEFORM) {
            float xs = 1.0f / xscale;
            int lx, ly, ox, oy;
            int yh;
            if (y_pos == 2) {
                yh = h / 4;
            } else {
                yh = y_pos * h / 2;
            }
            lx = 0;
            ly = yh + (int)((int)(fa_data[0] ^ 128) * yscale);
            ;
            for (x = 1; x < 288; x++) {
                ox = (int)(x * xs);
                oy = yh + (int)((int)(fa_data[x] ^ 128) * yscale);
                line((uint32_t*)framebuffer,
                     lx,
                     ly,
                     ox,
                     oy,
                     w,
                     h,
                     current_color,
                     (g_line_blend_mode & 0xff0000) >> 16);
                lx = ox;
                ly = oy;
            }
        } else { /*line analyzer*/
            int h2 = h / 2;
            int lx, ly, ox, oy;
            float xs = 1.0f / xscale * (288.0f / 200.f);
            float ys = yscale;
            if (y_pos != 1) {
                ys = -ys;
            }
            if (y_pos == 2) {
                h2 -= (int)(ys * 256 / 2);
            }
            ly = h2 + (int)((fa_data[0]) * ys);
            lx = 0;
            for (x = 1; x < 200; x++) {
                oy = h2 + (int)((fa_data[x]) * ys);
                ox = (int)(x * xs);
                line((uint32_t*)framebuffer,
                     lx,
                     ly,
                     ox,
                     oy,
                     w,
                     h,
                     current_color,
                     (g_line_blend_mode & 0xff0000) >> 16);
                ly = oy;
                lx = ox;
            }
        }
    } else { /*solid*/
        if (this->config.audio_source == AUDIO_WAVEFORM) {
            int yh = y_pos * h / 2;
            if (y_pos == 2) {
                yh = h / 4;
            }
            int ys = yh + (int)(yscale * 128.0f);
            for (x = 0; x < w; x++) {
                float r = x * xscale;
                float s1 = r - (int)r;
                float yr = (fa_data[(int)r] ^ 128) * (1.0f - s1)
                           + (fa_data[(int)r + 1] ^ 128) * (s1);
                line((uint32_t*)framebuffer,
                     x,
                     ys - 1,
                     x,
                     yh + (int)(yr * yscale),
                     w,
                     h,
                     current_color,
                     (g_line_blend_mode & 0xff0000) >> 16);
            }
        } else { /*solid analyzer*/
            int h2 = h / 2;
            float ys = yscale;
            float xs = 200.0f / w;
            int adj = 1;
            if (y_pos != 1) {
                ys = -ys;
                adj = 0;
            }
            if (y_pos == 2) {
                h2 -= (int)(ys * 256 / 2);
            }
            for (x = 0; x < w; x++) {
                float r = x * xs;
                float s1 = r - (int)r;
                float yr = fa_data[(int)r] * (1.0f - s1) + fa_data[(int)r + 1] * (s1);
                line((uint32_t*)framebuffer,
                     x,
                     h2 - adj,
                     x,
                     h2 + adj + (int)(yr * ys - 1.0f),
                     w,
                     h,
                     current_color,
                     (g_line_blend_mode & 0xff0000) >> 16);
            }
        }
    }
    return 0;
}

void E_Simple::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    uint32_t effect = 0b101000;  // default: solid spectrum
    if (len - pos >= 4) {
        effect = GET_INT();
        pos += 4;
    }
    this->config.audio_source = (effect & 0b10) ? AUDIO_WAVEFORM : AUDIO_SPECTRUM;
    if (effect & 0b1000000) {  // 7th bit is the second bit of the draw mode
        this->config.draw_mode = DRAW_DOTS;
    } else {
        // This is a quirk of the legacy preset file format, the meaning of the
        // lines-vs-solid bit switches depending on the audio source:
        // With waveform audio, 0 means lines, 1 means solid.
        // With spectrum audio, 1 means solid, 0 means lines.
        if (this->config.audio_source == AUDIO_WAVEFORM) {
            this->config.draw_mode = effect & 0b1 ? DRAW_SOLID : DRAW_LINES;
        } else {
            this->config.draw_mode = effect & 0b1 ? DRAW_LINES : DRAW_SOLID;
        }
    }
    switch (effect & 0b1100) {
        case 0b0000: this->config.audio_channel = AUDIO_LEFT; break;
        case 0b0100: this->config.audio_channel = AUDIO_RIGHT; break;
        default:
        case 0b1000: this->config.audio_channel = AUDIO_CENTER; break;
    }
    switch (effect & 0b110000) {
        case 0b000000: this->config.position = VPOS_TOP; break;
        case 0b010000: this->config.position = VPOS_BOTTOM; break;
        default:
        case 0b100000: this->config.position = VPOS_CENTER; break;
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
}

int E_Simple::save_legacy(unsigned char* data) {
    int pos = 0;
    uint32_t effect = 0;
    // See `load_legacy()` above for the draw_mode/audio_source details.
    switch (this->config.draw_mode) {
        default:
        case DRAW_SOLID:
            effect |= this->config.audio_source == AUDIO_WAVEFORM ? 0b1 : 0b0;
            break;
        case DRAW_LINES:
            effect |= this->config.audio_source == AUDIO_WAVEFORM ? 0b0 : 0b1;
            break;
        case DRAW_DOTS: effect |= 0b1000000; break;
    }
    switch (this->config.audio_source) {
        case AUDIO_WAVEFORM: effect |= 0b10; break;
        default:
        case AUDIO_SPECTRUM: break;
    }
    switch (this->config.audio_channel) {
        case AUDIO_LEFT: break;
        case AUDIO_RIGHT: effect |= 0b0100; break;
        default:
        case AUDIO_CENTER: effect |= 0b1000; break;
    }
    switch (this->config.position) {
        case VPOS_TOP: break;
        case VPOS_BOTTOM: effect |= 0b010000; break;
        default:
        case VPOS_CENTER: effect |= 0b100000; break;
    }
    PUT_INT(effect);
    pos += 4;
    PUT_INT(this->config.colors.size());
    pos += 4;
    for (auto const& color : this->config.colors) {
        PUT_INT(color.color);
        pos += 4;
    }
    return pos;
}

Effect_Info* create_Simple_Info() { return new Simple_Info(); }
Effect* create_Simple(AVS_Instance* avs) { return new E_Simple(avs); }
void set_Simple_desc(char* desc) { E_Simple::set_desc(desc); }
