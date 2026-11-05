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
#include "e_waterbump.h"

#include <math.h>
#include <stdlib.h>

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))
#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

constexpr Parameter WaterBump_Info::parameters[];

E_WaterBump::E_WaterBump(AVS_Instance* avs)
    : Configurable_Effect(avs), buffer_w(0), buffer_h(0), page(0) {
    this->buffers[0] = nullptr;
    this->buffers[1] = nullptr;
}
E_WaterBump::~E_WaterBump() {
    free(this->buffers[0]);
    free(this->buffers[1]);
}

void E_WaterBump::SineBlob(int x, int y, int radius, int height, int page) {
    int cx, cy;
    int left, top, right, bottom;
    int square;
    double dist;
    int radsquare = radius * radius;
    double length = (1024.0 / (float)radius) * (1024.0 / (float)radius);

    if (x < 0) {
        x = 1 + radius + rand() % (this->buffer_w - 2 * radius - 1);
    }
    if (y < 0) {
        y = 1 + radius + rand() % (this->buffer_h - 2 * radius - 1);
    }

    radsquare = (radius * radius);

    left = -radius;
    right = radius;
    top = -radius;
    bottom = radius;

    // Perform edge clipping...
    if (x - radius < 1) {
        left -= (x - radius - 1);
    }
    if (y - radius < 1) {
        top -= (y - radius - 1);
    }
    if (x + radius > this->buffer_w - 1) {
        right -= (x + radius - this->buffer_w + 1);
    }
    if (y + radius > this->buffer_h - 1) {
        bottom -= (y + radius - this->buffer_h + 1);
    }

    for (cy = top; cy < bottom; cy++) {
        for (cx = left; cx < right; cx++) {
            square = cy * cy + cx * cx;
            if (square < radsquare) {
                dist = sqrt(square * length);
                this->buffers[page][this->buffer_w * (cy + y) + cx + x] +=
                    (int)((cos(dist) + 0xffff) * (height)) >> 19;
            }
        }
    }
}

/*
void E_WaterBump::HeightBlob(int x, int y, int radius, int height, int page) {
    int rquad;
    int cx, cy, cyq;
    int left, top, right, bottom;

    rquad = radius * radius;

    // Make a randomly-placed blob...
    if (x < 0) x = 1 + radius + rand() % (this->buffer_w - 2 * radius - 1);
    if (y < 0) y = 1 + radius + rand() % (this->buffer_h - 2 * radius - 1);

    left = -radius;
    right = radius;
    top = -radius;
    bottom = radius;

    // Perform edge clipping...
    if (x - radius < 1) left -= (x - radius - 1);
    if (y - radius < 1) top -= (y - radius - 1);
    if (x + radius > this->buffer_w - 1) right -= (x + radius - this->buffer_w + 1);
    if (y + radius > this->buffer_h - 1) bottom -= (y + radius - this->buffer_h + 1);

    for (cy = top; cy < bottom; cy++) {
        cyq = cy * cy;
        for (cx = left; cx < right; cx++) {
            if (cx * cx + cyq < rquad)
                this->buffers[page][this->buffer_w * (cy + y) + (cx + x)] += height;
        }
    }
}
*/

void E_WaterBump::CalcWater(int npage, int fluidity) {
    int newh;
    int count = this->buffer_w + 1;

    int* newptr = this->buffers[npage];
    int* oldptr = this->buffers[!npage];

    int x, y;

    for (y = (this->buffer_h - 1) * this->buffer_w; count < y; count += 2) {
        for (x = count + this->buffer_w - 2; count < x; count++) {
            // This does the eight-pixel method.  It looks much better.

            newh = ((oldptr[count + this->buffer_w] + oldptr[count - this->buffer_w]
                     + oldptr[count + 1] + oldptr[count - 1]
                     + oldptr[count - this->buffer_w - 1]
                     + oldptr[count - this->buffer_w + 1]
                     + oldptr[count + this->buffer_w - 1]
                     + oldptr[count + this->buffer_w + 1])
                    >> 2)
                   - newptr[count];

            newptr[count] = newh - (newh >> fluidity);
        }
    }
}

/*
void E_WaterBump::CalcWaterSludge(int npage, int fluidity)
{
  int newh;
  int count = this->buffer_w + 1;

  int *newptr = this->buffers[npage];
  int *oldptr = this->buffers[!npage];

  int x, y;

  for (y = (this->buffer_h-1)*this->buffer_w; count < y; count += 2)
  {
    for (x = count+this->buffer_w-2; count < x; count++)
    {
// This is the "sludge" method...
      newh = (oldptr[count]<<2)
           +  oldptr[count-1-this->buffer_w]
           +  oldptr[count+1-this->buffer_w]
           +  oldptr[count-1+this->buffer_w]
           +  oldptr[count+1+this->buffer_w]
           + ((oldptr[count-1]
           +   oldptr[count+1]
           +   oldptr[count-this->buffer_w]
           +   oldptr[count+this->buffer_w])<<1);

      newptr[count] = (newh-(newh>>6)) >> fluidity;
    }
  }
}
*/

int E_WaterBump::render(char[2][2][576],
                        int is_beat,
                        int* framebuffer,
                        int* fbout,
                        int w,
                        int h) {
    if (this->buffer_w != w || this->buffer_h != h) {
        free(this->buffers[0]);
        free(this->buffers[1]);
        this->buffers[0] = nullptr;
        this->buffers[1] = nullptr;
    }
    if (this->buffers[0] == nullptr) {
        this->buffers[0] = (int*)calloc(w * h, sizeof(int));
        this->buffers[1] = (int*)calloc(w * h, sizeof(int));
        this->buffer_w = w;
        this->buffer_h = h;
    }
    if (is_beat & 0x80000000) {
        return 0;
    }

    if (is_beat) {
        if (this->config.random) {
            int max = w;
            if (h > w) {
                max = h;
            }
            SineBlob(-1,
                     -1,
                     this->config.drop_radius * max / 100,
                     -this->config.depth,
                     this->page);
        } else {
            int x, y;
            switch (this->config.drop_position_x) {
                case 0: x = w / 4; break;
                case 1:
                default: x = w / 2; break;
                case 2: x = w * 3 / 4; break;
            }
            switch (this->config.drop_position_y) {
                case 0: y = h / 4; break;
                case 1:
                default: y = h / 2; break;
                case 2: y = h * 3 / 4; break;
            }
            SineBlob(x, y, this->config.drop_radius, -this->config.depth, this->page);
        }
        //	HeightBlob(-1,-1,80/2,1400,this->page);
    }

    int dx, dy;
    int x, y;
    int ofs, len = this->buffer_h * this->buffer_w;

    int offset = this->buffer_w + 1;

    int* ptr = this->buffers[this->page];

    for (y = (this->buffer_h - 1) * this->buffer_w; offset < y; offset += 2) {
        for (x = offset + this->buffer_w - 2; offset < x; offset++) {
            dx = ptr[offset] - ptr[offset + 1];
            dy = ptr[offset] - ptr[offset + this->buffer_w];
            ofs = offset + this->buffer_w * (dy >> 3) + (dx >> 3);
            if ((ofs < len) && (ofs > -1)) {
                fbout[offset] = framebuffer[ofs];
            } else {
                fbout[offset] = framebuffer[offset];
            }

            offset++;
            dx = ptr[offset] - ptr[offset + 1];
            dy = ptr[offset] - ptr[offset + this->buffer_w];
            ofs = offset + this->buffer_w * (dy >> 3) + (dx >> 3);
            if ((ofs < len) && (ofs > -1)) {
                fbout[offset] = framebuffer[ofs];
            } else {
                fbout[offset] = framebuffer[offset];
            }
        }
    }

    CalcWater(!this->page, this->config.fluidity);

    this->page = !this->page;

    return 1;
}

void E_WaterBump::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.fluidity = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.depth = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.random = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.drop_position_x = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.drop_position_y = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.drop_radius = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.method = GET_INT();
        pos += 4;
    }
}

int E_WaterBump::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->enabled);
    pos += 4;
    PUT_INT(this->config.fluidity);
    pos += 4;
    PUT_INT(this->config.depth);
    pos += 4;
    PUT_INT(this->config.random);
    pos += 4;
    PUT_INT(this->config.drop_position_x);
    pos += 4;
    PUT_INT(this->config.drop_position_y);
    pos += 4;
    PUT_INT(this->config.drop_radius);
    pos += 4;
    PUT_INT(this->config.method);
    pos += 4;
    return pos;
}

Effect_Info* create_WaterBump_Info() { return new WaterBump_Info(); }
Effect* create_WaterBump(AVS_Instance* avs) { return new E_WaterBump(avs); }
void set_WaterBump_desc(char* desc) { E_WaterBump::set_desc(desc); }
