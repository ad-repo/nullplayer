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
#include "e_setrendermode.h"

int g_line_blend_mode;

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter SetRenderMode_Info::parameters[];

uint32_t E_SetRenderMode::pack_mode() {
    return (this->enabled ? 0x80000000 : 0) | uint32_t(this->config.blend & 0xff)
           | uint32_t(max(0, min(255, this->config.adjustable_blend)) << 8)
           | uint32_t(max(0, min(255, this->config.line_size)) << 16);
}

int E_SetRenderMode::render(char[2][2][576], int is_beat, int*, int*, int, int) {
    if (is_beat & 0x80000000) {
        return 0;
    }
    if (this->enabled) {
        g_line_blend_mode = int32_t(this->pack_mode() & 0x7fffffff);
    }
    return 0;
}

void E_SetRenderMode::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        uint32_t mode = GET_INT();
        this->enabled = mode >> 31;
        this->config.blend = mode & 0xff;
        this->config.adjustable_blend = (mode >> 8) & 0xff;
        this->config.line_size = (mode >> 16) & 0xff;
        pos += 4;
    }
}
int E_SetRenderMode::save_legacy(unsigned char* data) {
    int pos = 0;
    uint32_t mode = this->pack_mode();
    PUT_INT(mode);
    pos += 4;
    return pos;
}

Effect_Info* create_SetRenderMode_Info() { return new SetRenderMode_Info(); }
Effect* create_SetRenderMode(AVS_Instance* avs) { return new E_SetRenderMode(avs); }
void set_SetRenderMode_desc(char* desc) { E_SetRenderMode::set_desc(desc); }
