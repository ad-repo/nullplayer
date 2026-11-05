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
#include "e_grain.h"

#include "blend.h"

#include <stdlib.h>

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

constexpr Parameter Grain_Info::parameters[];

E_Grain::E_Grain(AVS_Instance* avs)
    : Configurable_Effect(avs), old_x(0), old_y(0), depth_buffer(NULL) {
    unsigned int x;
    for (x = 0; x < sizeof(this->randtab); x++) {
        this->randtab[x] = rand() & 255;
    }
    this->randtab_pos = rand() % sizeof(this->randtab);
}
E_Grain::~E_Grain() { free(this->depth_buffer); }

unsigned char inline E_Grain::fastrandbyte(void) {
    unsigned char r = this->randtab[this->randtab_pos];
    this->randtab_pos++;
    if (!(this->randtab_pos & 15)) {
        this->randtab_pos += rand() % 73;
    }
    if (this->randtab_pos >= 491) {
        this->randtab_pos -= 491;
    }
    return r;
}

void E_Grain::reinit(int w, int h) {
    int x;
    int y;
    unsigned char* p;
    free(this->depth_buffer);
    this->depth_buffer = (unsigned char*)malloc(w * h * 2);
    p = this->depth_buffer;
    if (p) {
        for (y = 0; y < h; y++) {
            for (x = 0; x < w; x++) {
                *p++ = (rand() % 255);
                *p++ = (rand() % 100);
            }
        }
    }
}

int E_Grain::render(char[2][2][576],
                    int is_beat,
                    int* framebuffer,
                    int*,
                    int w,
                    int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }

    int amount_scaled = (this->config.amount * 255) / 100;
    int l = w * h;

    if (w != this->old_x || h != this->old_y) {
        reinit(w, h);
        this->old_x = w;
        this->old_y = h;
    }
    this->randtab_pos += rand() % 300;
    if (this->randtab_pos >= 491) {
        this->randtab_pos -= 491;
    }

    auto p = (uint32_t*)framebuffer;
    uint8_t* q = this->depth_buffer;
    if (this->config.static_) {
        if (this->config.blend_mode == BLEND_SIMPLE_ADDITIVE) {
            while (l--) {
                if (*p) {
                    uint32_t c = 0;
                    if (q[1] < amount_scaled) {
                        int s = q[0];
                        int r = (((p[0] & 0xff0000) * s) >> 8);
                        if (r > 0xff0000) {
                            r = 0xff0000;
                        }
                        c |= r & 0xff0000;
                        r = (((p[0] & 0xff00) * s) >> 8);
                        if (r > 0xff00) {
                            r = 0xff00;
                        }
                        c |= r & 0xff00;
                        r = (((p[0] & 0xff) * s) >> 8);
                        if (r > 0xff) {
                            r = 0xff;
                        }
                        c |= r;
                    }
                    blend_add_1px(&c, p, p);
                }
                p++;
                q += 2;
            }
        } else if (this->config.blend_mode == BLEND_SIMPLE_5050) {
            while (l--) {
                if (*p) {
                    uint32_t c = 0;
                    if (q[1] < amount_scaled) {
                        int s = q[0];
                        int r = (((p[0] & 0xff0000) * s) >> 8);
                        if (r > 0xff0000) {
                            r = 0xff0000;
                        }
                        c |= r & 0xff0000;
                        r = (((p[0] & 0xff00) * s) >> 8);
                        if (r > 0xff00) {
                            r = 0xff00;
                        }
                        c |= r & 0xff00;
                        r = (((p[0] & 0xff) * s) >> 8);
                        if (r > 0xff) {
                            r = 0xff;
                        }
                        c |= r;
                    }
                    blend_5050_1px(&c, p, p);
                }
                p++;
                q += 2;
            }
        } else {  // BLEND_SIMPLE_REPLACE
            while (l--) {
                if (*p) {
                    uint32_t c = 0;
                    if (q[1] < amount_scaled) {
                        int s = q[0];
                        int r = (((p[0] & 0xff0000) * s) >> 8);
                        if (r > 0xff0000) {
                            r = 0xff0000;
                        }
                        c |= r & 0xff0000;
                        r = (((p[0] & 0xff00) * s) >> 8);
                        if (r > 0xff00) {
                            r = 0xff00;
                        }
                        c |= r & 0xff00;
                        r = (((p[0] & 0xff) * s) >> 8);
                        if (r > 0xff) {
                            r = 0xff;
                        }
                        c |= r;
                    }
                    blend_replace_1px(&c, p);
                }
                p++;
                q += 2;
            }
        }
    } else {  // !static
        if (this->config.blend_mode == BLEND_SIMPLE_ADDITIVE) {
            while (l--) {
                if (*p) {
                    uint32_t c = 0;
                    if (fastrandbyte() < amount_scaled) {
                        int s = fastrandbyte();
                        int r = (((p[0] & 0xff0000) * s) >> 8);
                        if (r > 0xff0000) {
                            r = 0xff0000;
                        }
                        c |= r & 0xff0000;
                        r = (((p[0] & 0xff00) * s) >> 8);
                        if (r > 0xff00) {
                            r = 0xff00;
                        }
                        c |= r & 0xff00;
                        r = (((p[0] & 0xff) * s) >> 8);
                        if (r > 0xff) {
                            r = 0xff;
                        }
                        c |= r;
                    }
                    blend_add_1px(&c, p, p);
                }
                p++;
                q += 2;
            }
        } else if (this->config.blend_mode == BLEND_SIMPLE_5050) {
            while (l--) {
                if (*p) {
                    uint32_t c = 0;
                    if (fastrandbyte() < amount_scaled) {
                        int s = fastrandbyte();
                        int r = (((p[0] & 0xff0000) * s) >> 8);
                        if (r > 0xff0000) {
                            r = 0xff0000;
                        }
                        c |= r & 0xff0000;
                        r = (((p[0] & 0xff00) * s) >> 8);
                        if (r > 0xff00) {
                            r = 0xff00;
                        }
                        c |= r & 0xff00;
                        r = (((p[0] & 0xff) * s) >> 8);
                        if (r > 0xff) {
                            r = 0xff;
                        }
                        c |= r;
                    }
                    blend_5050_1px(&c, p, p);
                }
                p++;
                q += 2;
            }
        } else {  // BLEND_SIMPLE_REPLACE
            while (l--) {
                if (*p) {
                    uint32_t c = 0;
                    if (fastrandbyte() < amount_scaled) {
                        int s = fastrandbyte();
                        int r = (((p[0] & 0xff0000) * s) >> 8);
                        if (r > 0xff0000) {
                            r = 0xff0000;
                        }
                        c |= r & 0xff0000;
                        r = (((p[0] & 0xff00) * s) >> 8);
                        if (r > 0xff00) {
                            r = 0xff00;
                        }
                        c |= r & 0xff00;
                        r = (((p[0] & 0xff) * s) >> 8);
                        if (r > 0xff) {
                            r = 0xff;
                        }
                        c |= r;
                    }
                    blend_replace_1px(&c, p);
                }
                p++;
                q += 2;
            }
        }
    }
    return 0;
}

void E_Grain::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = GET_INT();
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
        if (GET_INT() && this->config.blend_mode == 0) {
            this->config.blend_mode = BLEND_SIMPLE_5050;
        }
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.amount = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.static_ = GET_INT();
        pos += 4;
    }
}

int E_Grain::save_legacy(unsigned char* data) {
    int pos = 0;

    PUT_INT(this->enabled);
    pos += 4;
    uint32_t blend_additive = this->config.blend_mode == BLEND_SIMPLE_ADDITIVE;
    PUT_INT(blend_additive);
    pos += 4;
    uint32_t blend_5050 = this->config.blend_mode == BLEND_SIMPLE_5050;
    PUT_INT(blend_5050);
    pos += 4;
    PUT_INT(this->config.amount);
    pos += 4;
    PUT_INT(this->config.static_);
    pos += 4;
    return pos;
}

Effect_Info* create_Grain_Info() { return new Grain_Info(); }
Effect* create_Grain(AVS_Instance* avs) { return new E_Grain(avs); }
void set_Grain_desc(char* desc) { E_Grain::set_desc(desc); }
