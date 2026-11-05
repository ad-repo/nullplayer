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
#include "e_dynamicmovement.h"

#include "blend.h"
#include "instance.h"

#include <math.h>
#include <mmintrin.h>

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255
#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr DynamicMovement_Example DynamicMovement_Info::examples[];
constexpr Parameter DynamicMovement_Info::parameters[];

void DynamicMovement_Info::recompile(Effect* component,
                                     const Parameter* parameter,
                                     const std::vector<int64_t>&) {
    auto dynamicmovement = (E_DynamicMovement*)component;
    if (std::string("Init") == parameter->name) {
        dynamicmovement->code_init.need_recompile = true;
    } else if (std::string("Frame") == parameter->name) {
        dynamicmovement->code_frame.need_recompile = true;
    } else if (std::string("Beat") == parameter->name) {
        dynamicmovement->code_beat.need_recompile = true;
    } else if (std::string("Point") == parameter->name) {
        dynamicmovement->code_point.need_recompile = true;
    }
}

void DynamicMovement_Info::load_example(Effect* component,
                                        const Parameter*,
                                        const std::vector<int64_t>&) {
    auto dm = ((E_DynamicMovement*)component);
    if (dm->config.example < 0 || dm->config.example >= dm->info.num_examples) {
        return;
    }
    const DynamicMovement_Example& to_load = dm->info.examples[dm->config.example];
    dm->config.init = to_load.init;
    dm->config.frame = to_load.frame;
    dm->config.beat = to_load.beat;
    dm->config.point = to_load.point;
    dm->config.coordinates =
        to_load.rectangular_coordinates ? COORDS_CARTESIAN : COORDS_POLAR;
    dm->config.wrap = to_load.wrap;
    dm->config.grid_w = to_load.grid_w;
    dm->config.grid_h = to_load.grid_h;
    dm->need_full_recompile();
}

E_DynamicMovement::E_DynamicMovement(AVS_Instance* avs)
    : Programmable_Effect(avs),
      last_w(0),
      last_h(0),
      last_x_res(0),
      last_y_res(0),
      w_mul(NULL),
      tab(NULL) {
    this->need_full_recompile();
}

E_DynamicMovement::~E_DynamicMovement() {
    free(this->w_mul);
    this->w_mul = NULL;
    free(this->tab);
    this->tab = NULL;
}

int E_DynamicMovement::render(char visdata[2][2][576],
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

int E_DynamicMovement::smp_finish(char[2][2][576], int, int*, int*, int, int) {
    return !this->alpha_only;
}

int E_DynamicMovement::smp_begin(int max_threads,
                                 char visdata[2][2][576],
                                 int is_beat,
                                 int*,
                                 int*,
                                 int w,
                                 int h) {
    this->bilinear = this->config.bilinear;
    this->coordinates = this->config.coordinates;
    this->blend = this->config.blend;
    this->wrap = this->config.wrap;
    this->alpha_only = this->config.alpha_only;

    this->w_adj = (w - 2) << 16;
    this->h_adj = (h - 2) << 16;
    this->XRES = max(2, this->config.grid_w + 1);
    this->YRES = max(2, this->config.grid_h + 1);

    if (this->last_w != w || this->last_h != h || !this->tab || !this->w_mul
        || this->last_x_res != this->XRES || this->last_y_res != this->YRES) {
        int y;
        this->last_x_res = this->XRES;
        this->last_y_res = this->YRES;
        this->last_w = w;
        this->last_h = h;
        free(this->w_mul);
        this->w_mul = (int*)malloc(sizeof(int) * h);
        for (y = 0; y < h; y++) {
            this->w_mul[y] = y * w;
        }
        free(this->tab);

        this->tab = (int*)malloc(
            (this->XRES * this->YRES * 3 + (this->XRES * 6 + 6) * MAX_SMP_THREADS)
            * sizeof(int));
    }

    if (!this->bilinear) {
        this->w_adj = (w - 1) << 16;
        this->h_adj = (h - 1) << 16;
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
    int y;
    int* tabptr = this->tab;

    double xsc = 2.0 / w, ysc = 2.0 / h;
    double dw2 = ((double)w * 32768.0);
    double dh2 = ((double)h * 32768.0);
    double max_screen_d = sqrt((double)(w * w + h * h)) * 0.5;

    double divmax_d = 1.0 / max_screen_d;

    max_screen_d *= 65536.0;

    int yc_pos, yc_dpos, xc_pos, xc_dpos;
    yc_pos = 0;
    xc_dpos = (w << 16) / (this->XRES - 1);
    yc_dpos = (h << 16) / (this->YRES - 1);
    for (y = 0; y < this->YRES; y++) {
        xc_pos = 0;
        for (x = 0; x < this->XRES; x++) {
            double xd, yd;

            xd = ((double)xc_pos - dw2) * (1.0 / 65536.0);
            yd = ((double)yc_pos - dh2) * (1.0 / 65536.0);

            xc_pos += xc_dpos;

            *this->vars.x = xd * xsc;
            *this->vars.y = yd * ysc;
            *this->vars.d = sqrt(xd * xd + yd * yd) * divmax_d;
            *this->vars.r = atan2(yd, xd) + M_PI * 0.5;

            this->code_point.exec(visdata);

            int tmp1, tmp2;
            if (this->coordinates == COORDS_POLAR) {
                *this->vars.d *= max_screen_d;
                *this->vars.r -= M_PI * 0.5;
                tmp1 = (int)(dw2 + cos(*this->vars.r) * *this->vars.d);
                tmp2 = (int)(dh2 + sin(*this->vars.r) * *this->vars.d);
            } else {
                tmp1 = (int)((*this->vars.x + 1.0) * dw2);
                tmp2 = (int)((*this->vars.y + 1.0) * dh2);
            }
            if (!this->wrap) {
                if (tmp1 < 0) {
                    tmp1 = 0;
                }
                if (tmp1 > this->w_adj) {
                    tmp1 = this->w_adj;
                }
                if (tmp2 < 0) {
                    tmp2 = 0;
                }
                if (tmp2 > this->h_adj) {
                    tmp2 = this->h_adj;
                }
            }
            *tabptr++ = tmp1;
            *tabptr++ = tmp2;
            double va = *this->vars.alpha;
            if (va < 0.0) {
                va = 0.0;
            } else if (va > 1.0) {
                va = 1.0;
            }
            int a = (int)(va * 255.0 * 65536.0);
            *tabptr++ = a;
        }
        yc_pos += yc_dpos;
    }

    return max_threads;
}

void E_DynamicMovement::smp_render(int this_thread,
                                   int max_threads,
                                   char[2][2][576],
                                   int,
                                   int* framebuffer,
                                   int* fbout,
                                   int w,
                                   int h) {
    if (max_threads < 1) {
        max_threads = 1;
    }

    int start_l = (this_thread * h) / max_threads;
    int end_l;
    int ypos = 0;

    if (this_thread >= max_threads - 1) {
        end_l = h;
    } else {
        end_l = ((this_thread + 1) * h) / max_threads;
    }

    int outh = end_l - start_l;
    if (outh < 1) {
        return;
    }

    int* fbin = this->config.buffer == 0
                    ? framebuffer
                    : (int*)this->avs->get_buffer(w, h, this->config.buffer - 1, false);
    if (!fbin) {
        return;
    }
    // yay, the table is generated. now we do a fixed point
    // interpolation of the whole thing and pray.

    int* interptab =
        this->tab + this->XRES * this->YRES * 3 + this_thread * (this->XRES * 6 + 6);
    int* rdtab = this->tab;
    auto in = (uint32_t*)fbin;
    auto blendin = (uint32_t*)framebuffer;
    auto out = (uint32_t*)fbout;
    int yseek = 1;
    int xc_dpos, yc_pos = 0, yc_dpos;
    xc_dpos = (w << 16) / (this->XRES - 1);
    yc_dpos = (h << 16) / (this->YRES - 1);
    int lypos = 0;
    int yl = end_l;
    while (yl > 0) {
        yc_pos += yc_dpos;
        yseek = (yc_pos >> 16) - lypos;
        if (!yseek) {
#ifndef NO_MMX
            _mm_empty();
#endif
            return;
        }
        lypos = yc_pos >> 16;
        int l = this->XRES;
        int* stab = interptab;
        int xr3 = this->XRES * 3;
        while (l--) {
            int tmp1, tmp2, tmp3;
            tmp1 = rdtab[0];
            tmp2 = rdtab[1];
            tmp3 = rdtab[2];
            stab[0] = tmp1;
            stab[1] = tmp2;
            stab[2] = (rdtab[xr3] - tmp1) / yseek;
            stab[3] = (rdtab[xr3 + 1] - tmp2) / yseek;
            stab[4] = tmp3;
            stab[5] = (rdtab[xr3 + 2] - tmp3) / yseek;
            rdtab += 3;
            stab += 6;
        }

        if (yseek > yl) {
            yseek = yl;
        }
        yl -= yseek;

        if (yseek > 0) {
            while (yseek--) {
                int d_x;
                int d_y;
                int d_a;
                int ap;
                int seek;
                int* seektab = interptab;
                int xp, yp;
                int l = w;
                int lpos = 0;
                int xc_pos = 0;
                ypos++;
                {
                    while (l > 0) {
                        xc_pos += xc_dpos;
                        seek = (xc_pos >> 16) - lpos;
                        if (!seek) {
#ifndef NO_MMX
                            _mm_empty();
#endif
                            return;
                        }
                        lpos = xc_pos >> 16;
                        xp = seektab[0];
                        yp = seektab[1];
                        ap = seektab[4];
                        d_a = (seektab[10] - ap) / (seek);
                        d_x = (seektab[6] - xp) / (seek);
                        d_y = (seektab[7] - yp) / (seek);
                        seektab[0] += seektab[2];
                        seektab[1] += seektab[3];
                        seektab[4] += seektab[5];
                        seektab += 6;

                        if (seek > l) {
                            seek = l;
                        }
                        l -= seek;
                        if (seek > 0 && ypos <= start_l) {
                            blendin += seek;
                            if (this->alpha_only) {
                                in += seek;
                            } else {
                                out += seek;
                            }

                            seek = 0;
                        }
                        if (seek > 0) {
#define CHECK
// normal loop
#define NORMAL_LOOP(Z) \
    while ((seek--)) { \
        Z;             \
        xp += d_x;     \
        yp += d_y;     \
    }

#if 0 
              // this would be faster, but seems like it might be less reliable:
#define WRAPPING_LOOPS(Z)                                                            \
    if (d_x <= 0 && d_y <= 0)                                                        \
        NORMAL_LOOP(if (xp < 0) xp += this->w_adj; if (yp < 0) yp += this->h_adj; Z) \
    else if (d_x <= 0)                                                               \
        NORMAL_LOOP(if (xp < 0) xp += this->w_adj;                                   \
                    if (yp >= this->h_adj) yp -= this->h_adj;                        \
                    Z)                                                               \
    else if (d_y <= 0)                                                               \
        NORMAL_LOOP(if (xp >= this->w_adj) xp -= this->w_adj;                        \
                    if (yp < 0) yp += this->h_adj;                                   \
                    Z)                                                               \
    else                                                                             \
        NORMAL_LOOP(if (xp >= this->w_adj) xp -= this->w_adj;                        \
                    if (yp >= this->h_adj) yp -= this->h_adj;                        \
                    Z)

#define CLAMPED_LOOPS(Z)                                                             \
    if (d_x <= 0 && d_y <= 0)                                                        \
        NORMAL_LOOP(if (xp < 0) xp = 0; if (yp < 0) yp = 0; Z)                       \
    else if (d_x <= 0)                                                               \
        NORMAL_LOOP(if (xp < 0) xp = 0; if (yp >= this->h_adj) yp = this->h_adj - 1; \
                    Z)                                                               \
    else if (d_y <= 0)                                                               \
        NORMAL_LOOP(if (xp >= this->w_adj) xp = this->w_adj - 1; if (yp < 0) yp = 0; \
                    Z)                                                               \
    else                                                                             \
        NORMAL_LOOP(if (xp >= this->w_adj) xp = this->w_adj - 1;                     \
                    if (yp >= this->h_adj) yp = this->h_adj - 1;                     \
                    Z)

#else  // slower, more reliable loops

// wrapping loop
#define WRAPPING_LOOPS(Z)                                      \
    NORMAL_LOOP(if (xp < 0) xp += this->w_adj;                 \
                else if (xp >= this->w_adj) xp -= this->w_adj; \
                if (yp < 0) yp += this->h_adj;                 \
                else if (yp >= this->h_adj) yp -= this->h_adj; \
                Z)

#define CLAMPED_LOOPS(Z)                                                              \
    NORMAL_LOOP(if (xp < 0) xp = 0; else if (xp >= this->w_adj) xp = this->w_adj - 1; \
                if (yp < 0) yp = 0;                                                   \
                else if (yp >= this->h_adj) yp = this->h_adj - 1;                     \
                Z)

#endif

#define LOOPS(DO)                                                                      \
    if (this->blend && this->bilinear)                                                 \
        DO(CHECK uint32_t src_bilinear = blend_bilinear_2x2(                           \
               in + (xp >> 16) + (this->w_mul[yp >> 16]), w, xp, yp);                  \
           blend_adjustable_1px(&src_bilinear, blendin++, out++, ap >> 16);            \
           ap += d_a)                                                                  \
    else if (this->blend)                                                              \
        DO(CHECK blend_adjustable_1px(                                                 \
               &in[(xp >> 16) + (this->w_mul[yp >> 16])], blendin++, out++, ap >> 16); \
           ap += d_a)                                                                  \
    else if (this->bilinear)                                                           \
        DO(CHECK* out++ = blend_bilinear_2x2(                                          \
               in + (xp >> 16) + (this->w_mul[yp >> 16]), w, xp, yp))                  \
    else                                                                               \
        DO(CHECK* out++ = in[(xp >> 16) + (this->w_mul[yp >> 16])])

                            if (this->alpha_only) {
                                if (fbin != framebuffer) {
                                    while (seek--) {
                                        blend_adjustable_1px(
                                            in++, blendin, blendin, ap >> 16);
                                        ap += d_a;
                                        blendin++;
                                    }
                                } else {
                                    uint32_t zero = 0;
                                    while (seek--) {
                                        blend_adjustable_1px(
                                            &zero, blendin, blendin, ap >> 16);
                                        ap += d_a;
                                        blendin++;
                                    }
                                }
                            } else if (!this->wrap) {
                                // this might not really be necessary b/c of the
                                // clamping in the loop, but I'm sick of crashes
                                if (xp < 0) {
                                    xp = 0;
                                } else if (xp >= this->w_adj) {
                                    xp = this->w_adj - 1;
                                }
                                if (yp < 0) {
                                    yp = 0;
                                } else if (yp >= this->h_adj) {
                                    yp = this->h_adj - 1;
                                }

                                LOOPS(CLAMPED_LOOPS)
                            } else {  // this->wrap
                                xp %= this->w_adj;
                                yp %= this->h_adj;
                                if (xp < 0) {
                                    xp += this->w_adj;
                                }
                                if (yp < 0) {
                                    yp += this->h_adj;
                                }

                                if (d_x <= -this->w_adj) {
                                    d_x = -this->w_adj + 1;
                                } else if (d_x >= this->w_adj) {
                                    d_x = this->w_adj - 1;
                                }

                                if (d_y <= -this->h_adj) {
                                    d_y = -this->h_adj + 1;
                                } else if (d_y >= this->h_adj) {
                                    d_y = this->h_adj - 1;
                                }

                                LOOPS(WRAPPING_LOOPS)
                            }
                        }  // if seek>0
                    }
                    // adjust final (rightmost elem) part of seektab
                    seektab[0] += seektab[2];
                    seektab[1] += seektab[3];
                    seektab[4] += seektab[5];
                }
            }
        }
    }

#ifndef NO_MMX
    _mm_empty();
#endif
}

void DynamicMovement_Vars::register_(void* vm_context) {
    this->b = NSEEL_VM_regvar(vm_context, "b");
    this->d = NSEEL_VM_regvar(vm_context, "d");
    this->r = NSEEL_VM_regvar(vm_context, "r");
    this->x = NSEEL_VM_regvar(vm_context, "x");
    this->y = NSEEL_VM_regvar(vm_context, "y");
    this->w = NSEEL_VM_regvar(vm_context, "w");
    this->h = NSEEL_VM_regvar(vm_context, "h");
    this->alpha = NSEEL_VM_regvar(vm_context, "alpha");
}

void DynamicMovement_Vars::init(int w, int h, int is_beat, va_list) {
    *this->w = w;
    *this->h = h;
    *this->b = is_beat ? 1.0 : 0.0;
    *this->alpha = 0.5;
}

void E_DynamicMovement::load_legacy(unsigned char* data, int len) {
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
        this->config.bilinear = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.coordinates = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.grid_w = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.grid_h = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.blend = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.wrap = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.buffer = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.alpha_only = GET_INT();
        pos += 4;
    }
}
int E_DynamicMovement::save_legacy(unsigned char* data) {
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
    PUT_INT(this->config.bilinear);
    pos += 4;
    PUT_INT(this->config.coordinates);
    pos += 4;
    PUT_INT(this->config.grid_w);
    pos += 4;
    PUT_INT(this->config.grid_h);
    pos += 4;
    PUT_INT(this->config.blend);
    pos += 4;
    PUT_INT(this->config.wrap);
    pos += 4;
    PUT_INT(this->config.buffer);
    pos += 4;
    PUT_INT(this->config.alpha_only);
    pos += 4;
    return pos;
}

Effect_Info* create_DynamicMovement_Info() { return new DynamicMovement_Info(); }
Effect* create_DynamicMovement(AVS_Instance* avs) { return new E_DynamicMovement(avs); }
void set_DynamicMovement_desc(char* desc) { E_DynamicMovement::set_desc(desc); }
