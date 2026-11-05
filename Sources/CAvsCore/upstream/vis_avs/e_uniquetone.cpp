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
#include "e_uniquetone.h"

#include "blend.h"
#include "effect_common.h"

#include <stdlib.h>

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

constexpr Parameter UniqueTone_Info::parameters[];

void UniqueTone_Info::on_color_change(Effect* component,
                                      const Parameter*,
                                      const std::vector<int64_t>&) {
    ((E_UniqueTone*)component)->rebuild_table();
}

E_UniqueTone::E_UniqueTone(AVS_Instance* avs)
    : Configurable_Effect(avs), table_r{}, table_g{}, table_b{} {
    rebuild_table();
}

int __inline E_UniqueTone::depth_of(int c) {
    int r = max(max((c & 0xFF), ((c & 0xFF00) >> 8)), (c & 0xFF0000) >> 16);
    return this->config.invert ? 255 - r : r;
}

void E_UniqueTone::rebuild_table() {
    int i;
    for (i = 0; i < 256; i++) {
        this->table_b[i] =
            (unsigned char)((i / 255.0) * (float)(this->config.color & 0xFF));
    }
    for (i = 0; i < 256; i++) {
        this->table_g[i] =
            (unsigned char)((i / 255.0) * (float)((this->config.color & 0xFF00) >> 8));
    }
    for (i = 0; i < 256; i++) {
        this->table_r[i] =
            (unsigned char)((i / 255.0)
                            * (float)((this->config.color & 0xFF0000) >> 16));
    }
}

int E_UniqueTone::render(char[2][2][576],
                         int is_beat,
                         int* framebuffer,
                         int*,
                         int w,
                         int h) {
    int i = w * h;
    auto p = (uint32_t*)framebuffer;
    uint32_t c, d;

    if (is_beat & 0x80000000) {
        return 0;
    }

    if (this->config.blend_mode == BLEND_SIMPLE_ADDITIVE) {
        while (i--) {
            d = this->depth_of(*p);
            c = this->table_b[d] | (this->table_g[d] << 8) | (this->table_r[d] << 16);
            blend_add_1px(&c, p, p);
            ++p;
        }
    } else if (this->config.blend_mode == BLEND_SIMPLE_5050) {
        while (i--) {
            d = this->depth_of(*p);
            c = this->table_b[d] | (this->table_g[d] << 8) | (this->table_r[d] << 16);
            blend_5050_1px(&c, p, p);
            ++p;
        }
    } else {  // BLEND_SIMPLE_REPLACE
        while (i--) {
            d = this->depth_of(*p);
            *p++ =
                this->table_b[d] | (this->table_g[d] << 8) | (this->table_r[d] << 16);
        }
    }
    return 0;
}

void E_UniqueTone::on_load() { rebuild_table(); }

void E_UniqueTone::load_legacy(unsigned char* data, int len) {
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
        this->config.invert = GET_INT();
        pos += 4;
    }
    rebuild_table();
}

int E_UniqueTone::save_legacy(unsigned char* data) {
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
    PUT_INT(this->config.invert);
    pos += 4;
    return pos;
}

Effect_Info* create_UniqueTone_Info() { return new UniqueTone_Info(); }
Effect* create_UniqueTone(AVS_Instance* avs) { return new E_UniqueTone(avs); }
void set_UniqueTone_desc(char* desc) { E_UniqueTone::set_desc(desc); }
