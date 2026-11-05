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
#include "e_colorreduction.h"

#include "constants.h"

#include "../util.h"  // ssizeof32()

#include <immintrin.h>

constexpr Parameter ColorReduction_Info::parameters[];

void on_levels_change(Effect* component,
                      const Parameter*,
                      const std::vector<int64_t>&) {
    ((E_ColorReduction*)component)->bake_mask();
}

E_ColorReduction::E_ColorReduction(AVS_Instance* avs) : Configurable_Effect(avs) {
    this->bake_mask();
}
E_ColorReduction::~E_ColorReduction() {}

void E_ColorReduction::bake_mask() {
    // 0 -> 100000000
    // 1 -> 110000000
    // 2 -> 111000000
    // 3 -> 111100000
    // 4 -> 111110000
    // 5 -> 111111000
    // 6 -> 111111100
    // 7 -> 111111110
    this->mask = (0xFF << (7 - this->config.levels)) & 0xFF;
    // spread mask to other color channels & leave alpha as-is
    this->mask |= (this->mask << 16) | (this->mask << 8) | 0xFF000000;
}

void render_c(int32_t* framebuffer, int length, uint32_t mask) {
    for (int i = 0; i < length; i++) {
        framebuffer[i] &= mask;
    }
}

void render_simd(int32_t* framebuffer, int length, uint32_t mask) {
    __m128i mask4 = _mm_set1_epi32(mask);
    for (int i = 0; i < length; i += 4) {
        __m128i four_px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
        four_px = _mm_and_si128(four_px, mask4);
        _mm_store_si128((__m128i*)&framebuffer[i], four_px);
    }
}

int E_ColorReduction::render(char[2][2][576],
                             int is_beat,
                             int* framebuffer,
                             int*,
                             int w,
                             int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }
    // render_c(framebuffer, w * h, this->mask);
    render_simd(framebuffer, w * h, this->mask);
    return 0;
}

void E_ColorReduction::on_load() { this->bake_mask(); }

void E_ColorReduction::load_legacy(unsigned char* data, int len) {
    if (len - LEGACY_SAVE_PATH_LEN >= ssizeof32(uint32_t)) {
        this->config.levels = *(uint32_t*)&data[LEGACY_SAVE_PATH_LEN] - 1;
        this->bake_mask();
    } else {
        this->config.levels = COLRED_LEVELS_256;
    }
}

int E_ColorReduction::save_legacy(unsigned char* data) {
    memset(data, '\0', LEGACY_SAVE_PATH_LEN);
    *(uint32_t*)&data[LEGACY_SAVE_PATH_LEN] = (uint32_t)(this->config.levels + 1);
    return LEGACY_SAVE_PATH_LEN + sizeof(uint32_t);
}

Effect_Info* create_ColorReduction_Info() { return new ColorReduction_Info(); }
Effect* create_ColorReduction(AVS_Instance* avs) { return new E_ColorReduction(avs); }
void set_ColorReduction_desc(char* desc) { E_ColorReduction::set_desc(desc); }
