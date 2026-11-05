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
#include "e_movingparticle.h"

#include "blend.h"
#include "pixel_format.h"

#include <math.h>

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter MovingParticle_Info::parameters[];

void MovingParticle_Info::on_size_change(Effect* component,
                                         const Parameter* parameter,
                                         const std::vector<int64_t>&) {
    auto particle = (E_MovingParticle*)component;
    particle->set_current_size(particle->get_int(parameter->handle));
}

E_MovingParticle::E_MovingParticle(AVS_Instance* avs)
    : Configurable_Effect(avs),
      cur_size((int32_t)this->config.size),
      c{0.0, 0.0},
      v{-0.01551, 0.0},
      p{-0.6, 0.3} {}

void E_MovingParticle::set_current_size(int64_t size) {
    this->cur_size = (int32_t)size;
}

int E_MovingParticle::render(char[2][2][576],
                             int is_beat,
                             int* framebuffer,
                             int*,
                             int w,
                             int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }
    int32_t xp;
    int32_t yp;
    int32_t ss = min(h / 2, (w * 3) / 8);

    if (is_beat) {
        c[0] = ((rand() % 33) - 16) / 48.0f;
        c[1] = ((rand() % 33) - 16) / 48.0f;
    }

    v[0] -= 0.004 * (p[0] - c[0]);
    v[1] -= 0.004 * (p[1] - c[1]);

    p[0] += v[0];
    p[1] += v[1];

    v[0] *= 0.991;
    v[1] *= 0.991;

    xp = (int32_t)(p[0] * (ss) * (this->config.distance / 32.0)) + w / 2;
    yp = (int32_t)(p[1] * (ss) * (this->config.distance / 32.0)) + h / 2;
    if (is_beat && this->config.on_beat_size_change) {
        this->cur_size = this->config.on_beat_size;
    }
    auto color = (pixel_rgb0_8)(this->config.color & AVS_PIXEL_COLOR_MASK_RGB0_8);
    int32_t size = this->cur_size;
    this->cur_size = (this->cur_size + this->config.size) / 2;
    if (size <= 1) {
        auto dest = (uint32_t*)framebuffer + xp + yp * w;
        if (xp >= 0 && yp >= 0 && xp < w && yp < h) {
            switch (this->config.blend_mode) {
                case PARTICLE_BLEND_REPLACE: blend_replace_1px(&color, dest); break;
                case PARTICLE_BLEND_5050: blend_5050_1px(&color, dest, dest); break;
                case PARTICLE_BLEND_DEFAULT:
                    blend_default_1px(&color, dest, dest);
                    break;
                default:
                case PARTICLE_BLEND_ADDITIVE:
                    blend_default_1px(&color, dest, dest);
                    break;
            }
        }
        return 0;
    }
    if (size > 128) {
        size = 128;
    }
    int32_t y;
    double md = size * size * 0.25;
    yp -= size / 2;
    for (y = 0; y < size; y++) {
        if (yp + y >= 0 && yp + y < h) {
            double yd = (y - size * 0.5);
            double l = sqrt(md - yd * yd);
            auto xs = (int32_t)(l + 0.99);
            int32_t x;
            if (xs < 1) {
                xs = 1;
            }
            int32_t xe = xp + xs;
            if (xe > w) {
                xe = w;
            }
            int32_t xst = xp - xs;
            if (xst < 0) {
                xst = 0;
            }
            auto f = (uint32_t*)&framebuffer[xst + (yp + y) * w];
            switch (this->config.blend_mode) {
                case PARTICLE_BLEND_REPLACE:
                    for (x = xst; x < xe; x++, f++) {
                        blend_replace_1px(&color, f);
                    }
                    break;
                case PARTICLE_BLEND_5050:
                    for (x = xst; x < xe; x++, f++) {
                        blend_5050_1px(&color, f, f);
                    }
                    break;
                case PARTICLE_BLEND_DEFAULT:
                    for (x = xst; x < xe; x++, f++) {
                        blend_default_1px(&color, f, f);
                    }
                    break;
                default:
                case PARTICLE_BLEND_ADDITIVE:
                    for (x = xst; x < xe; x++, f++) {
                        blend_default_1px(&color, f, f);
                    }
                    break;
            }
        }
    }
    return 0;
}

void E_MovingParticle::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        int32_t enabled_and_onbeat = GET_INT();
        this->enabled = bool(enabled_and_onbeat & 0b01);
        this->config.on_beat_size_change = bool(enabled_and_onbeat & 0b10);
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.color = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.distance = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.size = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_size = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.blend_mode = GET_INT();
        pos += 4;
    }
    this->cur_size = (int32_t)this->config.size;
}

int E_MovingParticle::save_legacy(unsigned char* data) {
    int pos = 0;
    int32_t enabled_and_onbeat = (this->enabled ? 0b01 : 0b00)
                                 | (this->config.on_beat_size_change ? 0b10 : 0b00);
    PUT_INT(enabled_and_onbeat);
    pos += 4;
    PUT_INT(this->config.color);
    pos += 4;
    PUT_INT(this->config.distance);
    pos += 4;
    PUT_INT(this->config.size);
    pos += 4;
    PUT_INT(this->config.on_beat_size);
    pos += 4;
    PUT_INT(this->config.blend_mode);
    pos += 4;
    return pos;
}

Effect_Info* create_MovingParticle_Info() { return new MovingParticle_Info(); }
Effect* create_MovingParticle(AVS_Instance* avs) { return new E_MovingParticle(avs); }
void set_MovingParticle_desc(char* desc) { E_MovingParticle::set_desc(desc); }
