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
#include "e_colorclip.h"

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter ColorClip_Info::parameters[];

void ColorClip_Info::copy_in_to_out(Effect* component,
                                    const Parameter*,
                                    const std::vector<int64_t>&) {
    auto colorclip = (E_ColorClip*)component;
    colorclip->copy_in_to_out();
}

void E_ColorClip::copy_in_to_out() { this->config.color_out = this->config.color_in; }

int E_ColorClip::render(char[2][2][576],
                        int is_beat,
                        int* framebuffer,
                        int*,
                        int w,
                        int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }

    int* fb = framebuffer;
    int32_t pixel_counter = w * h;
    int32_t l = (int32_t)this->config.distance * 2;

    l = l * l;

    int32_t fs_b = (this->config.color_in & 0xff0000);
    int32_t fs_g = (this->config.color_in & 0xff00);
    int32_t fs_r = (this->config.color_in & 0xff);

    if (this->config.mode == COLORCLIP_BELOW) {
        while (pixel_counter--) {
            int a = fb[0];
            if ((a & 0xff) <= fs_r && (a & 0xff00) <= fs_g && (a & 0xff0000) <= fs_b) {
                fb[0] = (a & 0xff000000) | this->config.color_out;
            }
            fb++;
        }
    } else if (this->config.mode == COLORCLIP_ABOVE) {
        while (pixel_counter--) {
            int a = fb[0];
            if ((a & 0xff) >= fs_r && (a & 0xff00) >= fs_g && (a & 0xff0000) >= fs_b) {
                fb[0] = (a & 0xff000000) | this->config.color_out;
            }
            fb++;
        }
    } else {  // COLORCLIP_NEAR
        fs_b >>= 16;
        fs_g >>= 8;
        while (pixel_counter--) {
            int a = fb[0];
            int r = a & 255;
            int g = (a >> 8) & 255;
            int b = (a >> 16) & 255;
            r -= fs_r;
            g -= fs_g;
            b -= fs_b;
            if (r * r + g * g + b * b <= l) {
                fb[0] = (a & 0xff000000) | this->config.color_out;
            }
            fb++;
        }
    }
    return 0;
}

void E_ColorClip::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        int32_t mode = GET_INT();
        switch (mode) {
            case 0:
                this->enabled = false;
                this->config.mode = COLORCLIP_NEAR;
                break;
            case 1:
                this->enabled = true;
                this->config.mode = COLORCLIP_BELOW;
                break;
            case 2:
                this->enabled = true;
                this->config.mode = COLORCLIP_ABOVE;
                break;
            default:
            case 3:
                this->enabled = true;
                this->config.mode = COLORCLIP_NEAR;
                break;
        }
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.color_in = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.color_out = GET_INT();
        pos += 4;
    } else {
        this->config.color_out = this->config.color_in;
    }
    if (len - pos >= 4) {
        this->config.distance = GET_INT();
        pos += 4;
    }
}

int E_ColorClip::save_legacy(unsigned char* data) {
    int pos = 0;
    int32_t mode = this->enabled ? 0 : int32_t(this->config.mode + 1);
    PUT_INT(mode);
    pos += 4;
    PUT_INT(this->config.color_in);
    pos += 4;
    PUT_INT(this->config.color_out);
    pos += 4;
    PUT_INT(this->config.distance);
    pos += 4;
    return pos;
}

Effect_Info* create_ColorClip_Info() { return new ColorClip_Info(); }
Effect* create_ColorClip(AVS_Instance* avs) { return new E_ColorClip(avs); }
void set_ColorClip_desc(char* desc) { E_ColorClip::set_desc(desc); }
