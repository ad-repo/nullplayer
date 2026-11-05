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
#include "e_interleave.h"

#include "blend.h"

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

constexpr Parameter Interleave_Info::parameters[];

void Interleave_Info::on_x_change(Effect* component,
                                  const Parameter* parameter,
                                  const std::vector<int64_t>&) {
    auto* interleave = (E_Interleave*)component;
    interleave->cur_x = (double)interleave->get_int(parameter->handle);
}

void Interleave_Info::on_y_change(Effect* component,
                                  const Parameter* parameter,
                                  const std::vector<int64_t>&) {
    auto* interleave = (E_Interleave*)component;
    interleave->cur_y = (double)interleave->get_int(parameter->handle);
}

void Interleave_Info::on_duration_change(Effect* component,
                                         const Parameter*,
                                         const std::vector<int64_t>&) {
    auto* interleave = (E_Interleave*)component;
    interleave->cur_x = (double)interleave->config.on_beat_x;
    interleave->cur_y = (double)interleave->config.on_beat_y;
}

E_Interleave::E_Interleave(AVS_Instance* avs)
    : Configurable_Effect(avs), cur_x(1.0), cur_y(1.0) {}

E_Interleave::~E_Interleave() = default;

int E_Interleave::render(char[2][2][576],
                         int is_beat,
                         int* framebuffer,
                         int*,
                         int w,
                         int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }

    double xy_lerp = ((double)this->config.on_beat_duration + 512.0 - 64.0) / 512.0;
    this->cur_x = (this->cur_x * xy_lerp + (double)this->config.x * (1.0 - xy_lerp));
    this->cur_y = (this->cur_y * xy_lerp + (double)this->config.y * (1.0 - xy_lerp));

    if (is_beat && this->config.on_beat) {
        this->cur_x = (double)this->config.on_beat_x;
        this->cur_y = (double)this->config.on_beat_y;
    }
    int stride_x = (int)this->cur_x;
    int stride_y = (int)this->cur_y;
    int right_edge_correction_x = 0;
    int bottom_edge_correction_y = 0;
    bool fill_x = true;
    bool fill_y = true;

    auto dest = (uint32_t*)framebuffer;
    uint32_t src = this->config.color & 0x00ffffff;
    if (!stride_y) {
        fill_y = false;
    }
    if (stride_x > 0) {
        right_edge_correction_x = (w % stride_x) / 2;
    }
    if (stride_y > 0) {
        bottom_edge_correction_y = (h % stride_y) / 2;
    }
    if (stride_x >= 0 && stride_y >= 0) {
        for (int y = 0; y < h; y++) {
            fill_x = true;
            if (stride_y && ++bottom_edge_correction_y >= stride_y) {
                fill_y = !fill_y;
                bottom_edge_correction_y = 0;
            }
            int x = w;

            if (fill_y) {
                switch (this->config.blend_mode) {
                    case BLEND_SIMPLE_ADDITIVE: blend_add_fill(src, dest, w); break;
                    case BLEND_SIMPLE_5050: blend_5050_fill(src, dest, w); break;
                    default:
                    case BLEND_SIMPLE_REPLACE: blend_replace_fill(src, dest, w); break;
                }
                dest += w;
            } else if (stride_x) {
                switch (this->config.blend_mode) {
                    case BLEND_SIMPLE_ADDITIVE: {
                        int edge_correction = right_edge_correction_x;
                        while (x > 0) {
                            int cur_stride_x = min(x, stride_x - edge_correction);
                            edge_correction = 0;
                            x -= cur_stride_x;
                            if (fill_x) {
                                blend_add_fill(src, dest, cur_stride_x);
                            }
                            dest += cur_stride_x;
                            fill_x = !fill_x;
                        }
                        break;
                    }
                    case BLEND_SIMPLE_5050: {
                        int edge_correction = right_edge_correction_x;
                        while (x > 0) {
                            int cur_stride_x = min(x, stride_x - edge_correction);
                            edge_correction = 0;
                            x -= cur_stride_x;
                            if (fill_x) {
                                blend_5050_fill(src, dest, cur_stride_x);
                            }
                            dest += cur_stride_x;
                            fill_x = !fill_x;
                        }
                        break;
                    }
                    default:
                    case BLEND_SIMPLE_REPLACE: {
                        int edge_correction = right_edge_correction_x;
                        while (x > 0) {
                            int cur_stride_x = min(x, stride_x - edge_correction);
                            edge_correction = 0;
                            x -= cur_stride_x;
                            if (fill_x) {
                                blend_replace_fill(src, dest, cur_stride_x);
                            }
                            dest += cur_stride_x;
                            fill_x = !fill_x;
                        }
                        break;
                    }
                }
            } else {
                dest += w;
            }
        }
    }
    return 0;
}

void E_Interleave::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.x = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.y = GET_INT();
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
        this->config.on_beat = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_x = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_y = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_duration = GET_INT();
        pos += 4;
    }
    this->cur_x = (double)this->config.x;
    this->cur_y = (double)this->config.y;
}

int E_Interleave::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->enabled);
    pos += 4;
    PUT_INT(this->config.x);
    pos += 4;
    PUT_INT(this->config.y);
    pos += 4;
    PUT_INT(this->config.color);
    pos += 4;
    bool blend_additive = this->config.blend_mode == BLEND_SIMPLE_ADDITIVE;
    PUT_INT(blend_additive);
    pos += 4;
    bool blend_5050 = this->config.blend_mode == BLEND_SIMPLE_5050;
    PUT_INT(blend_5050);
    pos += 4;
    PUT_INT(this->config.on_beat);
    pos += 4;
    PUT_INT(this->config.on_beat_x);
    pos += 4;
    PUT_INT(this->config.on_beat_y);
    pos += 4;
    PUT_INT(this->config.on_beat_duration);
    pos += 4;
    return pos;
}

Effect_Info* create_Interleave_Info() { return new Interleave_Info(); }
Effect* create_Interleave(AVS_Instance* avs) { return new E_Interleave(avs); }
void set_Interleave_desc(char* desc) { E_Interleave::set_desc(desc); }
