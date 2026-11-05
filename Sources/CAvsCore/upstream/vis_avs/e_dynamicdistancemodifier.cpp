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
#include "e_dynamicdistancemodifier.h"

#include "avs_eelif.h"
#include "blend.h"

#include <math.h>

// Integer Square Root function

// Uses factoring to find square root
// A 256 entry table used to work out the square root of the 7 or 8 most
// significant bits.  A power of 2 used to approximate the rest.
// Based on an 80386 Assembly implementation by Arne Steinarson

static unsigned const char sq_table[] = {
    0,   16,  22,  27,  32,  35,  39,  42,  45,  48,  50,  53,  55,  57,  59,  61,
    64,  65,  67,  69,  71,  73,  75,  76,  78,  80,  81,  83,  84,  86,  87,  89,
    90,  91,  93,  94,  96,  97,  98,  99,  101, 102, 103, 104, 106, 107, 108, 109,
    110, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126,
    128, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142,
    143, 144, 144, 145, 146, 147, 148, 149, 150, 150, 151, 152, 153, 154, 155, 155,
    156, 157, 158, 159, 160, 160, 161, 162, 163, 163, 164, 165, 166, 167, 167, 168,
    169, 170, 170, 171, 172, 173, 173, 174, 175, 176, 176, 177, 178, 178, 179, 180,
    181, 181, 182, 183, 183, 184, 185, 185, 186, 187, 187, 188, 189, 189, 190, 191,
    192, 192, 193, 193, 194, 195, 195, 196, 197, 197, 198, 199, 199, 200, 201, 201,
    202, 203, 203, 204, 204, 205, 206, 206, 207, 208, 208, 209, 209, 210, 211, 211,
    212, 212, 213, 214, 214, 215, 215, 216, 217, 217, 218, 218, 219, 219, 220, 221,
    221, 222, 222, 223, 224, 224, 225, 225, 226, 226, 227, 227, 228, 229, 229, 230,
    230, 231, 231, 232, 232, 233, 234, 234, 235, 235, 236, 236, 237, 237, 238, 238,
    239, 240, 240, 241, 241, 242, 242, 243, 243, 244, 244, 245, 245, 246, 246, 247,
    247, 248, 248, 249, 249, 250, 250, 251, 251, 252, 252, 253, 253, 254, 254, 255};

static inline unsigned long isqrt(unsigned long n) {
    if (n >= 0x10000) {
        if (n >= 0x1000000) {
            if (n >= 0x10000000) {
                if (n >= 0x40000000) {
                    return (sq_table[n >> 24] << 8);
                } else {
                    return (sq_table[n >> 22] << 7);
                }
            } else if (n >= 0x4000000) {
                return (sq_table[n >> 20] << 6);
            } else {
                return (sq_table[n >> 18] << 5);
            }
        } else if (n >= 0x100000) {
            if (n >= 0x400000) {
                return (sq_table[n >> 16] << 4);
            } else {
                return (sq_table[n >> 14] << 3);
            }
        } else if (n >= 0x40000) {
            return (sq_table[n >> 12] << 2);
        } else {
            return (sq_table[n >> 10] << 1);
        }
    }

    else if (n >= 0x100) {
        if (n >= 0x1000) {
            if (n >= 0x4000) {
                return (sq_table[n >> 8]);
            } else {
                return (sq_table[n >> 6] >> 1);
            }
        } else if (n >= 0x400) {
            return (sq_table[n >> 4] >> 2);
        } else {
            return (sq_table[n >> 2] >> 3);
        }
    } else if (n >= 0x10) {
        if (n >= 0x40) {
            return (sq_table[n] >> 4);
        } else {
            return (sq_table[n << 2] << 5);
        }
    } else if (n >= 0x4) {
        return (sq_table[n >> 4] << 6);
    } else {
        return (sq_table[n >> 6] << 7);
    }
}

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255
#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

// --------------------------

constexpr Parameter DynamicDistanceModifier_Info::parameters[];

void DynamicDistanceModifier_Info::recompile(Effect* component,
                                             const Parameter* parameter,
                                             const std::vector<int64_t>&) {
    auto ddm = (E_DynamicDistanceModifier*)component;
    if (std::string("Init") == parameter->name) {
        ddm->code_init.need_recompile = true;
    } else if (std::string("Frame") == parameter->name) {
        ddm->code_frame.need_recompile = true;
    } else if (std::string("Beat") == parameter->name) {
        ddm->code_beat.need_recompile = true;
    } else if (std::string("Point") == parameter->name) {
        ddm->code_point.need_recompile = true;
    }
    ddm->recompile_if_needed();
}

E_DynamicDistanceModifier::E_DynamicDistanceModifier(AVS_Instance* avs)
    : Programmable_Effect(avs), m_lastw(0), m_lasth(0), m_wmul(NULL), m_tab(NULL) {
    this->need_full_recompile();
}

E_DynamicDistanceModifier::~E_DynamicDistanceModifier() {
    free(this->m_wmul);
    free(this->m_tab);
    this->m_tab = 0;
    this->m_wmul = 0;
}

int E_DynamicDistanceModifier::render(char visdata[2][2][576],
                                      int is_beat,
                                      int* framebuffer,
                                      int* fbout,
                                      int w,
                                      int h) {
    if (this->m_lasth != h || this->m_lastw != w || !this->m_tab || !this->m_wmul) {
        int y;
        this->m_lastw = w;  // jf 121100 - added (oops)
        this->m_lasth = h;
        this->max_d = sqrt((w * w + h * h) / 4.0);
        free(this->m_wmul);
        this->m_wmul = (int*)malloc(sizeof(int) * h);
        for (y = 0; y < h; y++) {
            this->m_wmul[y] = y * w;
        }
        free(this->m_tab);
        this->m_tab = NULL;
    }
    int imax_d = (int)(this->max_d + 32.9);
    if (imax_d < 33) {
        imax_d = 33;
    }
    if (!this->m_tab) {
        this->m_tab = (int*)malloc(sizeof(int) * imax_d);
    }

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
    int x;
    if (this->code_point.is_valid()) {
        for (x = 0; x < imax_d - 32; x++) {
            *this->vars.d = x / (this->max_d - 1);
            this->code_point.exec(visdata);
            this->m_tab[x] = (int)(*this->vars.d * 256.0 * this->max_d / (x + 1));
        }
        for (; x < imax_d; x++) {
            this->m_tab[x] = this->m_tab[x - 1];
        }
    } else {
        for (x = 0; x < imax_d; x++) {
            this->m_tab[x] = 0;
        }
    }

    int w2 = w / 2;
    int h2 = h / 2;
    int y;
    auto in = (uint32_t*)framebuffer;
    auto out = (uint32_t*)fbout;
    auto in2 = in;
    for (y = 0; y < h; y++) {
        int ty = y - h2;
        int x2 = w2 * w2 + w2 + ty * ty + 256;
        int dx2 = -2 * w2;
        int yysc = ty;
        int xxsc = -w2;
        int x = w;
        if (this->config.bilinear) {
            if (this->config.blend_mode == BLEND_SIMPLE_5050) {
                while (x--) {
                    int qd = this->m_tab[isqrt(x2)];
                    int ow, oh;
                    int xpart, ypart;
                    x2 += dx2;
                    dx2 += 2;
                    xpart = (qd * xxsc + 128);
                    ypart = (qd * yysc + 128);
                    ow = w2 + (xpart >> 8);
                    oh = h2 + (ypart >> 8);
                    xpart &= 0xff;
                    ypart &= 0xff;
                    xxsc++;

                    if (ow < 0) {
                        ow = 0;
                    } else if (ow >= w - 1) {
                        ow = w - 2;
                    }
                    if (oh < 0) {
                        oh = 0;
                    } else if (oh >= h - 1) {
                        oh = h - 2;
                    }

                    uint32_t src =
                        blend_bilinear_2x2(&in[ow + this->m_wmul[oh]], w, xpart, ypart);
                    blend_5050_1px(&src, in2++, out++);
                }
            } else {
                while (x--) {
                    int qd = this->m_tab[isqrt(x2)];
                    int ow, oh;
                    int xpart, ypart;
                    x2 += dx2;
                    dx2 += 2;
                    xpart = (qd * xxsc + 128);
                    ypart = (qd * yysc + 128);
                    ow = w2 + (xpart >> 8);
                    oh = h2 + (ypart >> 8);
                    xpart &= 0xff;
                    ypart &= 0xff;
                    xxsc++;

                    if (ow < 0) {
                        ow = 0;
                    } else if (ow >= w - 1) {
                        ow = w - 2;
                    }
                    if (oh < 0) {
                        oh = 0;
                    } else if (oh >= h - 1) {
                        oh = h - 2;
                    }

                    uint32_t src =
                        blend_bilinear_2x2(&in[ow + this->m_wmul[oh]], w, xpart, ypart);
                    blend_replace_1px(&src, out++);
                }
            }
        } else {
            if (this->config.blend_mode == BLEND_SIMPLE_5050) {
                while (x--) {
                    int qd = this->m_tab[isqrt(x2)];
                    int ow, oh;
                    x2 += dx2;
                    dx2 += 2;
                    ow = w2 + ((qd * xxsc + 128) >> 8);
                    xxsc++;
                    oh = h2 + ((qd * yysc + 128) >> 8);

                    if (ow < 0) {
                        ow = 0;
                    } else if (ow >= w) {
                        ow = w - 1;
                    }
                    if (oh < 0) {
                        oh = 0;
                    } else if (oh >= h) {
                        oh = h - 1;
                    }

                    blend_5050_1px(&in[ow + this->m_wmul[oh]], in2++, out++);
                }
            } else {
                while (x--) {
                    int qd = this->m_tab[isqrt(x2)];
                    int ow, oh;
                    x2 += dx2;
                    dx2 += 2;
                    ow = w2 + ((qd * xxsc + 128) >> 8);
                    xxsc++;
                    oh = h2 + ((qd * yysc + 128) >> 8);

                    if (ow < 0) {
                        ow = 0;
                    } else if (ow >= w) {
                        ow = w - 1;
                    }
                    if (oh < 0) {
                        oh = 0;
                    } else if (oh >= h) {
                        oh = h - 1;
                    }

                    blend_replace_1px(&in[ow + this->m_wmul[oh]], out++);
                }
            }
        }
    }
    return 1;
}

void DynamicDistanceModifier_Vars::register_(void* vm_context) {
    this->d = NSEEL_VM_regvar(vm_context, "d");
    this->b = NSEEL_VM_regvar(vm_context, "b");
}

void DynamicDistanceModifier_Vars::init(int, int, int is_beat, va_list) {
    *this->b = is_beat ? 1.0 : 0.0;
}

void E_DynamicDistanceModifier::load_legacy(unsigned char* data, int len) {
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
        this->config.blend_mode = GET_INT() ? BLEND_SIMPLE_5050 : BLEND_SIMPLE_REPLACE;
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.bilinear = GET_INT();
        pos += 4;
    }
}

int E_DynamicDistanceModifier::save_legacy(unsigned char* data) {
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
    PUT_INT(this->config.blend_mode);
    pos += 4;
    PUT_INT(this->config.bilinear ? 1 : 0);
    pos += 4;
    return pos;
}

Effect_Info* create_DynamicDistanceModifier_Info() {
    return new DynamicDistanceModifier_Info();
}
Effect* create_DynamicDistanceModifier(AVS_Instance* avs) {
    return new E_DynamicDistanceModifier(avs);
}
void set_DynamicDistanceModifier_desc(char* desc) {
    E_DynamicDistanceModifier::set_desc(desc);
}
