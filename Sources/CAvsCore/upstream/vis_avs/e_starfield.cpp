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
#include "e_starfield.h"

#include "blend.h"

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;             \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

float E_Starfield::GET_FLOAT(const unsigned char* data, int pos) {
    float f;
    auto a = (unsigned char*)&f;
    a[0] = data[pos];
    a[1] = data[pos + 1];
    a[2] = data[pos + 2];
    a[3] = data[pos + 3];
    return f;
}

void E_Starfield::PUT_FLOAT(float f, unsigned char* data, int pos) {
    auto y = (unsigned char*)&f;
    data[pos] = y[0];
    data[pos + 1] = y[1];
    data[pos + 2] = y[2];
    data[pos + 3] = y[3];
}

constexpr Parameter Starfield_Info::parameters[];

void Starfield_Info::initialize(Effect* component,
                                const Parameter*,
                                const std::vector<int64_t>&) {
    ((E_Starfield*)component)->initialize_stars();
}

void Starfield_Info::set_cur_speed(Effect* component,
                                   const Parameter*,
                                   const std::vector<int64_t>&) {
    ((E_Starfield*)component)->set_cur_speed();
}

E_Starfield::E_Starfield(AVS_Instance* avs)
    : Configurable_Effect(avs),
      abs_stars(350),
      x_off(0),
      y_off(0),
      z_off(255),
      width(0),
      height(0),
      current_speed(6),
      on_beat_speed_diff(0),
      on_beat_cooldown(0) {}

void E_Starfield::initialize_stars() {
    // This used to be MulDiv() which uses a 64-bit intermediate.
    // But the maximum for config.stars is 4096, and 4096 * w * h overflows 32-bit
    // INT_MAX already for 720p, so we explicitly use 64-bit integers instead.
    this->abs_stars = (int)(((uint64_t)this->config.stars * (uint64_t)this->width
                             * (uint64_t)this->height)
                            / (512 * 384));

    if (this->abs_stars > 4095) {
        this->abs_stars = 4095;
    }
    for (int i = 0; i < this->abs_stars; i++) {
        this->stars[i].x = (rand() % this->width) - this->x_off;
        this->stars[i].y = (rand() % this->height) - this->y_off;
        this->stars[i].z = (float)(rand() % 255);
        this->stars[i].speed = (float)(rand() % 9 + 1) / 10;
    }
}

void E_Starfield::set_cur_speed() { this->current_speed = this->config.speed; }

void E_Starfield::create_star(int i) {
    this->stars[i].x = (rand() % this->width) - this->x_off;
    this->stars[i].y = (rand() % this->height) - this->y_off;
    this->stars[i].z = (float)this->z_off;
}

// A very rough variant of the adjustable blend mode. Kept for pixel compatability.
// It creates a "staircased", i.e. aliased progression of values: Every 16th value rises
// by 15 and the values in between are the same:
//   0, 0, ..., 0, 15, 15, ..., 15, 30, 30, ..., etc. until ..., 225, 225
//
// TODO [cleanup]: The render code using it below could probably be written in a simpler
//                 way. It basically colorizes the stars, but shows something even if
//                 the color is black (but not if brightness is).
static uint32_t inline blend_adjustable_rough(uint32_t a, uint32_t b, uint32_t v) {
    return ((a >> 4) & 0x0F0F0F) * (16 - v) + (((b >> 4) & 0x0F0F0F) * v);
}

int E_Starfield::render(char[2][2][576],
                        int is_beat,
                        int* framebuffer,
                        int*,
                        int w,
                        int h) {
    if (this->config.on_beat && is_beat) {
        this->current_speed = this->config.on_beat_speed;
        this->on_beat_speed_diff = (this->config.speed - this->current_speed)
                                   / (float)this->config.on_beat_duration;
        this->on_beat_cooldown = this->config.on_beat_duration;
    }

    if (this->width != w || this->height != h) {
        this->width = w;
        this->height = h;
        this->x_off = this->width / 2;
        this->y_off = this->height / 2;
        this->initialize_stars();
    }
    if (is_beat & 0x80000000) {
        return 0;
    }

    for (int i = 0; i < this->abs_stars; i++) {
        if ((int)this->stars[i].z > 0) {
            int nx = ((this->stars[i].x << 7) / (int)this->stars[i].z) + this->x_off;
            int ny = ((this->stars[i].y << 7) / (int)this->stars[i].z) + this->y_off;
            if ((nx > 0) && (nx < w) && (ny > 0) && (ny < h)) {
                uint32_t brightness =
                    (int)((255 - (int)this->stars[i].z) * this->stars[i].speed);
                if (this->config.color != 0xFFFFFF) {
                    brightness = blend_adjustable_rough(
                        (brightness | (brightness << 8) | (brightness << 16)),
                        this->config.color,
                        brightness >> 4);
                } else {
                    brightness = (brightness | (brightness << 8) | (brightness << 16));
                }
                auto dest = (uint32_t*)&framebuffer[ny * w + nx];
                switch (this->config.blend_mode) {
                    case BLEND_SIMPLE_ADDITIVE:
                        blend_add_1px(&brightness, dest, dest);
                        break;
                    case BLEND_SIMPLE_5050:
                        blend_5050_1px(&brightness, dest, dest);
                        break;
                    default: framebuffer[ny * w + nx] = brightness; break;
                }
                this->stars[i].ox = nx;
                this->stars[i].oy = ny;
                this->stars[i].z -= this->stars[i].speed * this->current_speed;
            } else {
                this->create_star(i);
            }
        } else {
            this->create_star(i);
        }
    }

    if (!this->on_beat_cooldown) {
        this->current_speed = this->config.speed;
    } else {
        this->current_speed = max(0, this->current_speed + this->on_beat_speed_diff);
        this->on_beat_cooldown--;
    }

    return 0;
}

void E_Starfield::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.color = GET_INT();
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
        this->config.speed = GET_FLOAT(data, pos);
        pos += 4;
    }
    this->current_speed = this->config.speed;
    if (len - pos >= 4) {
        this->config.stars = GET_INT();
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
    if (len - pos >= 4) {
        this->config.on_beat_duration = GET_INT();
        pos += 4;
    }
}

int E_Starfield::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->enabled);
    pos += 4;
    PUT_INT(this->config.color);
    pos += 4;
    int32_t blend_additive = this->config.blend_mode == BLEND_SIMPLE_ADDITIVE;
    PUT_INT(blend_additive);
    pos += 4;
    int32_t blend_5050 = this->config.blend_mode == BLEND_SIMPLE_5050;
    PUT_INT(blend_5050);
    pos += 4;
    PUT_FLOAT((float)this->config.speed, data, pos);
    pos += 4;
    PUT_INT(this->config.stars);
    pos += 4;
    PUT_INT(this->config.on_beat);
    pos += 4;
    PUT_FLOAT((float)this->config.on_beat_speed, data, pos);
    pos += 4;
    PUT_INT(this->config.on_beat_duration);
    pos += 4;
    return pos;
}

Effect_Info* create_Starfield_Info() { return new Starfield_Info(); }
Effect* create_Starfield(AVS_Instance* avs) { return new E_Starfield(avs); }
void set_Starfield_desc(char* desc) { E_Starfield::set_desc(desc); }
