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
#include "e_rotstar.h"

#include "linedraw.h"

#include <math.h>

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255
#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter RotStar_Info::parameters[];
constexpr Parameter RotStar_Info::color_params[];

E_RotStar::E_RotStar(AVS_Instance* avs)
    : Configurable_Effect(avs), color_pos(0), r(0.0) {}
E_RotStar::~E_RotStar() {}

int E_RotStar::render(char visdata[2][2][576],
                      int is_beat,
                      int* framebuffer,
                      int*,
                      int w,
                      int h) {
    int x, y, c;
    int current_color;

    if (is_beat & 0x80000000) {
        return 0;
    }
    if (this->config.colors.empty()) {
        return 0;
    }

    color_pos++;
    if (color_pos >= this->config.colors.size() * 64) {
        color_pos = 0;
    }
    uint32_t p = color_pos / 64;
    uint32_t r = color_pos & 63;
    int c1, c2;
    int r1, r2, r3;
    c1 = this->config.colors[p].color;
    if (p + 1 < this->config.colors.size()) {
        c2 = this->config.colors[p + 1].color;
    } else {
        c2 = this->config.colors[0].color;
    }
    r1 = (((c1 & 255) * (63 - r)) + ((c2 & 255) * r)) / 64;
    r2 = ((((c1 >> 8) & 255) * (63 - r)) + (((c2 >> 8) & 255) * r)) / 64;
    r3 = ((((c1 >> 16) & 255) * (63 - r)) + (((c2 >> 16) & 255) * r)) / 64;
    current_color = r1 | (r2 << 8) | (r3 << 16);

    x = (int)(cos(this->r) * w / 4.0);
    y = (int)(sin(this->r) * h / 4.0);
    for (c = 0; c < 2; c++) {
        double r2 = -this->r;
        int s = 0;
        int t;
        int a, b;
        int nx, ny;
        int lx, ly, l;
        a = x;
        b = y;

        for (l = 3; l < 14; l++) {
            if (visdata[0][c][l] > s && visdata[0][c][l] > visdata[0][c][l + 1] + 4
                && visdata[0][c][l] > visdata[0][c][l - 1] + 4) {
                s = visdata[0][c][l];
            }
        }

        if (c == 1) {
            a = -a;
            b = -b;
        }

        double vw, vh;
        vw = w / 8.0 * (s + 9) / 88.0;
        vh = h / 8.0 * (s + 9) / 88.0;

        nx = (int)(cos(r2) * vw);
        ny = (int)(sin(r2) * vh);
        lx = w / 2 + a + nx;
        ly = h / 2 + b + ny;

        r2 += 3.14159 * 4.0 / 5.0;

        for (t = 0; t < 5; t++) {
            int nx, ny;
            nx = (int)(cos(r2) * vw + w / 2 + a);
            ny = (int)(sin(r2) * vh + h / 2 + b);
            r2 += 3.14159 * 4.0 / 5.0;
            line((uint32_t*)framebuffer,
                 lx,
                 ly,
                 nx,
                 ny,
                 w,
                 h,
                 current_color,
                 (g_line_blend_mode & 0xff0000) >> 16);
            lx = nx;
            ly = ny;
        }
    }
    this->r += 0.1;
    return 0;
}

void E_RotStar::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    uint32_t num_colors = 0;
    if (len - pos >= 4) {
        num_colors = GET_INT();
        pos += 4;
    }
    this->config.colors.clear();
    if (num_colors <= 16) {
        for (uint32_t i = 0; len - pos >= 4 && i < num_colors; i++) {
            uint32_t color = GET_INT();
            this->config.colors.emplace_back(color);
            pos += 4;
        }
    }
}

int E_RotStar::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->config.colors.size());
    pos += 4;
    for (auto const& color : this->config.colors) {
        PUT_INT(color.color);
        pos += 4;
    }
    return pos;
}

Effect_Info* create_RotStar_Info() { return new RotStar_Info(); }
Effect* create_RotStar(AVS_Instance* avs) { return new E_RotStar(avs); }
void set_RotStar_desc(char* desc) { E_RotStar::set_desc(desc); }
