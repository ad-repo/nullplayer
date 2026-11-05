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
#include "e_brightness.h"

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

constexpr Parameter Brightness_Info::parameters[];

void Brightness_Info::on_color_change(Effect* component,
                                      const Parameter* parameter,
                                      const std::vector<int64_t>&) {
    auto brightness = (E_Brightness*)component;
    if (!brightness->config.separate) {
        auto new_value = brightness->get_int(parameter->handle);
        // Yes, one of these 3 lines will always be superfluous,
        // but the alternative would be much uglier code.
        brightness->config.red = new_value;
        brightness->config.green = new_value;
        brightness->config.blue = new_value;
    }
    brightness->need_tab_init = true;
}

void Brightness_Info::on_separate_toggle(Effect* component,
                                         const Parameter*,
                                         const std::vector<int64_t>&) {
    auto brightness = (E_Brightness*)component;
    if (!brightness->config.separate) {
        brightness->config.green = brightness->config.red;
        brightness->config.blue = brightness->config.red;
    }
    brightness->need_tab_init = true;
}

E_Brightness::~E_Brightness() {}
E_Brightness::E_Brightness(AVS_Instance* avs)
    : Configurable_Effect(avs), need_tab_init(true) {}

static inline int iabs(int v) { return (v < 0) ? -v : v; }

static inline int in_range(int color, int ref, int distance) {
    if (iabs((color & 0xFF) - (ref & 0xFF)) > distance) {
        return 0;
    }
    if (iabs(((color) & 0xFF00) - ((ref) & 0xFF00)) > (distance << 8)) {
        return 0;
    }
    if (iabs(((color) & 0xFF0000) - ((ref) & 0xFF0000)) > (distance << 16)) {
        return 0;
    }
    return 1;
}

int E_Brightness::render(char visdata[2][2][576],
                         int is_beat,
                         int* framebuffer,
                         int* fbout,
                         int w,
                         int h) {
    smp_begin(1, visdata, is_beat, framebuffer, fbout, w, h);
    if (is_beat & 0x80000000) {
        return 0;
    }

    smp_render(0, 1, visdata, is_beat, framebuffer, fbout, w, h);
    return smp_finish(visdata, is_beat, framebuffer, fbout, w, h);
}

int E_Brightness::smp_begin(int max_threads,
                            char[2][2][576],
                            int is_beat,
                            int*,
                            int*,
                            int,
                            int) {
    if (this->need_tab_init) {
        int tab_red =
            (int)((1
                   + (this->config.red < 0 ? 1 : 16) * ((float)this->config.red / 4096))
                  * 65536.0);
        int tab_green = (int)((1
                               + (this->config.green < 0 ? 1 : 16)
                                     * ((float)this->config.green / 4096))
                              * 65536.0);
        int tab_blue = (int)((1
                              + (this->config.blue < 0 ? 1 : 16)
                                    * ((float)this->config.blue / 4096))
                             * 65536.0);
        for (int n = 0; n < 256; n++) {
            this->red_tab[n] = (n * tab_red) & 0xffff0000;
            if (this->red_tab[n] > 0xff0000) {
                this->red_tab[n] = 0xff0000;
            }
            if (this->red_tab[n] < 0) {
                this->red_tab[n] = 0;
            }
            this->green_tab[n] = ((n * tab_green) >> 8) & 0xffff00;
            if (this->green_tab[n] > 0xff00) {
                this->green_tab[n] = 0xff00;
            }
            if (this->green_tab[n] < 0) {
                this->green_tab[n] = 0;
            }
            this->blue_tab[n] = ((n * tab_blue) >> 16) & 0xffff;
            if (this->blue_tab[n] > 0xff) {
                this->blue_tab[n] = 0xff;
            }
            if (this->blue_tab[n] < 0) {
                this->blue_tab[n] = 0;
            }
        }
        this->need_tab_init = false;
    }
    if (is_beat & 0x80000000) {
        return 0;
    }

    return max_threads;
}

int E_Brightness::smp_finish(char[2][2][576], int, int*, int*, int, int) { return 0; }

void E_Brightness::smp_render(int this_thread,
                              int max_threads,
                              char[2][2][576],
                              int is_beat,
                              int* framebuffer,
                              int*,
                              int w,
                              int h) {
    if (is_beat & 0x80000000) {
        return;
    }

    if (max_threads < 1) {
        max_threads = 1;
    }

    int start_l = (this_thread * h) / max_threads;
    int end_l;

    if (this_thread >= max_threads - 1) {
        end_l = h;
    } else {
        end_l = ((this_thread + 1) * h) / max_threads;
    }

    int out_h = end_l - start_l;
    if (out_h < 1) {
        return;
    }

    int l = w * out_h;

    uint32_t* p = (uint32_t*)&framebuffer[start_l * w];
    switch (this->config.blend_mode) {
        case BLEND_SIMPLE_ADDITIVE: {
            if (!this->config.exclude) {
                while (l--) {
                    uint32_t color = this->red_tab[(*p >> 16) & 0xff]
                                     | this->green_tab[(*p >> 8) & 0xff]
                                     | this->blue_tab[*p & 0xff];
                    blend_add_1px(&color, p, p);
                    p++;
                }
            } else {
                while (l--) {
                    if (!in_range(
                            *p, this->config.exclude_color, this->config.distance)) {
                        uint32_t color = this->red_tab[(*p >> 16) & 0xff]
                                         | this->green_tab[(*p >> 8) & 0xff]
                                         | this->blue_tab[*p & 0xff];
                        blend_add_1px(&color, p, p);
                    }
                    p++;
                }
            }
            break;
        }
        case BLEND_SIMPLE_5050: {
            if (!this->config.exclude) {
                while (l--) {
                    uint32_t color = this->red_tab[(*p >> 16) & 0xff]
                                     | this->green_tab[(*p >> 8) & 0xff]
                                     | this->blue_tab[*p & 0xff];
                    blend_5050_1px(&color, p, p);
                    p++;
                }
            } else {
                while (l--) {
                    if (!in_range(
                            *p, this->config.exclude_color, this->config.distance)) {
                        uint32_t color = this->red_tab[(*p >> 16) & 0xff]
                                         | this->green_tab[(*p >> 8) & 0xff]
                                         | this->blue_tab[*p & 0xff];
                        blend_5050_1px(&color, p, p);
                    }
                    p++;
                }
            }
            break;
        }
        default:
        case BLEND_SIMPLE_REPLACE: {
            if (!this->config.exclude) {
                while (l--) {
                    uint32_t color = this->red_tab[(*p >> 16) & 0xff]
                                     | this->green_tab[(*p >> 8) & 0xff]
                                     | this->blue_tab[*p & 0xff];
                    blend_replace_1px(&color, p);
                    p++;
                }
            } else {
                while (l--) {
                    if (!in_range(
                            *p, this->config.exclude_color, this->config.distance)) {
                        uint32_t color = this->red_tab[(*p >> 16) & 0xff]
                                         | this->green_tab[(*p >> 8) & 0xff]
                                         | this->blue_tab[*p & 0xff];
                        blend_replace_1px(&color, p);
                    }
                    p++;
                }
            }
            break;
        }
    }
}

void E_Brightness::on_load() { Brightness_Info::on_separate_toggle(this, nullptr, {}); }

void E_Brightness::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = GET_INT();
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
        this->config.red = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.green = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.blue = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.separate = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.exclude_color = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.exclude = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.distance = GET_INT();
        pos += 4;
    }
    Brightness_Info::on_separate_toggle(this, nullptr, {});
    this->need_tab_init = true;
}

int E_Brightness::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->enabled);
    pos += 4;
    bool blend_additive = this->config.blend_mode == BLEND_SIMPLE_ADDITIVE;
    PUT_INT(blend_additive);
    pos += 4;
    bool blend_5050 = this->config.blend_mode == BLEND_SIMPLE_5050;
    PUT_INT(blend_5050);
    pos += 4;
    PUT_INT(this->config.red);
    pos += 4;
    PUT_INT(this->config.green);
    pos += 4;
    PUT_INT(this->config.blue);
    pos += 4;
    PUT_INT(this->config.separate);
    pos += 4;
    PUT_INT(this->config.exclude_color);
    pos += 4;
    PUT_INT(this->config.exclude);
    pos += 4;
    PUT_INT(this->config.distance);
    pos += 4;
    return pos;
}

Effect_Info* create_Brightness_Info() { return new Brightness_Info(); }
Effect* create_Brightness(AVS_Instance* avs) { return new E_Brightness(avs); }
void set_Brightness_desc(char* desc) { E_Brightness::set_desc(desc); }
