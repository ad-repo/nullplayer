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
#include "e_scatter.h"

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255
#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

void E_Scatter::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = GET_INT();
        pos += 4;
    }
}
int E_Scatter::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->enabled);
    pos += 4;
    return pos;
}

E_Scatter::E_Scatter(AVS_Instance* avs) : Configurable_Effect(avs), ftw(0) {}
E_Scatter::~E_Scatter() {}

int E_Scatter::render(char[2][2][576],
                      int is_beat,
                      int* framebuffer,
                      int* fbout,
                      int w,
                      int h) {
    int l;
    if (ftw != w) {
        int x;
        for (x = 0; x < 512; x++) {
            int yp;
            int xp;
            xp = (x % 8) - 4;
            yp = (x / 8) % 8 - 4;
            if (xp < 0) {
                xp++;
            }
            if (yp < 0) {
                yp++;
            }
            fudgetable[x] = w * yp + xp;
        }
        ftw = w;
    }
    if (is_beat & 0x80000000) {
        return 0;
    }

    l = w * 4;
    while (l-- > 0) {
        *fbout++ = *framebuffer++;
    }
    l = w * (h - 8);
    while (l-- > 0) {
        *fbout++ = framebuffer[fudgetable[rand() & 511]];
        framebuffer++;
    }
    l = w * 4;
    while (l-- > 0) {
        *fbout++ = *framebuffer++;
    }

    return 1;
}

Effect_Info* create_Scatter_Info() { return new Scatter_Info(); }
Effect* create_Scatter(AVS_Instance* avs) { return new E_Scatter(avs); }
void set_Scatter_desc(char* desc) { E_Scatter::set_desc(desc); }
