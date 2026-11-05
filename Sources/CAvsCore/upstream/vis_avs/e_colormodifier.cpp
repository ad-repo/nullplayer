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
#include "e_colormodifier.h"

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255
#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter ColorModifier_Info::parameters[];
constexpr ColorModifier_Preset ColorModifier_Info::examples[];

void ColorModifier_Info::recompile(Effect* component,
                                   const Parameter* parameter,
                                   const std::vector<int64_t>&) {
    auto color_modifier = (E_ColorModifier*)component;
    if (std::string("Init") == parameter->name) {
        color_modifier->code_init.need_recompile = true;
    } else if (std::string("Frame") == parameter->name) {
        color_modifier->code_frame.need_recompile = true;
    } else if (std::string("Beat") == parameter->name) {
        color_modifier->code_beat.need_recompile = true;
    } else if (std::string("Point") == parameter->name) {
        color_modifier->code_point.need_recompile = true;
    }
    color_modifier->recompile_if_needed();
}
void ColorModifier_Info::load_example(Effect* component,
                                      const Parameter*,
                                      const std::vector<int64_t>&) {
    auto color_modifier = (E_ColorModifier*)component;
    const ColorModifier_Preset& to_load =
        color_modifier->info.examples[color_modifier->config.example];
    color_modifier->config.init = to_load.init;
    color_modifier->config.frame = to_load.frame;
    color_modifier->config.beat = to_load.beat;
    color_modifier->config.point = to_load.point;
    color_modifier->config.recompute_every_frame = to_load.recompute_every_frame;
    color_modifier->need_full_recompile();
    color_modifier->channel_table_valid = false;
}

E_ColorModifier::E_ColorModifier(AVS_Instance* avs)
    : Programmable_Effect(avs), channel_table_valid(false) {
    this->need_full_recompile();
}

E_ColorModifier::~E_ColorModifier() {}

int E_ColorModifier::render(char visdata[2][2][576],
                            int is_beat,
                            int* framebuffer,
                            int*,
                            int w,
                            int h) {
    this->recompile_if_needed();
    if (is_beat & 0x80000000) {
        return 0;
    }

    if (this->need_init) {
        this->code_init.exec(visdata);
        this->need_init = false;
    }
    this->init_variables(w, h, is_beat);
    this->code_frame.exec(visdata);
    if (is_beat) {
        this->code_beat.exec(visdata);
    }

    if (this->config.recompute_every_frame || !this->channel_table_valid) {
        int x;
        uint8_t* t = this->channel_table;
        for (x = 0; x < 256; x++) {
            *this->vars.red = *this->vars.blue = *this->vars.green = x / 255.0;
            this->code_point.exec(visdata);
            int r = (int)(*this->vars.red * 255.0 + 0.5);
            int g = (int)(*this->vars.green * 255.0 + 0.5);
            int b = (int)(*this->vars.blue * 255.0 + 0.5);
            if (r < 0) {
                r = 0;
            } else if (r > 255) {
                r = 255;
            }
            if (g < 0) {
                g = 0;
            } else if (g > 255) {
                g = 255;
            }
            if (b < 0) {
                b = 0;
            } else if (b > 255) {
                b = 255;
            }
            t[512] = r;
            t[256] = g;
            t[0] = b;
            t++;
        }
        this->channel_table_valid = true;
    }

    uint8_t* fb = (uint8_t*)framebuffer;
    int l = w * h;
    while (l--) {
        fb[0] = this->channel_table[fb[0]];
        fb[1] = this->channel_table[(int)fb[1] + 256];
        fb[2] = this->channel_table[(int)fb[2] + 512];
        fb += 4;
    }

    return 0;
}

void ColorModifier_Vars::register_(void* vm_context) {
    this->red = NSEEL_VM_regvar(vm_context, "red");
    this->green = NSEEL_VM_regvar(vm_context, "green");
    this->blue = NSEEL_VM_regvar(vm_context, "blue");
    this->beat = NSEEL_VM_regvar(vm_context, "beat");
}

void ColorModifier_Vars::init(int, int, int is_beat, va_list) {
    *this->beat = is_beat ? 1.0 : 0.0;
}

void E_ColorModifier::load_legacy(unsigned char* data, int len) {
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
        this->config.recompute_every_frame = GET_INT();
        pos += 4;
    }
}
int E_ColorModifier::save_legacy(unsigned char* data) {
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
    PUT_INT(this->config.recompute_every_frame);
    pos += 4;
    return pos;
}

Effect_Info* create_ColorModifier_Info() { return new ColorModifier_Info(); }
Effect* create_ColorModifier(AVS_Instance* avs) { return new E_ColorModifier(avs); }
void set_ColorModifier_desc(char* desc) { E_ColorModifier::set_desc(desc); }
