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
#include "e_dynamicshift.h"

#include "blend.h"

#include <math.h>

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255
#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter DynamicShift_Info::parameters[];

void DynamicShift_Info::recompile(Effect* component,
                                  const Parameter* parameter,
                                  const std::vector<int64_t>&) {
    auto dynamicshift = (E_DynamicShift*)component;
    if (std::string("Init") == parameter->name) {
        dynamicshift->code_init.need_recompile = true;
    } else if (std::string("Frame") == parameter->name) {
        dynamicshift->code_frame.need_recompile = true;
    } else if (std::string("Beat") == parameter->name) {
        dynamicshift->code_beat.need_recompile = true;
    }
    dynamicshift->recompile_if_needed();
}

E_DynamicShift::E_DynamicShift(AVS_Instance* avs)
    : Programmable_Effect(avs), m_lastw(0), m_lasth(0) {}
E_DynamicShift::~E_DynamicShift() {}

int E_DynamicShift::render(char visdata[2][2][576],
                           int is_beat,
                           int* framebuffer,
                           int* fbout,
                           int w,
                           int h) {
    this->recompile_if_needed();
    if (is_beat & 0x80000000) {
        return 0;
    }

    if (this->need_init || this->m_lastw != w || this->m_lasth != h) {
        this->m_lastw = w;
        this->m_lasth = h;
        *this->vars.x = 0;
        *this->vars.y = 0;
        *this->vars.alpha = 0.5;
        this->code_init.exec(visdata);
        this->need_init = false;
    }
    this->init_variables(w, h, is_beat);
    this->code_frame.exec(visdata);
    if (is_beat) {
        this->code_beat.exec(visdata);
    }

    int doblend = this->config.blend_mode;
    int ialpha = 127;
    if (doblend) {
        ialpha = (int)(*this->vars.alpha * 255.0);
        if (ialpha <= 0) {
            return 0;
        }
        if (ialpha >= 255) {
            doblend = 0;
        }
    }
    auto inptr = (uint32_t*)framebuffer;
    auto blendptr = (uint32_t*)framebuffer;
    auto outptr = (uint32_t*)fbout;
    int xa = (int)*this->vars.x;
    int ya = (int)*this->vars.y;

    if (!this->config.bilinear) {
        int endy = h + ya;
        int endx = w + xa;
        int x, y;
        if (endx > w) {
            endx = w;
        }
        if (endy > h) {
            endy = h;
        }
        if (ya < 0) {
            inptr += -ya * w;
        }
        if (ya > h) {
            ya = h;
        }
        if (xa > w) {
            xa = w;
        }
        if (ya > 0) {
            if (doblend) {
                blend_adjustable_fill(0, blendptr, outptr, ialpha, ya * w);
            } else {
                blend_replace_fill(0, outptr, ya * w);
            }
            blendptr += ya * w;
            outptr += ya * w;
            y = ya;
        } else {
            y = 0;
        }
        for (; y < endy; y++) {
            uint32_t* ip = inptr;
            if (xa < 0) {
                inptr += -xa;
            }
            if (!doblend) {
                for (x = 0; x < xa; x++) {
                    *outptr++ = 0;
                }
                for (; x < endx; x++) {
                    *outptr++ = *inptr++;
                }
                for (; x < w; x++) {
                    *outptr++ = 0;
                }
            } else {
                if (xa > 0) {
                    blend_adjustable_fill(0, blendptr, outptr, ialpha, xa);
                    blendptr += xa;
                    outptr += xa;
                } else {
                    xa = 0;
                }
                blend_adjustable(inptr, blendptr, outptr, ialpha, endx - xa, 1);
                blendptr += endx - xa;
                outptr += endx - xa;
                if (endx < w) {
                    blend_adjustable_fill(0, blendptr, outptr, ialpha, w - endx);
                    blendptr += w - endx;
                    outptr += w - endx;
                }
            }
            inptr = ip + w;
        }
        if (y < h) {
            if (doblend) {
                blend_adjustable_fill(0, blendptr, outptr, ialpha, (h - y) * w);
            } else {
                blend_replace_fill(0, outptr, (h - y) * w);
            }
        }
    } else {  // bilinear filtering version
        int xpart, ypart;

        double vx = *this->vars.x;
        double vy = *this->vars.y;
        xpart = (int)((vx - (int)vx) * 255.0);
        if (xpart < 0) {
            xpart = -xpart;
        } else {
            xa++;
            xpart = 255 - xpart;
        }
        if (xpart < 0) {
            xpart = 0;
        }
        if (xpart > 255) {
            xpart = 255;
        }

        ypart = (int)((vy - (int)vy) * 255.0);
        if (ypart < 0) {
            ypart = -ypart;
        } else {
            ya++;
            ypart = 255 - ypart;
        }
        if (ypart < 0) {
            ypart = 0;
        }
        if (ypart > 255) {
            ypart = 255;
        }

        int x, y;
        if (ya < 1 - h) {
            ya = 1 - h;
        }
        if (xa < 1 - w) {
            xa = 1 - w;
        }
        if (ya > h - 1) {
            ya = h - 1;
        }
        if (xa > w - 1) {
            xa = w - 1;
        }
        if (ya < 0) {
            inptr += -ya * w;
        }
        int endy = h - 1 + ya;
        int endx = w - 1 + xa;
        if (endx > w - 1) {
            endx = w - 1;
        }
        if (endy > h - 1) {
            endy = h - 1;
        }
        if (endx < 0) {
            endx = 0;
        }
        if (endy < 0) {
            endy = 0;
        }
        if (ya > 0) {
            if (doblend) {
                blend_adjustable_fill(0, blendptr, outptr, ialpha, ya * w);
            } else {
                blend_replace_fill(0, outptr, ya * w);
            }
            blendptr += ya * w;
            outptr += ya * w;
            y = ya;
        } else {
            y = 0;
        }
        for (; y < endy; y++) {
            uint32_t* ip = inptr;
            if (xa < 0) {
                inptr += -xa;
            }
            if (!doblend) {
                for (x = 0; x < xa; x++) {
                    *outptr++ = 0;
                }
                for (; x < endx; x++) {
                    *outptr++ = blend_bilinear_2x2(inptr++, w, xpart, ypart);
                }
                for (; x < w; x++) {
                    *outptr++ = 0;
                }
            } else {
                if (xa > 0) {
                    blend_adjustable_fill(0, blendptr, outptr, ialpha, xa);
                    blendptr += xa;
                    outptr += xa;
                    x = xa;
                } else {
                    x = 0;
                }
                for (; x < endx; x++) {
                    auto src_bilinear = blend_bilinear_2x2(inptr++, w, xpart, ypart);
                    blend_adjustable_1px(&src_bilinear, blendptr++, outptr++, ialpha);
                }
                if (endx < w) {
                    blend_adjustable_fill(0, blendptr, outptr, ialpha, w - endx);
                    blendptr += w - endx;
                    outptr += w - endx;
                }
            }
            inptr = ip + w;
        }
        if (y < h) {
            if (doblend) {
                blend_adjustable_fill(0, blendptr, outptr, ialpha, (h - y) * w);
            } else {
                blend_replace_fill(0, outptr, (h - y) * w);
            }
        }
    }

    return 1;
}

void DynamicShift_Vars::register_(void* vm_context) {
    this->x = NSEEL_VM_regvar(vm_context, "x");
    this->y = NSEEL_VM_regvar(vm_context, "y");
    this->w = NSEEL_VM_regvar(vm_context, "w");
    this->h = NSEEL_VM_regvar(vm_context, "h");
    this->b = NSEEL_VM_regvar(vm_context, "b");
    this->alpha = NSEEL_VM_regvar(vm_context, "alpha");
}

void DynamicShift_Vars::init(int w, int h, int is_beat, va_list) {
    *this->x = 0.0;
    *this->y = 0.0;
    *this->w = w;
    *this->h = h;
    *this->b = is_beat ? 1.0 : 0.0;
    *this->alpha = 0.5;
}

void E_DynamicShift::load_legacy(unsigned char* data, int len) {
    char* str_data = (char*)data;
    int pos = 0;
    if (data[pos] == 1) {
        pos++;
        pos += this->string_load_legacy(&str_data[pos], this->config.init, len - pos);
        pos += this->string_load_legacy(&str_data[pos], this->config.frame, len - pos);
        pos += this->string_load_legacy(&str_data[pos], this->config.beat, len - pos);
    } else {
        char buf[769];
        if (len - pos >= 768) {
            memcpy(buf, data + pos, 768);
            pos += 768;
            buf[768] = 0;
            this->config.beat.assign(buf + 512);
            buf[512] = 0;
            this->config.frame.assign(buf + 256);
            buf[256] = 0;
            this->config.init.assign(buf);
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

int E_DynamicShift::save_legacy(unsigned char* data) {
    char* str_data = (char*)data;
    int pos = 0;
    data[pos++] = 1;
    pos += this->string_save_legacy(
        this->config.init, &str_data[pos], MAX_CODE_LEN - 1 - pos, /*with_nt*/ true);
    pos += this->string_save_legacy(
        this->config.frame, &str_data[pos], MAX_CODE_LEN - 1 - pos, /*with_nt*/ true);
    pos += this->string_save_legacy(
        this->config.beat, &str_data[pos], MAX_CODE_LEN - 1 - pos, /*with_nt*/ true);
    PUT_INT(this->config.blend_mode);
    pos += 4;
    PUT_INT(this->config.bilinear ? 1 : 0);
    pos += 4;
    return pos;
}

Effect_Info* create_DynamicShift_Info() { return new DynamicShift_Info(); }
Effect* create_DynamicShift(AVS_Instance* avs) { return new E_DynamicShift(avs); }
void set_DynamicShift_desc(char* desc) { E_DynamicShift::set_desc(desc); }
