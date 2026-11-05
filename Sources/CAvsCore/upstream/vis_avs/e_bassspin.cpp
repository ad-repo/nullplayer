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
// alphachannel safe (sets alpha to 0 on rendered portions) 11/21/99

#include "e_bassspin.h"

#include "blend.h"
#include "linedraw.h"

#include <cmath>

#define F16(x) ((x) << 16)

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter BassSpin_Info::parameters[];

E_BassSpin::E_BassSpin(AVS_Instance* avs)
    : Configurable_Effect(avs),
      last_a(0),
      lx{{0, 0}, {0, 0}},
      ly{{0, 0}, {0, 0}},
      r_v{3.14159, 0.0},
      v{0, 0},
      dir{-1.0, 1.0} {}

// TODO [clean]: Replace this method by reusing the one from Triangle
void E_BassSpin::render_triangle(uint32_t* fb,
                                 int32_t points[6],
                                 int32_t width,
                                 int32_t height,
                                 uint32_t color) {
    int32_t tmp_p;
    for (int32_t i = 0; i < 2; i++) {
        if (points[1] > points[3]) {
            tmp_p = points[2];
            points[2] = points[0];
            points[0] = tmp_p;
            tmp_p = points[3];
            points[3] = points[1];
            points[1] = tmp_p;
        }
        if (points[3] > points[5]) {
            tmp_p = points[4];
            points[4] = points[2];
            points[2] = tmp_p;
            tmp_p = points[5];
            points[5] = points[3];
            points[3] = tmp_p;
        }
    }

    int32_t x1 = F16(points[0]);
    int32_t x2 = F16(points[0]);
    int32_t dx1 = points[1] < points[3]
                      ? F16(points[2] - points[0]) / (points[3] - points[1])
                      : 0;
    int32_t dx2 = points[1] < points[5]
                      ? F16(points[4] - points[0]) / (points[5] - points[1])
                      : 0;

    fb += points[1] * width;
    int32_t max_y = min(points[5], height);
    for (int32_t y = points[1]; y < max_y; y++) {
        if (y == points[3]) {
            if (y == points[5]) {
                return;
            }
            x1 = F16(points[2]);
            dx1 = F16(points[4] - points[2]) / (points[5] - points[3]);
        }
        if (y >= 0) {
            int32_t x;
            int32_t xl;
            x = (min(x1, x2) - 32768) >> 16;
            xl = ((max(x1, x2) + 32768) >> 16) - x;
            if (xl < 0) {
                xl = -xl;
            }
            if (!xl) {
                xl++;
            }
            uint32_t* t = fb + x;
            if (x < 0) {
                t -= x;
                xl -= x;
            }
            if (x + xl >= width) {
                xl = width - x;
            }
            if (xl > 0) {
                while (xl--) {
                    blend_default_1px(&color, t, t++);
                }
            }
        }
        fb += width;
        x1 += dx1;
        x2 += dx2;
    }
}

int E_BassSpin::render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int*,
                       int w,
                       int h) {
    int32_t x;
    int32_t triangle;
    if (is_beat & 0x80000000) {
        return 0;
    }
    for (triangle = 0; triangle < 2; triangle++) {
        if (!(triangle ? this->config.enabled_left : this->config.enabled_right)) {
            continue;
        }
        auto fa_data = (uint8_t*)visdata[0][triangle];
        int32_t xp;
        int32_t yp;
        int32_t screen_size = min(h / 2, (w * 3) / 8);
        auto screen_size_f = (double)screen_size;
        int32_t c_x = (!triangle ? w / 2 - screen_size / 2 : w / 2 + screen_size / 2);
        int32_t a = 0, d = 0;
        auto color =
            (uint32_t)(triangle ? this->config.color_right : this->config.color_left);
        for (x = 0; x < 44; x++) {
            d += fa_data[x];
        }

        a = (d * 512) / (last_a + 30 * 256);

        last_a = d;

        if (a > 255) {
            a = 255;
        }
        v[triangle] = 0.7 * (max(a - 104, 12) / 96.0) + 0.3 * v[triangle];
        r_v[triangle] += 3.14159 / 6.0 * v[triangle] * dir[triangle];

        screen_size_f *= a * 1.0 / 256.0f;
        yp = (int32_t)(sin(r_v[triangle]) * screen_size_f);
        xp = (int32_t)(cos(r_v[triangle]) * screen_size_f);
        if (this->config.mode == BASSSPIN_MODE_OUTLINE) {
            if (lx[0][triangle] || ly[0][triangle]) {
                line((uint32_t*)framebuffer,
                     lx[0][triangle],
                     ly[0][triangle],
                     xp + c_x,
                     yp + h / 2,
                     w,
                     h,
                     color,
                     (g_line_blend_mode & 0xff0000) >> 16);
            }
            lx[0][triangle] = xp + c_x;
            ly[0][triangle] = yp + h / 2;
            line((uint32_t*)framebuffer,
                 c_x,
                 h / 2,
                 c_x + xp,
                 h / 2 + yp,
                 w,
                 h,
                 color,
                 (g_line_blend_mode & 0xff0000) >> 16);
            if (lx[1][triangle] || ly[1][triangle]) {
                line((uint32_t*)framebuffer,
                     lx[1][triangle],
                     ly[1][triangle],
                     c_x - xp,
                     h / 2 - yp,
                     w,
                     h,
                     color,
                     (g_line_blend_mode & 0xff0000) >> 16);
            }
            lx[1][triangle] = c_x - xp;
            ly[1][triangle] = h / 2 - yp;
            line((uint32_t*)framebuffer,
                 c_x,
                 h / 2,
                 c_x - xp,
                 h / 2 - yp,
                 w,
                 h,
                 color,
                 (g_line_blend_mode & 0xff0000) >> 16);
        } else if (this->config.mode == BASSSPIN_MODE_FILLED) {
            if (lx[0][triangle] || ly[0][triangle]) {
                int32_t points[6] = {
                    c_x, h / 2, lx[0][triangle], ly[0][triangle], xp + c_x, yp + h / 2};
                render_triangle((uint32_t*)framebuffer, points, w, h, color);
            }
            lx[0][triangle] = xp + c_x;
            ly[0][triangle] = yp + h / 2;
            if (lx[1][triangle] || ly[1][triangle]) {
                int32_t points[6] = {
                    c_x, h / 2, lx[1][triangle], ly[1][triangle], c_x - xp, h / 2 - yp};
                render_triangle((uint32_t*)framebuffer, points, w, h, color);
            }
            lx[1][triangle] = c_x - xp;
            ly[1][triangle] = h / 2 - yp;
        }
    }
    return 0;
}

void E_BassSpin::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        uint32_t enabled_left_right = GET_INT();
        this->config.enabled_left = enabled_left_right & 0b01;
        this->config.enabled_right = enabled_left_right & 0b10;
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.color_left = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.color_right = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.mode = GET_INT() ? BASSSPIN_MODE_FILLED : BASSSPIN_MODE_OUTLINE;
        pos += 4;
    }
}

int E_BassSpin::save_legacy(unsigned char* data) {
    int pos = 0;
    uint32_t enabled_left_right = (this->config.enabled_left ? 0b01 : 0b00)
                                  | (this->config.enabled_right ? 0b10 : 0b00);
    PUT_INT(enabled_left_right);
    pos += 4;
    PUT_INT(this->config.color_left);
    pos += 4;
    PUT_INT(this->config.color_right);
    pos += 4;
    PUT_INT(this->config.mode == BASSSPIN_MODE_FILLED);
    pos += 4;
    return pos;
}

Effect_Info* create_BassSpin_Info() { return new BassSpin_Info(); }
Effect* create_BassSpin(AVS_Instance* avs) { return new E_BassSpin(avs); }
void set_BassSpin_desc(char* desc) { E_BassSpin::set_desc(desc); }
