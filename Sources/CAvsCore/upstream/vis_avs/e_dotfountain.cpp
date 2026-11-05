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
#include "e_dotfountain.h"

#include "blend.h"
#include "constants.h"
#include "matrix.h"

#include <array>
#include <cmath>
#include <cstdint>

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter DotFountain_Info::color_params[];
constexpr Parameter DotFountain_Info::parameters[];

void DotFountain_Info::init_color_map(Effect* component,
                                      const Parameter* parameter,
                                      const std::vector<int64_t>& path) {
    DotFountain_Info::init_color_map_list(component, parameter, path, 0, 0);
}

void DotFountain_Info::init_color_map_list(Effect* component,
                                           const Parameter*,
                                           const std::vector<int64_t>&,
                                           int64_t,
                                           int64_t) {
    ((E_DotFountain*)component)->init_color_map();
}

E_DotFountain::E_DotFountain(AVS_Instance* avs)
    : Configurable_Effect(avs), points(), color_map() {
    this->init_color_map();
    memset(this->points, 0, sizeof(this->points));
}

void E_DotFountain::init_color_map() {
    for (uint32_t t = 0; t < this->config.colors.size() - 1; ++t) {
        auto color1 = (pixel_rgb0_8)this->config.colors[t].color;
        auto color2 = (pixel_rgb0_8)this->config.colors[t + 1].color;
        pixel_rgb0_8 r = (color1 & 255) << 16;
        pixel_rgb0_8 g = ((color1 >> 8) & 255) << 16;
        pixel_rgb0_8 b = ((color1 >> 16) & 255) << 16;
        pixel_rgb0_8 dr = (((color2 & 255) - (color1 & 255)) << 16) / 16;
        pixel_rgb0_8 dg = ((((color2 >> 8) & 255) - ((color1 >> 8) & 255)) << 16) / 16;
        pixel_rgb0_8 db =
            ((((color2 >> 16) & 255) - ((color1 >> 16) & 255)) << 16) / 16;
        for (int x = 0; x < COLOR_MAP_LERP_STEPS; x++) {
            this->color_map[t * COLOR_MAP_LERP_STEPS + x] =
                (r >> 16) | ((g >> 16) << 8) | ((b >> 16) << 16);
            r += dr;
            g += dg;
            b += db;
        }
    }
}

int E_DotFountain::render(char visdata[2][2][576],
                          int is_beat,
                          int* framebuffer,
                          int*,
                          int w,
                          int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }
    float transform[16];
    float transform2[16];
    matrixRotate(transform, 2, (float)this->config.rotation);
    matrixRotate(transform2, 1, (float)this->config.angle);
    matrixMultiply(transform, transform2);
    matrixTranslate(transform2, 0.0f, -20.0f, 400.0f);
    matrixMultiply(transform, transform2);

    DotFountain_Point tmp_ring[NUM_ROT_DIV];
    DotFountain_Point* prev;
    DotFountain_Point* next;

    // Move all points.
    memcpy(tmp_ring, &this->points[0], sizeof(tmp_ring));
    int generation = NUM_ROT_HEIGHT - 2;
    do {
        float accel_radius = 1.3f / ((float)generation + 100);
        prev = &this->points[generation][0];
        next = &this->points[generation + 1][0];
        for (int angular_pos = 0; angular_pos < NUM_ROT_DIV; angular_pos++) {
            *next = *prev;
            next->radius += next->delta_radius;
            next->delta_height += 0.05f;
            next->delta_radius += accel_radius;
            next->height += next->delta_height;
            next++;
            prev++;
        }
    } while (generation--);

    // Add a new ring of points at the bottom
    next = this->points[0];
    prev = tmp_ring;
    float angle;
    for (int angular_pos = 0; angular_pos < NUM_ROT_DIV; angular_pos++) {
        auto audio_sample = (uint8_t)visdata[1][0][angular_pos] ^ 128;
        int audio = (int)audio_sample * 5 / 4 - 64 + is_beat * 128;
        if (audio > 255) {
            audio = 255;
        }
        next->radius = 1.0f;
        next->height = 250;
        float dr = (float)std::labs(audio) / 200.0f + 1.0f;
        // Initial upward speed
        next->delta_height =
            -dr * (100.0f + (next->delta_height - prev->delta_height)) / 100.0f * 2.8f;
        audio = audio / 4;
        if (audio > 63) {
            audio = 63;
        }
        next->color = this->color_map[audio];
        angle = (float)(angular_pos * M_PI) * 2.0f / NUM_ROT_DIV;
        next->ax = (float)sin(angle);
        next->ay = (float)cos(angle);
        next->delta_radius = 0.0;
        next++;
        prev++;
    }

    // Display points:
    // - polar -> cartesian coordinate transformation
    // - 3D rotation
    // - render according to blendmode
    float zoom = (float)w * 440.0f / 640.0f;
    float zoom2 = (float)h * 440.0f / 480.0f;
    if (zoom2 < zoom) {
        zoom = zoom2;
    }
    DotFountain_Point* cur_point = this->points[0];
    for (generation = 0; generation < NUM_ROT_HEIGHT; generation++) {
        for (int angular_pos = 0; angular_pos < NUM_ROT_DIV; angular_pos++) {
            float x, y, z;
            matrixApply(transform,
                        cur_point->ax * cur_point->radius,
                        cur_point->height,
                        cur_point->ay * cur_point->radius,
                        &x,
                        &y,
                        &z);
            z = zoom / z;
            if (z > 0.0000001) {
                int screen_x = (int)(x * z) + w / 2;
                int screen_y = (int)(y * z) + h / 2;
                if (screen_y >= 0 && screen_y < h && screen_x >= 0 && screen_x < w) {
                    auto dest = (uint32_t*)framebuffer + screen_y * w + screen_x;
                    blend_default_1px(&cur_point->color, dest, dest);
                }
            }
            cur_point++;
        }
    }
    this->config.rotation += (float)this->config.rotation_speed / 5.0f;
    if (this->config.rotation >= 360.0f) {
        this->config.rotation -= 360.0f;
    }
    if (this->config.rotation < 0.0f) {
        this->config.rotation += 360.0f;
    }
    return 0;
}

#define LEGACY_COLOR_COUNT 5

void E_DotFountain::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->config.rotation_speed = GET_INT();
        pos += 4;
    }
    for (uint32_t i = 0; i < LEGACY_COLOR_COUNT && (len - pos >= 4); ++i) {
        this->config.colors[i].color = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.angle = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.rotation = GET_INT() / 32.0f;
        pos += 4;
    }

    this->init_color_map();
}

int E_DotFountain::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->config.rotation_speed);
    pos += 4;
    for (uint32_t i = 0; i < LEGACY_COLOR_COUNT; ++i) {
        if (i < this->config.colors.size()) {
            PUT_INT((uint32_t)this->config.colors[i].color);
        } else {
            PUT_INT(0);
        }
        pos += 4;
    }
    PUT_INT(this->config.angle);
    pos += 4;
    auto int_rotation = (int32_t)(this->config.rotation * 32.0f);
    PUT_INT(int_rotation);
    pos += 4;
    return pos;
}

Effect_Info* create_DotFountain_Info() { return new DotFountain_Info(); }
Effect* create_DotFountain(AVS_Instance* avs) { return new E_DotFountain(avs); }
void set_DotFountain_desc(char* desc) { E_DotFountain::set_desc(desc); }
