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
#include "e_bump.h"

#include "avs_eelif.h"
#include "blend.h"
#include "instance.h"

#include <stdio.h>
#include <stdlib.h>

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

constexpr Parameter Bump_Info::parameters[];

void Bump_Info::recompile(Effect* component,
                          const Parameter* parameter,
                          const std::vector<int64_t>&) {
    auto bump = (E_Bump*)component;
    if (std::string("Init") == parameter->name) {
        bump->code_init.need_recompile = true;
    } else if (std::string("Frame") == parameter->name) {
        bump->code_frame.need_recompile = true;
    } else if (std::string("Beat") == parameter->name) {
        bump->code_beat.need_recompile = true;
    }
    bump->recompile_if_needed();
}

E_Bump::E_Bump(AVS_Instance* avs)
    : Programmable_Effect(avs),
      cur_depth(this->config.depth),
      on_beat_fadeout(0),
      use_old_xy_range(0) {}
E_Bump::~E_Bump() {}

static inline uint32_t max_channel(uint32_t color, bool invert) {
    uint32_t r =
        max(max((color & 0xFF), ((color & 0xFF00) >> 8)), (color & 0xFF0000) >> 16);
    return invert ? 255 - r : r;
}

static inline uint32_t set_depth(int light_distance, uint32_t color) {
    uint32_t r;
    r = min((color & 0xFF) + light_distance, 254);
    r |= min(((color & 0xFF00)) + (light_distance << 8), 254 << 8);
    r |= min(((color & 0xFF0000)) + (light_distance << 16), 254 << 16);
    return r;
}

static inline uint32_t set_far_depth(uint32_t c) {
    uint32_t r;
    r = min((c & 0xFF), 254);
    r |= min((c & 0xFF00), 254 << 8);
    r |= min((c & 0xFF0000), 254 << 16);
    return r;
}

#define abs(x) ((x) >= 0 ? (x) : -(x))

int E_Bump::render(char visdata[2][2][576],
                   int is_beat,
                   int* framebuffer,
                   int* fbout,
                   int w,
                   int h) {
    int32_t center_x;
    int32_t center_y;
    bool use_cur_buf;

    this->recompile_if_needed();
    if (is_beat & 0x80000000) {
        return 0;
    }

    uint32_t* src_buffer = this->config.depth_buffer == 0
                               ? (uint32_t*)framebuffer
                               : (uint32_t*)this->avs->get_buffer(
                                     w, h, this->config.depth_buffer - 1, false);
    if (!src_buffer) {
        return 0;
    }

    if (this->need_init) {
        this->code_init.exec(visdata);
        this->need_init = false;
        *this->vars.bi = 1.0;
    }

    this->code_frame.exec(visdata);
    if (is_beat) {
        this->code_beat.exec(visdata);
    }
    this->init_variables(w, h, is_beat, this->on_beat_fadeout);

    if (this->config.on_beat && is_beat) {
        this->cur_depth = this->config.on_beat_depth;
        this->on_beat_fadeout = this->config.on_beat_duration;
    } else if (!this->on_beat_fadeout) {
        this->cur_depth = this->config.depth;
    }

    memset(fbout, 0, w * h * 4);  // previous effects may have left fbout in a mess

    if (this->use_old_xy_range) {
        center_x = *this->vars.x / 100.0 * w;
        center_y = *this->vars.y / 100.0 * h;
    } else {
        center_x = *this->vars.x * w;
        center_y = *this->vars.y * h;
    }
    center_x = max(0, min(w, center_x));
    center_y = max(0, min(h, center_y));
    if (this->config.show_light_pos) {
        fbout[center_x + center_y * w] = 0xFFFFFF;
    }

    if (*this->vars.bi < 0.0) {
        *this->vars.bi = 0.0;
    } else if (*this->vars.bi > 1.0) {
        *this->vars.bi = 1.0;
    }
    this->cur_depth = (int)(this->cur_depth * *this->vars.bi);

    int depth_scaled = (this->cur_depth << 8) / 100;
    src_buffer += w + 1;
    framebuffer += w + 1;
    fbout += w + 1;

    int light_y = 1 - center_y;
    int i = h - 2;
    int left;
    int right;
    int above;
    int below;
    int x_distance;
    int y_distance;
    int xy_combined;
    uint32_t distance;
    auto fb_in = (uint32_t*)framebuffer;
    auto fb_out = (uint32_t*)fbout;
    use_cur_buf = (src_buffer == fb_in);
    while (i--) {
        int j = w - 2;
        int light_x = 1 - center_x;
        switch (this->config.blend_mode) {
            case BLEND_SIMPLE_ADDITIVE: {
                while (j--) {
                    left = src_buffer[-1];
                    right = src_buffer[1];
                    above = src_buffer[-w];
                    below = src_buffer[w];
                    if (!use_cur_buf
                        || (use_cur_buf && (left || right || above || below))) {
                        x_distance = max_channel(right, this->config.invert_depth)
                                     - max_channel(left, this->config.invert_depth)
                                     - light_x;
                        y_distance = max_channel(below, this->config.invert_depth)
                                     - max_channel(above, this->config.invert_depth)
                                     - light_y;
                        x_distance = 127 - abs(x_distance);
                        y_distance = 127 - abs(y_distance);
                        if (x_distance <= 0 || y_distance <= 0) {
                            distance = set_far_depth(*fb_in);
                        } else {
                            xy_combined =
                                (x_distance * y_distance * depth_scaled) >> (8 + 6);
                            distance = set_depth(xy_combined, *fb_in);
                        }
                        blend_add_1px(&distance, fb_in, fb_out);
                    }
                    src_buffer++;
                    fb_in++;
                    fb_out++;
                    light_x++;
                }
                break;
            }
            case BLEND_SIMPLE_5050: {
                while (j--) {
                    left = src_buffer[-1];
                    right = src_buffer[1];
                    above = src_buffer[-w];
                    below = src_buffer[w];
                    if (!use_cur_buf
                        || (use_cur_buf && (left || right || above || below))) {
                        x_distance = max_channel(right, this->config.invert_depth)
                                     - max_channel(left, this->config.invert_depth)
                                     - light_x;
                        y_distance = max_channel(below, this->config.invert_depth)
                                     - max_channel(above, this->config.invert_depth)
                                     - light_y;
                        x_distance = 127 - abs(x_distance);
                        y_distance = 127 - abs(y_distance);
                        if (x_distance <= 0 || y_distance <= 0) {
                            distance = set_far_depth(*fb_in);
                        } else {
                            xy_combined =
                                (x_distance * y_distance * depth_scaled) >> (8 + 6);
                            distance = set_depth(xy_combined, *fb_in);
                        }
                        blend_5050_1px(&distance, fb_in, fb_out);
                    }
                    src_buffer++;
                    fb_in++;
                    fb_out++;
                    light_x++;
                }
                break;
            }
            default:
            case BLEND_SIMPLE_REPLACE: {
                while (j--) {
                    left = src_buffer[-1];
                    right = src_buffer[1];
                    above = src_buffer[-w];
                    below = src_buffer[w];
                    if (!use_cur_buf
                        || (use_cur_buf && (left || right || above || below))) {
                        x_distance = max_channel(right, this->config.invert_depth)
                                     - max_channel(left, this->config.invert_depth)
                                     - light_x;
                        y_distance = max_channel(below, this->config.invert_depth)
                                     - max_channel(above, this->config.invert_depth)
                                     - light_y;
                        x_distance = 127 - abs(x_distance);
                        y_distance = 127 - abs(y_distance);
                        if (x_distance <= 0 || y_distance <= 0) {
                            distance = set_far_depth(*fb_in);
                        } else {
                            xy_combined =
                                (x_distance * y_distance * depth_scaled) >> (8 + 6);
                            distance = set_depth(xy_combined, *fb_in);
                        }
                        blend_replace_1px(&distance, fb_out);
                    }
                    src_buffer++;
                    fb_in++;
                    fb_out++;
                    light_x++;
                }
                break;
            }
        }
        src_buffer += 2;
        fb_in += 2;
        fb_out += 2;
        light_y++;
    }

    if (this->on_beat_fadeout > 0) {
        this->on_beat_fadeout--;
        if (this->on_beat_fadeout) {
            int a = abs(this->config.depth - this->config.on_beat_depth)
                    / this->config.on_beat_duration;
            this->cur_depth +=
                a * (this->config.on_beat_depth > this->config.depth ? -1 : 1);
        }
    }

    return 1;
}

void Bump_Vars::register_(void* vm_context) {
    this->bi = NSEEL_VM_regvar(vm_context, "bi");
    this->x = NSEEL_VM_regvar(vm_context, "x");
    this->y = NSEEL_VM_regvar(vm_context, "y");
    this->is_beat = NSEEL_VM_regvar(vm_context, "isBeat");
    this->is_long_beat = NSEEL_VM_regvar(vm_context, "is_long_beat");
}

void Bump_Vars::init(int, int, int is_beat, va_list extra_args) {
    *this->is_beat = is_beat ? -1.0 : 1.0;
    *this->is_long_beat = va_arg(extra_args, int) > 0 ? -1 : 1;
}

void E_Bump::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_duration = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.depth = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_depth = GET_INT();
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
        if (GET_INT() && this->config.blend_mode == BLEND_SIMPLE_REPLACE) {
            this->config.blend_mode = BLEND_SIMPLE_5050;
        }
        pos += 4;
    }
    char* str_data = (char*)data;
    pos += this->string_load_legacy(&str_data[pos], this->config.frame, len - pos);
    pos += this->string_load_legacy(&str_data[pos], this->config.beat, len - pos);
    pos += this->string_load_legacy(&str_data[pos], this->config.init, len - pos);
    this->need_full_recompile();
    if (len - pos >= 4) {
        this->config.show_light_pos = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.invert_depth = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->use_old_xy_range = GET_INT();
        pos += 4;
    } else {
        this->use_old_xy_range = 1;
    }
    if (len - pos >= 4) {
        this->config.depth_buffer = GET_INT();
        pos += 4;
    }
    this->cur_depth = this->config.depth;
    this->on_beat_fadeout = 0;
}

int E_Bump::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->enabled);
    pos += 4;
    PUT_INT(this->config.on_beat);
    pos += 4;
    PUT_INT(this->config.on_beat_duration);
    pos += 4;
    PUT_INT(this->config.depth);
    pos += 4;
    PUT_INT(this->config.on_beat_depth);
    pos += 4;
    uint32_t blend_additive = this->config.blend_mode == BLEND_SIMPLE_ADDITIVE;
    PUT_INT(blend_additive);
    pos += 4;
    uint32_t blend_5050 = this->config.blend_mode == BLEND_SIMPLE_5050;
    PUT_INT(blend_5050);
    pos += 4;
    char* str_data = (char*)data;
    pos += this->string_save_legacy(
        this->config.frame, &str_data[pos], MAX_CODE_LEN - 1 - pos, /*with_nt*/ true);
    pos += this->string_save_legacy(
        this->config.beat, &str_data[pos], MAX_CODE_LEN - 1 - pos, /*with_nt*/ true);
    pos += this->string_save_legacy(
        this->config.init, &str_data[pos], MAX_CODE_LEN - 1 - pos, /*with_nt*/ true);
    PUT_INT(this->config.show_light_pos);
    pos += 4;
    PUT_INT(this->config.invert_depth);
    pos += 4;
    PUT_INT(this->use_old_xy_range);
    pos += 4;
    PUT_INT(this->config.depth_buffer);
    pos += 4;
    return pos;
}

Effect_Info* create_Bump_Info() { return new Bump_Info(); }
Effect* create_Bump(AVS_Instance* avs) { return new E_Bump(avs); }
void set_Bump_desc(char* desc) { E_Bump::set_desc(desc); }
