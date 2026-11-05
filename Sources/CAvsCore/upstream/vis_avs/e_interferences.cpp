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
#include "e_interferences.h"

#include "blend.h"

#include <math.h>
#include <stdlib.h>

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

void PUT_FLOAT(float f, unsigned char* data, int pos) {
    unsigned char* y = (unsigned char*)&f;
    data[pos] = y[0];
    data[pos + 1] = y[1];
    data[pos + 2] = y[2];
    data[pos + 3] = y[3];
}

float GET_FLOAT(unsigned char* data, int pos) {
    float f;
    unsigned char* a = (unsigned char*)&f;
    a[0] = data[pos];
    a[1] = data[pos + 1];
    a[2] = data[pos + 2];
    a[3] = data[pos + 3];
    return f;
}

constexpr Parameter Interferences_Info::parameters[];

void Interferences_Info::on_init_rotation(Effect* component,
                                          const Parameter*,
                                          const std::vector<int64_t>&) {
    auto interferences = (E_Interferences*)component;
    interferences->cur_rotation = interferences->config.init_rotation;
}

E_Interferences::E_Interferences(AVS_Instance* avs)
    : Configurable_Effect(avs), cur_rotation(0), on_beat_fadeout(0.0) {}

inline int lerp(int from, int to, float s) {
    return from + (int)((float)(to - from) * s);
}

int E_Interferences::render(char[2][2][576],
                            int is_beat,
                            int* framebuffer,
                            int* fbout,
                            int w,
                            int h) {
    int x, y;
    int i;
    float s;

    if (is_beat & 0x80000000) {
        return 0;
    }
    auto num_render_layers = this->config.num_layers;
    if (num_render_layers == 0) {
        return 0;
    }

    if (this->config.on_beat && is_beat && this->on_beat_fadeout >= M_PI) {
        this->on_beat_fadeout = 0;
    }
    s = (float)sin(this->on_beat_fadeout);

    int rotation_step = lerp(this->config.rotation, this->config.on_beat_rotation, s);
    int alpha = lerp(this->config.alpha, this->config.on_beat_alpha, s);
    int distance = lerp(this->config.distance, this->config.on_beat_distance, s);

    float angle_step = M_PI * 2 / num_render_layers;
    float angle = (float)this->cur_rotation / 255 * M_PI * 2;

    int xpoints[INTERFERENCES_MAX_POINTS];
    int ypoints[INTERFERENCES_MAX_POINTS];

    int min_x = 0;
    int max_x = 0;
    int min_y = 0;
    int max_y = 0;

    for (i = 0; i < num_render_layers; i++) {
        xpoints[i] = (int)(cos(angle) * distance);
        ypoints[i] = (int)(sin(angle) * distance);
        if (ypoints[i] > min_y) {
            min_y = ypoints[i];
        }
        if (-ypoints[i] > max_y) {
            max_y = -ypoints[i];
        }
        if (xpoints[i] > min_x) {
            min_x = xpoints[i];
        }
        if (-xpoints[i] > max_x) {
            max_x = -xpoints[i];
        }
        angle += angle_step;
    }

    unsigned char* bt = lut_u8_multiply[alpha];

    int* outp = fbout;
    for (y = 0; y < h; y++) {
        int yoffs[INTERFERENCES_MAX_POINTS];
        for (i = 0; i < num_render_layers; i++) {
            if (y >= ypoints[i] && y - ypoints[i] < h) {
                yoffs[i] = (y - ypoints[i]) * w;
            } else {
                yoffs[i] = -1;
            }
        }
        if (this->config.separate_rgb && (num_render_layers % 3 == 0)) {
            if (num_render_layers == 3) {
                for (x = 0; x < w; x++) {
                    int r = 0, g = 0, b = 0;
                    int xp;
                    xp = x - xpoints[0];
                    if (xp >= 0 && xp < w && yoffs[0] != -1) {
                        int pix = framebuffer[xp + yoffs[0]];
                        r = bt[pix & 0xff];
                    }
                    xp = x - xpoints[1];
                    if (xp >= 0 && xp < w && yoffs[1] != -1) {
                        int pix = framebuffer[xp + yoffs[1]];
                        g = bt[(pix >> 8) & 0xff];
                    }
                    xp = x - xpoints[2];
                    if (xp >= 0 && xp < w && yoffs[2] != -1) {
                        int pix = framebuffer[xp + yoffs[2]];
                        b = bt[(pix >> 16) & 0xff];
                    }
                    *outp++ = r | (g << 8) | (b << 16);
                }
            } else {
                for (x = 0; x < w; x++) {
                    int r = 0, g = 0, b = 0;
                    int xp;
                    xp = x - xpoints[0];
                    if (xp >= 0 && xp < w && yoffs[0] != -1) {
                        int pix = framebuffer[xp + yoffs[0]];
                        r = bt[pix & 0xff];
                    }
                    xp = x - xpoints[1];
                    if (xp >= 0 && xp < w && yoffs[1] != -1) {
                        int pix = framebuffer[xp + yoffs[1]];
                        g = bt[(pix >> 8) & 0xff];
                    }
                    xp = x - xpoints[2];
                    if (xp >= 0 && xp < w && yoffs[2] != -1) {
                        int pix = framebuffer[xp + yoffs[2]];
                        b = bt[(pix >> 16) & 0xff];
                    }
                    xp = x - xpoints[3];
                    if (xp >= 0 && xp < w && yoffs[3] != -1) {
                        int pix = framebuffer[xp + yoffs[3]];
                        r += bt[pix & 0xff];
                    }
                    xp = x - xpoints[4];
                    if (xp >= 0 && xp < w && yoffs[4] != -1) {
                        int pix = framebuffer[xp + yoffs[4]];
                        g += bt[(pix >> 8) & 0xff];
                    }
                    xp = x - xpoints[5];
                    if (xp >= 0 && xp < w && yoffs[5] != -1) {
                        int pix = framebuffer[xp + yoffs[5]];
                        b += bt[(pix >> 16) & 0xff];
                    }
                    if (r > 255) {
                        r = 255;
                    }
                    if (g > 255) {
                        g = 255;
                    }
                    if (b > 255) {
                        b = 255;
                    }
                    *outp++ = r | (g << 8) | (b << 16);
                }
            }
        } else if (y > min_y && y < h - max_y && min_x + max_x < w) {
            for (x = 0; x < min_x; x++) {
                int r = 0, g = 0, b = 0;
                for (i = 0; i < num_render_layers; i++) {
                    int xp = x - xpoints[i];
                    if (xp >= 0 && xp < w) {
                        int pix = framebuffer[xp + yoffs[i]];
                        r += bt[pix & 0xff];
                        g += bt[(pix >> 8) & 0xff];
                        b += bt[(pix >> 16) & 0xff];
                    }
                }
                if (r > 255) {
                    r = 255;
                }
                if (g > 255) {
                    g = 255;
                }
                if (b > 255) {
                    b = 255;
                }
                *outp++ = r | (g << 8) | (b << 16);
            }
            int* lfb = framebuffer + x;
            for (; x < w - max_x; x++) {
                int r = 0, g = 0, b = 0;
                for (i = 0; i < num_render_layers; i++) {
                    int pix = lfb[yoffs[i] - xpoints[i]];
                    r += bt[pix & 0xff];
                    g += bt[(pix >> 8) & 0xff];
                    b += bt[(pix >> 16) & 0xff];
                }
                if (r > 255) {
                    r = 255;
                }
                if (g > 255) {
                    g = 255;
                }
                if (b > 255) {
                    b = 255;
                }
                lfb++;
                *outp++ = r | (g << 8) | (b << 16);
            }
            for (; x < w; x++) {
                int r = 0, g = 0, b = 0;
                for (i = 0; i < num_render_layers; i++) {
                    int xp = x - xpoints[i];
                    if (xp >= 0 && xp < w) {
                        int pix = framebuffer[xp + yoffs[i]];
                        r += bt[pix & 0xff];
                        g += bt[(pix >> 8) & 0xff];
                        b += bt[(pix >> 16) & 0xff];
                    }
                }
                if (r > 255) {
                    r = 255;
                }
                if (g > 255) {
                    g = 255;
                }
                if (b > 255) {
                    b = 255;
                }
                *outp++ = r | (g << 8) | (b << 16);
            }
        } else {
            for (x = 0; x < w; x++) {
                int r = 0, g = 0, b = 0;
                for (i = 0; i < num_render_layers; i++) {
                    int xp = x - xpoints[i];
                    if (xp >= 0 && xp < w && yoffs[i] != -1) {
                        int pix = framebuffer[xp + yoffs[i]];
                        r += bt[pix & 0xff];
                        g += bt[(pix >> 8) & 0xff];
                        b += bt[(pix >> 16) & 0xff];
                    }
                }
                if (r > 255) {
                    r = 255;
                }
                if (g > 255) {
                    g = 255;
                }
                if (b > 255) {
                    b = 255;
                }
                *outp++ = r | (g << 8) | (b << 16);
            }
        }
    }

    this->cur_rotation += rotation_step;
    this->cur_rotation =
        this->cur_rotation > 255 ? this->cur_rotation - 255 : this->cur_rotation;
    this->cur_rotation =
        this->cur_rotation < -255 ? this->cur_rotation + 255 : this->cur_rotation;

    this->on_beat_fadeout += this->config.on_beat_speed;
    this->on_beat_fadeout = this->on_beat_fadeout > M_PI ? M_PI : this->on_beat_fadeout;
    if (this->on_beat_fadeout < -M_PI) {
        this->on_beat_fadeout = M_PI;
    }

    auto src = (uint32_t*)fbout;
    auto dest = (uint32_t*)framebuffer;
    switch (this->config.blend_mode) {
        default:
        case BLEND_SIMPLE_REPLACE: return 1;
        case BLEND_SIMPLE_ADDITIVE: blend_add(src, src, dest, w, h); break;
        case BLEND_SIMPLE_5050: blend_5050(src, src, dest, w, h); break;
    }
    return 0;
}

void E_Interferences::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.num_layers = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.init_rotation = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.distance = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.alpha = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.rotation = GET_INT();
        pos += 4;
    }
    this->config.blend_mode = BLEND_SIMPLE_REPLACE;
    if (len - pos >= 4) {
        if (GET_INT()) {
            this->config.blend_mode = BLEND_SIMPLE_ADDITIVE;
        }
        pos += 4;
    }
    if (len - pos >= 4) {
        if (GET_INT()) {
            this->config.blend_mode = BLEND_SIMPLE_5050;
        }
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_distance = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_alpha = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_rotation = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.separate_rgb = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_speed = GET_FLOAT(data, pos);
        pos += 4;
    }
    this->on_beat_fadeout = M_PI;
    this->cur_rotation = this->config.init_rotation;
}

int E_Interferences::save_legacy(unsigned char* data) {
    int pos = 0;

    PUT_INT(this->enabled);
    pos += 4;
    PUT_INT(this->config.num_layers);
    pos += 4;
    PUT_INT(this->config.init_rotation);
    pos += 4;
    PUT_INT(this->config.distance);
    pos += 4;
    PUT_INT(this->config.alpha);
    pos += 4;
    PUT_INT(this->config.rotation);
    pos += 4;
    PUT_INT(this->config.blend_mode == BLEND_SIMPLE_ADDITIVE);
    pos += 4;
    PUT_INT(this->config.blend_mode == BLEND_SIMPLE_5050);
    pos += 4;
    PUT_INT(this->config.on_beat_distance);
    pos += 4;
    PUT_INT(this->config.on_beat_alpha);
    pos += 4;
    PUT_INT(this->config.on_beat_rotation);
    pos += 4;
    PUT_INT(this->config.separate_rgb);
    pos += 4;
    PUT_INT(this->config.on_beat);
    pos += 4;
    PUT_FLOAT(this->config.on_beat_speed, data, pos);
    pos += 4;

    return pos;
}

Effect_Info* create_Interferences_Info() { return new Interferences_Info(); }
Effect* create_Interferences(AVS_Instance* avs) { return new E_Interferences(avs); }
void set_Interferences_desc(char* desc) { E_Interferences::set_desc(desc); }
