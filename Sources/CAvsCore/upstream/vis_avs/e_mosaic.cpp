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
#include "e_mosaic.h"

#include "blend.h"

#include <cstdlib>

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

constexpr Parameter Mosaic_Info::parameters[];

E_Mosaic::E_Mosaic(AVS_Instance* avs)
    : Configurable_Effect(avs),
      on_beat_cooldown(0),
      cur_size((int32_t)this->config.size) {}

int E_Mosaic::render(char[2][2][576],
                     int is_beat,
                     int* framebuffer,
                     int* fbout,
                     int w,
                     int h) {
    int rval = 0;

    if (is_beat & 0x80000000) {
        return 0;
    }

    if (this->config.on_beat_size_change && is_beat) {
        this->cur_size = (int32_t)this->config.on_beat_size;
        this->on_beat_cooldown = this->config.on_beat_duration;
    } else if (!this->on_beat_cooldown) {
        this->cur_size = (int32_t)this->config.size;
    }

    if (this->cur_size < 100) {
        int y;
        auto dest = (uint32_t*)fbout;
        auto src = (uint32_t*)framebuffer;
        uint32_t step_x = ((uint64_t)w << 16) / this->cur_size;
        uint32_t step_y = ((uint64_t)h << 16) / this->cur_size;
        uint32_t ypos = (step_y >> 17);
        uint32_t dypos = 0;

        for (y = 0; y < h; y++) {
            int x = w;
            auto fbread = (uint32_t*)framebuffer + ypos * w;
            uint32_t dpos = 0;
            int xpos = (step_x >> 17);

            if (this->config.blend_mode == BLEND_SIMPLE_ADDITIVE) {
                while (x--) {
                    blend_add_1px(&fbread[xpos], src++, dest++);
                    dpos += 1 << 16;
                    if (dpos >= step_x) {
                        xpos += dpos >> 16;
                        if (xpos >= w) {
                            break;
                        }
                        dpos -= step_x;
                    }
                }
            } else if (this->config.blend_mode == BLEND_SIMPLE_5050) {
                while (x--) {
                    blend_5050_1px(&fbread[xpos], src++, dest++);
                    dpos += 1 << 16;
                    if (dpos >= step_x) {
                        xpos += dpos >> 16;
                        if (xpos >= w) {
                            break;
                        }
                        dpos -= step_x;
                    }
                }
            } else {  // BLEND_SIMPLE_REPLACE
                while (x--) {
                    blend_replace_1px(&fbread[xpos], dest++);
                    dpos += 1 << 16;
                    if (dpos >= step_x) {
                        xpos += dpos >> 16;
                        if (xpos >= w) {
                            break;
                        }
                        dpos -= step_x;
                    }
                }
            }
            dypos += 1 << 16;
            if (dypos >= step_y) {
                ypos += (dypos >> 16);
                dypos -= step_y;
                if (ypos >= (uint32_t)h) {
                    break;
                }
            }
        }
        rval = 1;
    }

    if (this->on_beat_cooldown) {
        this->on_beat_cooldown--;
        if (this->on_beat_cooldown > 0) {
            int32_t a = abs(this->config.size - this->config.on_beat_size)
                        / this->config.on_beat_duration;
            this->cur_size +=
                a * (this->config.on_beat_size > this->config.size ? -1 : 1);
        }
    }

    return rval;
}

void E_Mosaic::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = GET_INT();
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
        this->config.on_beat_size_change = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_duration = GET_INT();
        pos += 4;
    }
}

int E_Mosaic::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->enabled);
    pos += 4;
    PUT_INT(this->config.size);
    pos += 4;
    PUT_INT(this->config.on_beat_size);
    pos += 4;
    int32_t blend_additive = this->config.blend_mode == BLEND_SIMPLE_ADDITIVE;
    PUT_INT(blend_additive);
    pos += 4;
    int32_t blend_5050 = this->config.blend_mode == BLEND_SIMPLE_5050;
    PUT_INT(blend_5050);
    pos += 4;
    PUT_INT(this->config.on_beat_size_change);
    pos += 4;
    PUT_INT(this->config.on_beat_duration);
    pos += 4;
    return pos;
}

Effect_Info* create_Mosaic_Info() { return new Mosaic_Info(); }
Effect* create_Mosaic(AVS_Instance* avs) { return new E_Mosaic(avs); }
void set_Mosaic_desc(char* desc) { E_Mosaic::set_desc(desc); }
