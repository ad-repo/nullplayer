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
#include "e_superscope.h"

#include "avs_eelif.h"
#include "blend.h"
#include "linedraw.h"

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255
#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter SuperScope_Info::color_params[];
constexpr Parameter SuperScope_Info::parameters[];
constexpr SuperScope_Example SuperScope_Info::examples[];

void SuperScope_Info::recompile(Effect* component,
                                const Parameter* parameter,
                                const std::vector<int64_t>&) {
    auto ssc = ((E_SuperScope*)component);
    if (std::string("Init") == parameter->name) {
        ssc->code_init.need_recompile = true;
    } else if (std::string("Frame") == parameter->name) {
        ssc->code_frame.need_recompile = true;
    } else if (std::string("Beat") == parameter->name) {
        ssc->code_beat.need_recompile = true;
    } else if (std::string("Point") == parameter->name) {
        ssc->code_point.need_recompile = true;
    }
}

void SuperScope_Info::load_example(Effect* component,
                                   const Parameter*,
                                   const std::vector<int64_t>&) {
    auto ssc = ((E_SuperScope*)component);
    if (ssc->config.example < 0 || ssc->config.example >= ssc->info.num_examples) {
        return;
    }
    const SuperScope_Example& to_load = ssc->info.examples[ssc->config.example];
    ssc->config.init = to_load.init;
    ssc->config.frame = to_load.frame;
    ssc->config.beat = to_load.beat;
    ssc->config.point = to_load.point;
    ssc->need_full_recompile();
}

E_SuperScope::E_SuperScope(AVS_Instance* avs) : Programmable_Effect(avs) {
    this->need_full_recompile();
}
E_SuperScope::~E_SuperScope() {}

static inline int makeint(double t) {
    if (t <= 0.0) {
        return 0;
    }
    if (t >= 1.0) {
        return 255;
    }
    return (int)(t * 255.0);
}

int E_SuperScope::render(char visdata[2][2][576],
                         int is_beat,
                         int* framebuffer,
                         int*,
                         int w,
                         int h) {
    if (this->recompile_if_needed()) {
        // Resetting "n" to 100 and running init again on every section's recompile is a
        // bit weird but replicates the original's behavior.
        // TODO [bug][feature]: Make this behave like other codeable effects.
        //                      (i.e. no "n" default value reset?)
        *this->vars.n = 100.0;
        this->need_init = true;
    }
    if (is_beat & 0x80000000 || this->config.colors.empty()) {
        return 0;
    }

    int x;
    uint32_t current_color;
    unsigned char* audio_data;
    char center_channel[576];
    int sign_invert = this->config.audio_source ? 0 : 128;

    if (this->config.audio_channel == 0) {
        if (this->config.audio_source == 0) {
            for (x = 0; x < 576; x++) {
                center_channel[x] =
                    (signed char)visdata[1 - this->config.audio_source][0][x] / 2
                    + (signed char)visdata[1 - this->config.audio_source][1][x] / 2;
            }
        } else {
            for (x = 0; x < 576; x++) {
                center_channel[x] =
                    (unsigned char)visdata[1 - this->config.audio_source][0][x] / 2
                    + (unsigned char)visdata[1 - this->config.audio_source][1][x] / 2;
            }
        }
        audio_data = (unsigned char*)center_channel;
    } else {
        audio_data = (unsigned char*)&visdata[1 - this->config.audio_source]
                                             [this->config.audio_channel - 1][0];
    }

    color_pos++;
    if (color_pos >= this->config.colors.size() * 64) {
        color_pos = 0;
    }
    uint32_t p = color_pos / 64;
    int r = color_pos & 63;
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

    this->init_variables(
        w, h, is_beat, current_color, (uint32_t)this->config.draw_mode);
    if (this->need_init) {
        this->code_init.exec(visdata);
        this->need_init = false;
    }
    this->code_frame.exec(visdata);
    if (is_beat) {
        this->code_beat.exec(visdata);
    }
    if (this->code_point.is_valid()) {
        bool is_first_point = true;
        int lx = 0;
        int ly = 0;
        int num_lines = *this->vars.n;
        if (num_lines > 128 * 1024) {
            num_lines = 128 * 1024;
        }
        for (int i = 0; i < num_lines; i++) {
            double audio_index = (i * 576.0) / num_lines;
            double audio_lerp = audio_index - (int)audio_index;
            double audio_value =
                (audio_data[(int)audio_index] ^ sign_invert) * (1.0f - audio_lerp)
                + (audio_data[(int)audio_index + 1] ^ sign_invert) * (audio_lerp);
            *this->vars.v = audio_value / 128.0 - 1.0;
            *this->vars.i = (double)i / (double)(num_lines - 1);
            *this->vars.skip = 0.0;
            this->code_point.exec(visdata);
            int x = (*this->vars.x + 1.0) * w * 0.5;
            int y = (*this->vars.y + 1.0) * h * 0.5;
            if (*this->vars.skip < 0.00001) {
                uint32_t thiscolor = makeint(*this->vars.blue)
                                     | (makeint(*this->vars.green) << 8)
                                     | (makeint(*this->vars.red) << 16);
                if (*this->vars.drawmode < 0.00001) {
                    if (y >= 0 && y < h && x >= 0 && x < w) {
                        uint32_t* dest = (uint32_t*)framebuffer + x + y * w;
                        blend_default_1px(&thiscolor, dest, dest);
                    }
                } else {
                    if (!is_first_point) {
                        if ((thiscolor & 0xffffff) || (g_line_blend_mode & 0xff) != 1) {
                            line((uint32_t*)framebuffer,
                                 lx,
                                 ly,
                                 x,
                                 y,
                                 w,
                                 h,
                                 thiscolor,
                                 (int)(*this->vars.linesize + 0.5));
                        }
                    }  // is_first_point
                }  // line
            }  // skip
            is_first_point = false;
            lx = x;
            ly = y;
        }
    }

    return 0;
}

void SuperScope_Vars::register_(void* vm_context) {
    this->w = NSEEL_VM_regvar(vm_context, "w");
    this->n = NSEEL_VM_regvar(vm_context, "n");
    this->b = NSEEL_VM_regvar(vm_context, "b");
    this->x = NSEEL_VM_regvar(vm_context, "x");
    this->y = NSEEL_VM_regvar(vm_context, "y");
    this->i = NSEEL_VM_regvar(vm_context, "i");
    this->v = NSEEL_VM_regvar(vm_context, "v");
    this->w = NSEEL_VM_regvar(vm_context, "w");
    this->h = NSEEL_VM_regvar(vm_context, "h");
    this->red = NSEEL_VM_regvar(vm_context, "red");
    this->green = NSEEL_VM_regvar(vm_context, "green");
    this->blue = NSEEL_VM_regvar(vm_context, "blue");
    this->linesize = NSEEL_VM_regvar(vm_context, "linesize");
    this->skip = NSEEL_VM_regvar(vm_context, "skip");
    this->drawmode = NSEEL_VM_regvar(vm_context, "drawmode");
}

void SuperScope_Vars::init(int w, int h, int is_beat, va_list extra_args) {
    *this->h = h;
    *this->w = w;
    *this->b = is_beat ? 1.0 : 0.0;
    *this->skip = 0.0;
    uint32_t color = va_arg(extra_args, uint32_t);
    *this->blue = (color & 0xff) / 255.0;
    *this->green = ((color >> 8) & 0xff) / 255.0;
    *this->red = ((color >> 16) & 0xff) / 255.0;
    *this->linesize = (double)((g_line_blend_mode & 0xff0000) >> 16);
    *this->drawmode = va_arg(extra_args, uint32_t);
}

void E_SuperScope::load_legacy(unsigned char* data, int len) {
    char* str_data = (char*)data;
    int pos = 0;
    if (data[pos] == 1) {
        pos++;
        pos += this->string_load_legacy(&str_data[pos], this->config.point, len - pos);
        pos += this->string_load_legacy(&str_data[pos], this->config.frame, len - pos);
        pos += this->string_load_legacy(&str_data[pos], this->config.beat, len - pos);
        pos += this->string_load_legacy(&str_data[pos], this->config.init, len - pos);
    } else {
        char buf[1025];
        if (len - pos >= 1024) {
            memcpy(buf, data + pos, 1024);
            pos += 1024;
            buf[1024] = 0;
            this->config.init.assign(buf + 768);
            buf[768] = 0;
            this->config.beat.assign(buf + 512);
            buf[512] = 0;
            this->config.frame.assign(buf + 256);
            buf[256] = 0;
            this->config.point.assign(buf);
        }
    }
    this->need_full_recompile();
    if (len - pos >= 4) {
        uint32_t channel_and_source = GET_INT();
        switch (channel_and_source & 0b011) {
            default:
            case 2: this->config.audio_channel = 0; break;  // Center
            case 0: this->config.audio_channel = 1; break;  // Left
            case 1: this->config.audio_channel = 2; break;  // Right
        }
        this->config.audio_source = channel_and_source & 0b100 ? 1 : 0;
        pos += 4;
    }
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
        this->config.draw_mode = GET_INT();
        pos += 4;
    }
}

int E_SuperScope::save_legacy(unsigned char* data) {
    char* str_data = (char*)data;
    int pos = 0;
    data[pos++] = 1;
    pos += this->string_save_legacy(
        this->config.point, &str_data[pos], MAX_CODE_LEN - 1 - pos, /*with_nt*/ true);
    pos += this->string_save_legacy(
        this->config.frame, &str_data[pos], MAX_CODE_LEN - 1 - pos, /*with_nt*/ true);
    pos += this->string_save_legacy(
        this->config.beat, &str_data[pos], MAX_CODE_LEN - 1 - pos, /*with_nt*/ true);
    pos += this->string_save_legacy(
        this->config.init, &str_data[pos], MAX_CODE_LEN - 1 - pos, /*with_nt*/ true);
    uint32_t channel_and_source;
    switch (this->config.audio_channel) {
        default:
        case 0: channel_and_source = 0b010; break;  // Center
        case 1: channel_and_source = 0b000; break;  // Left
        case 2: channel_and_source = 0b001; break;  // Right
    }
    if (this->config.audio_source == 1) {
        channel_and_source |= 0b100;
    }
    PUT_INT(channel_and_source);
    pos += 4;
    PUT_INT(this->config.colors.size());
    pos += 4;
    for (auto const& color : this->config.colors) {
        PUT_INT(color.color);
        pos += 4;
    }
    PUT_INT(this->config.draw_mode);
    pos += 4;
    return pos;
}

Effect_Info* create_SuperScope_Info() { return new SuperScope_Info(); }
Effect* create_SuperScope(AVS_Instance* avs) { return new E_SuperScope(avs); }
void set_SuperScope_desc(char* desc) { E_SuperScope::set_desc(desc); }
