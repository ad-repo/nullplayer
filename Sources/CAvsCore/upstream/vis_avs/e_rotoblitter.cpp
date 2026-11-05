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
#include "e_rotoblitter.h"

#include "blend.h"
#include "constants.h"

#include <math.h>

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter RotoBlitter_Info::parameters[];

void RotoBlitter_Info::on_zoom_change(Effect* component,
                                      const Parameter*,
                                      const std::vector<int64_t>&) {
    auto rotoblitter = (E_RotoBlitter*)component;
    rotoblitter->current_zoom = rotoblitter->config.zoom;
}

E_RotoBlitter::E_RotoBlitter(AVS_Instance* avs) : Configurable_Effect(avs) {
    this->current_zoom = this->config.zoom;
    this->direction = 1;
    this->current_rotation = 1.0;
    last_w = 0;
    last_h = 0;
    w_mul = nullptr;
}

E_RotoBlitter::~E_RotoBlitter() {
    if (w_mul) {
        free(w_mul);
    }
    w_mul = nullptr;
    last_w = last_h = 0;
}

int E_RotoBlitter::render(char[2][2][576],
                          int is_beat,
                          int* framebuffer,
                          int* fbout,
                          int w,
                          int h) {
    if (last_w != w || last_h != h || !w_mul) {
        int x;
        if (w_mul) {
            free(w_mul);
        }
        last_w = w;
        last_h = h;
        w_mul = (int*)malloc(sizeof(int) * h);
        for (x = 0; x < h; x++) {
            w_mul[x] = x * w;
        }
    }

    if (is_beat & 0x80000000) {
        return 0;
    }

    auto dest = (unsigned int*)fbout;
    auto src = (unsigned int*)framebuffer;
    auto bdest = (unsigned int*)framebuffer;

    if (is_beat && this->config.on_beat_reverse_enable) {
        this->direction = -this->direction;
    }
    if (!this->config.on_beat_reverse_enable) {
        this->direction = 1;
    }

    this->current_rotation += (1.0 / (1 + this->config.on_beat_reverse_speed * 4))
                              * ((double)this->direction - this->current_rotation);

    if (this->current_rotation > (double)this->direction && this->direction > 0) {
        this->current_rotation = (double)this->direction;
    }
    if (this->current_rotation < (double)this->direction && this->direction < 0) {
        this->current_rotation = (double)this->direction;
    }

    if (is_beat && this->config.on_beat_zoom_enable) {
        this->current_zoom = this->config.on_beat_zoom;
    }

    int64_t zoom;
    if (this->config.zoom < this->config.on_beat_zoom) {
        zoom = max(this->current_zoom, this->config.zoom);
        if (this->current_zoom > this->config.zoom) {
            this->current_zoom -= 3;
        }
    } else {
        zoom = min(this->current_zoom, this->config.zoom);
        if (this->current_zoom < this->config.zoom) {
            this->current_zoom += 3;
        }
    }

    double f_zoom = 1.0 + (double)zoom / -RotoBlitter_Info::parameters[0].int_min;

    double theta = (double)this->config.rotate * this->current_rotation;
    double temp;
    int ds_dx, dt_dx, ds_dy, dt_dy, s, t, sstart, tstart;
    int x;

    temp = cos((theta)*M_PI / 180.0) * f_zoom;
    ds_dx = (int)(temp * 65536.0);
    dt_dy = (int)(temp * 65536.0);
    temp = sin((theta)*M_PI / 180.0) * f_zoom;
    ds_dy = -(int)(temp * 65536.0);
    dt_dx = (int)(temp * 65536.0);

    s = sstart = -(((w - 1) / 2) * ds_dx + ((h - 1) / 2) * ds_dy)
                 + (w - 1) * (32768 + (1 << 20));
    t = tstart = -(((w - 1) / 2) * dt_dx + ((h - 1) / 2) * dt_dy)
                 + (h - 1) * (32768 + (1 << 20));
    int ds, dt;
    ds = (w - 1) << 16;
    dt = (h - 1) << 16;
    int y = h;
    if (ds_dx > -ds && ds_dx < ds && dt_dx > -dt && dt_dx < dt) {
        while (y--) {
            if (ds) {
                s %= ds;
            }
            if (dt) {
                t %= dt;
            }
            if (s < 0) {
                s += ds;
            }
            if (t < 0) {
                t += dt;
            }
            x = w;

#define DO_LOOP(Z)  \
    while (x--) {   \
        Z;          \
        s += ds_dx; \
        t += dt_dx; \
    }
#define DO_LOOPS(Z)                                          \
    if (ds_dx <= 0 && dt_dx <= 0)                            \
        DO_LOOP(if (t < 0) t += dt; if (s < 0) s += ds; Z)   \
    else if (ds_dx <= 0)                                     \
        DO_LOOP(if (t >= dt) t -= dt; if (s < 0) s += ds; Z) \
    else if (dt_dx <= 0)                                     \
        DO_LOOP(if (t < 0) t += dt; if (s >= ds) s -= ds; Z) \
    else                                                     \
        DO_LOOP(if (t >= dt) t -= dt; if (s >= ds) s -= ds; Z)

            if (this->config.bilinear && this->config.blend_mode == BLEND_SIMPLE_5050) {
                uint32_t src_bilinear;
                DO_LOOPS(src_bilinear = blend_bilinear_2x2(
                             &src[(s >> 16) + w_mul[t >> 16]], w, s, t);
                         blend_5050_1px(&src_bilinear, bdest, dest);
                         bdest++;
                         dest++)
            } else if (this->config.bilinear) {
                DO_LOOPS(*dest++ = blend_bilinear_2x2(
                             &src[(s >> 16) + w_mul[t >> 16]], w, s, t))
            } else if (this->config.blend_mode == BLEND_SIMPLE_REPLACE) {
                DO_LOOPS(*dest++ = src[(s >> 16) + w_mul[t >> 16]])
            } else {
                DO_LOOPS(blend_5050_1px(&src[(s >> 16) + w_mul[t >> 16]], bdest, dest);
                         bdest++;
                         dest++)
            }

            s = (sstart += ds_dy);
            t = (tstart += dt_dy);
        }
    }

    return 1;
}

void E_RotoBlitter::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->config.zoom = GET_INT() + RotoBlitter_Info::parameters[0].int_min;
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.rotate = GET_INT() + RotoBlitter_Info::parameters[1].int_min;
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.blend_mode = GET_INT() ? BLEND_SIMPLE_5050 : BLEND_SIMPLE_REPLACE;
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_reverse_enable = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_reverse_speed = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_zoom = GET_INT() + RotoBlitter_Info::parameters[7].int_min;
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_zoom_enable = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.bilinear = GET_INT();
        pos += 4;
    } else {
        this->config.bilinear = 0;
    }

    this->current_zoom = this->config.zoom;
}

int E_RotoBlitter::save_legacy(unsigned char* data) {
    int pos = 0;
    auto zoom = this->config.zoom - RotoBlitter_Info::parameters[0].int_min;
    PUT_INT(zoom);
    pos += 4;
    auto rotate = this->config.rotate - RotoBlitter_Info::parameters[1].int_min;
    PUT_INT(rotate);
    pos += 4;
    PUT_INT(this->config.blend_mode == BLEND_SIMPLE_5050);
    pos += 4;
    PUT_INT(this->config.on_beat_reverse_enable);
    pos += 4;
    PUT_INT(this->config.on_beat_reverse_speed);
    pos += 4;
    auto on_beat_zoom =
        this->config.on_beat_zoom - RotoBlitter_Info::parameters[7].int_min;
    PUT_INT(on_beat_zoom);
    pos += 4;
    PUT_INT(this->config.on_beat_zoom_enable);
    pos += 4;
    PUT_INT(this->config.bilinear);
    pos += 4;
    return pos;
}

Effect_Info* create_RotoBlitter_Info() { return new RotoBlitter_Info(); }
Effect* create_RotoBlitter(AVS_Instance* avs) { return new E_RotoBlitter(avs); }
void set_RotoBlitter_desc(char* desc) { E_RotoBlitter::set_desc(desc); }
