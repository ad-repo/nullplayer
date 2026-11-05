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
#include "e_colorfade.h"

constexpr Parameter Colorfade_Info::parameters[];

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;             \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

/**
 * When applying this effect the offsets from the faders are applied to the 3 color
 * channels in a specific order that depends on the relative brightness of the color
 * channels of a pixel between each other. This would need, for each pixel, 3
 * comparisons, which can be expensive. A lookup table created by using only two
 * subtractions is used instead.
 *
 * Create a lookup table like this:
 *
 *     2 2 2 0 6 6 9 5
 *     2 2 2 0 6 9 5 5
 *     2 2 2 0 9 5 5 5
 *     7 7 7 0 0 0 0 0
 *     1 1 0 8 3 3 3 3
 *     1 0 4 8 3 3 3 3
 *     0 4 4 8 3 3 3 3
 *     4 4 4 8 3 3 3 3
 *
 * This example is 8x8 for readability -- the actual table is 512x512. But imagine the
 * same values expanded outwards.
 *
 * The entries stand for one of 10 specific orderings of the color channels:
 *
 *     0: R = G = B
 *     1: R > G > B
 *     2: R > B > G
 *     3: G > B > R
 *     4: G > R > B
 *     5: B > G > R
 *     6: B > R > G
 *     7: R > G = B
 *     8: G > B = R
 *     9: B > R = G
 *
 * The layout of the table is specific to a certain index calculation, which is
 * performed once to pre-fill the table with the results, and again for every pixel of
 * every frame in the render function:
 *
 *     index = ((G - B) * 512) + B - R
 *               ‾‾▲‾‾           ‾‾▲‾‾
 *                row            column
 *
 * This way the table value at that index can quickly select one of the predefined
 * switched fader configurations and apply the configured offsets to each channel.
 */
void E_Colorfade::make_channel_fader_switch_tab() {
    int x, y;
    for (x = 0; x < 512; x++) {
        for (y = 0; y < 512; y++) {
            int xp = x - 255;
            int yp = y - 255;
            if (xp > 0 /* g-b > 0, or g > b */ && xp > -yp /* g-b > r-b, or g > r */) {
                // Green is brightest channel
                // Select fader switcher: 3->R 2->G 1->B
                this->channel_fader_switch_tab[x][y] = 0;
            } else if (yp < 0 /* b-r < 0 or r > b */
                       && xp < -yp /* g-b < r-b or g < r */) {
                // Red is brightest channel
                // Select fader switcher: 2->R 1->G 3->B
                this->channel_fader_switch_tab[x][y] = 1;
            } else if (xp < 0 /* g-b < 0 or b > g */ && yp > 0 /* b-r > 0 or b > r */) {
                // Blue is brightest channel
                // Select fader switcher: 1->R 3->G 2->B
                this->channel_fader_switch_tab[x][y] = 2;
            } else {
                // All channels the same, i.e. grayscale image
                // Select fader 3 for all channels (the switcher index "3" is
                // just coincidental here!)
                this->channel_fader_switch_tab[x][y] = 3;
            }
        }
    }
}

E_Colorfade::E_Colorfade(AVS_Instance* avs)
    : Configurable_Effect(avs),
      cur_max(this->config.fader_max),
      cur_2nd(this->config.fader_2nd),
      cur_3rd_gray(this->config.fader_3rd_gray) {
    this->make_channel_fader_switch_tab();
    // A small lookup table for clipped colors, similar to this shortened example:
    // 0 0 | 0 1 2 3 | 3 3
    for (int x = 0; x < 40 + 256 + 40; x++) {
        this->clip[x] = min(max(0, x - 40), 255);
    }
}

int E_Colorfade::render(char visdata[2][2][576],
                        int is_beat,
                        int* framebuffer,
                        int* fbout,
                        int w,
                        int h) {
    smp_begin(1, visdata, is_beat, framebuffer, fbout, w, h);
    if (is_beat & 0x80000000) {
        return 0;
    }

    smp_render(0, 1, visdata, is_beat, framebuffer, fbout, w, h);
    return smp_finish(visdata, is_beat, framebuffer, fbout, w, h);
}

int E_Colorfade::smp_begin(int max_threads,
                           char[2][2][576],
                           int is_beat,
                           int*,
                           int*,
                           int,
                           int) {
    if (is_beat & 0x80000000) {
        return 0;
    }

    if (this->cur_2nd < this->config.fader_2nd) {
        this->cur_2nd++;
    }
    if (this->cur_2nd > this->config.fader_2nd) {
        this->cur_2nd--;
    }
    if (this->config.version == COLORFADE_VERSION_V2_81D) {
        // This bug is a mixup in the 2nd and 3rd slider in normal operation:
        // The 3rd fader approaches the configured value for the 2nd and vice-versa.
        // Normally this would simply result in a UI switch between these two, but both
        // on preset load and on on-beat-change these values are set in their "correct"
        // order. The result is twofold:
        //   - The 2nd on-beat fader changes the 3rd normal fader value (and vice-versa)
        //   - Saving and loading the preset will result in a switched setting, but only
        //     for the first few seconds while the switched approach below is happening.
        if (this->cur_max < this->config.fader_3rd_gray) {
            this->cur_max++;
        }
        if (this->cur_max > this->config.fader_3rd_gray) {
            this->cur_max--;
        }
        if (this->cur_3rd_gray < this->config.fader_max) {
            this->cur_3rd_gray++;
        }
        if (this->cur_3rd_gray > this->config.fader_max) {
            this->cur_3rd_gray--;
        }
    } else {
        if (this->cur_max < this->config.fader_max) {
            this->cur_max++;
        }
        if (this->cur_max > this->config.fader_max) {
            this->cur_max--;
        }
        if (this->cur_3rd_gray < this->config.fader_3rd_gray) {
            this->cur_3rd_gray++;
        }
        if (this->cur_3rd_gray > this->config.fader_3rd_gray) {
            this->cur_3rd_gray--;
        }
    }
    if (!this->config.on_beat) {
        this->cur_2nd = this->config.fader_2nd;
        this->cur_max = this->config.fader_max;
        this->cur_3rd_gray = this->config.fader_3rd_gray;
    } else if (is_beat && this->config.on_beat_random) {
        this->cur_2nd = (rand() % 32) - 6;
        this->cur_max = (rand() % 64) - 32;
        if (this->cur_max < 0 && this->cur_max > -16) {
            this->cur_max = -32;
        }
        if (this->cur_max >= 0 && this->cur_max < 16) {
            this->cur_max = 32;
        }
        this->cur_3rd_gray = (rand() % 32) - 6;
    } else if (is_beat) {
        this->cur_2nd = this->config.on_beat_2nd;
        this->cur_max = this->config.on_beat_max;
        this->cur_3rd_gray = this->config.on_beat_3rd_gray;
    }

    this->fader_switch[0][0] = this->cur_3rd_gray;
    this->fader_switch[0][1] = this->cur_max;
    this->fader_switch[0][2] = this->cur_2nd;

    this->fader_switch[1][0] = this->cur_max;
    this->fader_switch[1][1] = this->cur_2nd;
    this->fader_switch[1][2] = this->cur_3rd_gray;

    this->fader_switch[2][0] = this->cur_2nd;
    this->fader_switch[2][1] = this->cur_3rd_gray;
    this->fader_switch[2][2] = this->cur_max;

    this->fader_switch[3][0] = this->cur_3rd_gray;
    this->fader_switch[3][1] = this->cur_3rd_gray;
    this->fader_switch[3][2] = this->cur_3rd_gray;

    return max_threads;
}

int E_Colorfade::smp_finish(char[2][2][576], int, int*, int*, int, int) { return 0; }

void E_Colorfade::smp_render(int this_thread,
                             int max_threads,
                             char[2][2][576],
                             int,
                             int* framebuffer,
                             int*,
                             int w,
                             int h) {
    if (max_threads < 1) {
        max_threads = 1;
    }

    int start_l = (this_thread * h) / max_threads;
    int end_l;

    if (this_thread >= max_threads - 1) {
        end_l = h;
    } else {
        end_l = ((this_thread + 1) * h) / max_threads;
    }

    int out_h = end_l - start_l;
    if (out_h < 1) {
        return;
    }

    auto* pixel = (unsigned char*)(framebuffer + start_l * w);

    unsigned char* channel_switch = &this->channel_fader_switch_tab[255][255];
    unsigned char* clip_0 = &this->clip[40];

    int x = w * out_h;
    bool odd_pixel_count = x & 1;
    for (; x > 0; x -= 2) {
        int r = pixel[0];
        int g = pixel[1];
        int b = pixel[2];
        int r2 = pixel[4];
        int g2 = pixel[5];
        int b2 = pixel[6];
        int i = ((g - b) << 9) + b - r;
        int i2 = ((g2 - b2) << 9) + b2 - r2;
        int switcher = channel_switch[i];
        int switcher2 = channel_switch[i2];

        pixel[0] = clip_0[r + this->fader_switch[switcher][0]];
        pixel[1] = clip_0[g + this->fader_switch[switcher][1]];
        pixel[2] = clip_0[b + this->fader_switch[switcher][2]];
        pixel[4] = clip_0[r2 + this->fader_switch[switcher2][0]];
        pixel[5] = clip_0[g2 + this->fader_switch[switcher2][1]];
        pixel[6] = clip_0[b2 + this->fader_switch[switcher2][2]];
        pixel += 8;
    }
    if (odd_pixel_count) {
        int r = pixel[0];
        int g = pixel[1];
        int b = pixel[2];
        int i = ((g - b) << 9) + b - r;
        int switcher = channel_switch[i];
        pixel[0] = clip_0[r + this->fader_switch[switcher][0]];
        pixel[1] = clip_0[g + this->fader_switch[switcher][1]];
        pixel[2] = clip_0[b + this->fader_switch[switcher][2]];
    }
}

void E_Colorfade::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        int32_t enabled_on_beat_random_version = GET_INT();
        this->enabled = enabled_on_beat_random_version & 0b0001;
        this->config.on_beat = enabled_on_beat_random_version & 0b0100;
        this->config.on_beat_random = enabled_on_beat_random_version & 0b0010;
        // Load the version for the fader fix from the high byte which is unused in the
        // legacy format. Just in case mask the sign bit, which shouldn't be set, but
        // you never know.
        this->config.version = enabled_on_beat_random_version >> 24 & 0x7f;
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.fader_2nd = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.fader_max = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.fader_3rd_gray = GET_INT();
        pos += 4;
    }
    this->config.on_beat_2nd = this->config.fader_2nd;
    this->config.on_beat_max = this->config.fader_max;
    this->config.on_beat_3rd_gray = this->config.fader_3rd_gray;
    if (len - pos >= 4) {
        this->config.on_beat_2nd = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_max = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_3rd_gray = GET_INT();
        pos += 4;
    }
    this->cur_2nd = this->config.fader_2nd;
    this->cur_max = this->config.fader_max;
    this->cur_3rd_gray = this->config.fader_3rd_gray;
}

int E_Colorfade::save_legacy(unsigned char* data) {
    int pos = 0;
    // Save the version for the fader fix to the high byte which is unused in the legacy
    // format. But mask the sign bit, so the number doesn't become negative and confuses
    // legacy AVS (if the version ever becomes > 127, which is highly unlikely).
    int32_t enabled_on_beat_random_version = (this->enabled * 0b0001)
                                             | (this->config.on_beat * 0b0100)
                                             | (this->config.on_beat_random * 0b0010)
                                             | ((this->config.version & 0x7f) << 24);
    PUT_INT(enabled_on_beat_random_version);
    pos += 4;
    PUT_INT(this->config.fader_2nd);
    pos += 4;
    PUT_INT(this->config.fader_max);
    pos += 4;
    PUT_INT(this->config.fader_3rd_gray);
    pos += 4;
    PUT_INT(this->config.on_beat_2nd);
    pos += 4;
    PUT_INT(this->config.on_beat_max);
    pos += 4;
    PUT_INT(this->config.on_beat_3rd_gray);
    pos += 4;
    return pos;
}

Effect_Info* create_Colorfade_Info() { return new Colorfade_Info(); }
Effect* create_Colorfade(AVS_Instance* avs) { return new E_Colorfade(avs); }
void set_Colorfade_desc(char* desc) { E_Colorfade::set_desc(desc); }
