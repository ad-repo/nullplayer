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
#include "e_dotplane.h"

#include "blend.h"
#include "matrix.h"

#include <cmath>

#include <sys/types.h>

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter DotPlane_Info::color_params[];
constexpr Parameter DotPlane_Info::parameters[];

void DotPlane_Info::init_color_map(Effect* component,
                                   const Parameter* parameter,
                                   const std::vector<int64_t>& path) {
    DotPlane_Info::init_color_map_list(component, parameter, path, 0, 0);
}

void DotPlane_Info::init_color_map_list(Effect* component,
                                        const Parameter*,
                                        const std::vector<int64_t>&,
                                        int64_t,
                                        int64_t) {
    ((E_DotPlane*)component)->init_color_map();
}

E_DotPlane::E_DotPlane(AVS_Instance* avs)
    : Configurable_Effect(avs),
      grid_height(),
      grid_height_delta(),
      grid_color(),
      color_map() {
    this->init_color_map();
}

void E_DotPlane::init_color_map() {
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

int E_DotPlane::render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int*,
                       int w,
                       int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }

    int x_pos;
    int y_pos;
    float transform[16];
    float transform2[16];
    matrixRotate(transform, 2, (float)this->config.rotation);
    matrixRotate(transform2, 1, (float)this->config.angle);
    matrixMultiply(transform, transform2);
    matrixTranslate(transform2, 0.0f, -20.0f, 400.0f);
    matrixMultiply(transform, transform2);

    float tmp_line[GRID_WIDTH];
    memcpy(tmp_line, &grid_height[0], sizeof(float) * GRID_WIDTH);

    int line;
    for (y_pos = 0, line = (GRID_WIDTH - 2) * GRID_WIDTH; y_pos < GRID_WIDTH;
         y_pos++, line -= GRID_WIDTH) {
        float* cur_height = &grid_height[line];
        float* next_height = &grid_height[line + GRID_WIDTH];
        float* cur_delta = &grid_height_delta[line];
        float* next_delta = &grid_height_delta[line + GRID_WIDTH];
        pixel_rgb0_8* prev_color = &grid_color[line];
        pixel_rgb0_8* next_color = &grid_color[line + GRID_WIDTH];
        if (y_pos == GRID_WIDTH - 1) {
            // Push new line
            cur_height = tmp_line;
            for (x_pos = 0; x_pos < GRID_WIDTH; x_pos++) {
                int audio = max(max((uint8_t)visdata[0][0][x_pos * 3],
                                    (uint8_t)visdata[0][0][x_pos * 3 + 1]),
                                (uint8_t)visdata[0][0][x_pos * 3 + 2]);
                next_height[x_pos] = (float)audio;
                next_color[x_pos] = color_map[min(audio / 4, 63)];
                next_delta[x_pos] = (next_height[x_pos] - cur_height[x_pos]) / 90.0f;
            }
        } else {
            // Move existing lines, decrement height & delta_height
            for (x_pos = 0; x_pos < GRID_WIDTH; x_pos++) {
                next_height[x_pos] = cur_height[x_pos] + cur_delta[x_pos];
                if (next_height[x_pos] < 0.0f) {
                    next_height[x_pos] = 0.0f;
                }
                next_delta[x_pos] =
                    cur_delta[x_pos] - 0.15f * (next_height[x_pos] / 255.0f);
                next_color[x_pos] = prev_color[x_pos];
            }
        }
    }

    float zoom = (float)w * 440.0f / 640.0f;
    float zoom2 = (float)h * 440.0f / 480.0f;
    if (zoom2 < zoom) {
        zoom = zoom2;
    }
    for (y_pos = 0; y_pos < GRID_WIDTH; y_pos++) {
        int grid_start_pos =
            (this->config.rotation < 90.0 || this->config.rotation > 270.0)
                ? GRID_WIDTH - y_pos - 1
                : y_pos;
        float grid_step = 350.0f / (float)GRID_WIDTH;
        float cur_y = -(GRID_WIDTH * 0.5f) * grid_step;
        float cur_x = ((float)grid_start_pos - GRID_WIDTH * 0.5f) * grid_step;
        pixel_rgb0_8* color = &grid_color[grid_start_pos * GRID_WIDTH];
        float* height = &grid_height[grid_start_pos * GRID_WIDTH];
        int direction = 1;
        if (this->config.rotation < 180.0) {
            direction = -1;
            grid_step = -grid_step;
            cur_y = -cur_y + grid_step;
            color += GRID_WIDTH - 1;
            height += GRID_WIDTH - 1;
        }
        for (x_pos = 0; x_pos < GRID_WIDTH; x_pos++) {
            float x, y, z;
            matrixApply(transform, cur_y, 64.0f - *height, cur_x, &x, &y, &z);
            z = zoom / z;
            int screen_x = (int)(x * z) + (w / 2);
            int screen_y = (int)(y * z) + (h / 2);
            if (screen_y >= 0 && screen_y < h && screen_x >= 0 && screen_x < w) {
                auto dest = (uint32_t*)framebuffer + screen_y * w + screen_x;
                blend_default_1px(color, dest, dest);
            }
            cur_y += grid_step;
            color += direction;
            height += direction;
        }
    }
    this->config.rotation += (double)this->config.rotation_speed / 5.0f;
    if (this->config.rotation >= 360.0f) {
        this->config.rotation -= 360.0f;
    }
    if (this->config.rotation < 0.0f) {
        this->config.rotation += 360.0f;
    }
    return 0;
}

#define LEGACY_COLOR_COUNT 5

void E_DotPlane::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->config.rotation_speed = GET_INT();
        pos += 4;
    }
    for (uint32_t i = 0; i < LEGACY_COLOR_COUNT && (len - pos >= 4); i++) {
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

int E_DotPlane::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->config.rotation_speed);
    pos += 4;
    for (uint32_t i = 0; i < LEGACY_COLOR_COUNT; i++) {
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

Effect_Info* create_DotPlane_Info() { return new DotPlane_Info(); }
Effect* create_DotPlane(AVS_Instance* avs) { return new E_DotPlane(avs); }
void set_DotPlane_desc(char* desc) { E_DotPlane::set_desc(desc); }
