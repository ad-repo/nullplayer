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
#include "e_mirror.h"

#include <chrono>
#include <cstdint>
#include <thread>

#define BLEND_DIVISOR_MAX 16

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;             \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

constexpr Parameter Mirror_Info::parameters[];

void Mirror_Info::on_mode_change(Effect* component,
                                 const Parameter* param,
                                 const std::vector<int64_t>&) {
    ((E_Mirror*)component)->on_mode_change(param);
}

void Mirror_Info::on_random_change(Effect* component,
                                   const Parameter*,
                                   const std::vector<int64_t>&) {
    ((E_Mirror*)component)->on_random_change();
}

E_Mirror::E_Mirror(AVS_Instance* avs)
    : Configurable_Effect(avs), transition_stepper(0) {
    this->cur_top_to_bottom = this->config.top_to_bottom * BLEND_DIVISOR_MAX;
    this->cur_bottom_to_top = this->config.bottom_to_top * BLEND_DIVISOR_MAX;
    this->cur_left_to_right = this->config.left_to_right * BLEND_DIVISOR_MAX;
    this->cur_right_to_left = this->config.right_to_left * BLEND_DIVISOR_MAX;
    this->target_top_to_bottom = this->config.top_to_bottom * BLEND_DIVISOR_MAX;
    this->target_bottom_to_top = this->config.bottom_to_top * BLEND_DIVISOR_MAX;
    this->target_left_to_right = this->config.left_to_right * BLEND_DIVISOR_MAX;
    this->target_right_to_left = this->config.right_to_left * BLEND_DIVISOR_MAX;
}

void E_Mirror::on_mode_change(const Parameter* param) {
    std::string param_name = param->name;
    if (this->config.on_beat_random || !this->get_bool(param->handle)) {
        return;
    }
    if (param_name == "Top to Bottom") {
        this->config.bottom_to_top = false;
    } else if (param_name == "Bottom to Top") {
        this->config.top_to_bottom = false;
    } else if (param_name == "Left to Right") {
        this->config.right_to_left = false;
    } else if (param_name == "Right to Left") {
        this->config.left_to_right = false;
    }
}

void E_Mirror::on_random_change() {
    if (this->config.on_beat_random) {
        return;
    }
    if (this->config.top_to_bottom && this->config.bottom_to_top) {
        this->config.bottom_to_top = false;
    }
    if (this->config.left_to_right && this->config.right_to_left) {
        this->config.right_to_left = false;
    }
}

/**
 * This method is a bit more complicated than it strictly needs to, in order to make the
 * probabilities evenly distributed. For each of the two orientations of the mirror do
 * the following: If *both* directions are enabled in the config, choose a random number
 * from [0, 1, 2] corresponding to no mirroring, mirroring in one direction, and in the
 * other. If only one direction is enabled in the config it becomes a binary choice
 * between that direction and none.
 */
void E_Mirror::random_mode() {
    // Pick a random number once in the beginning & use different parts of it.
    auto random = rand();
    if (this->config.top_to_bottom && this->config.bottom_to_top) {
        auto vertical = random % 3;
        this->target_top_to_bottom = (vertical == 2) ? BLEND_DIVISOR_MAX : 0;
        this->target_bottom_to_top = (vertical == 1) ? BLEND_DIVISOR_MAX : 0;
    } else if (this->config.top_to_bottom) {
        this->target_top_to_bottom = (random & 1) ? BLEND_DIVISOR_MAX : 0;
        this->target_bottom_to_top = 0;
    } else if (this->config.bottom_to_top) {
        this->target_bottom_to_top = (random & 1) ? BLEND_DIVISOR_MAX : 0;
        this->target_top_to_bottom = 0;
    } else {
        this->target_top_to_bottom = 0;
        this->target_bottom_to_top = 0;
    }
    if (this->config.left_to_right && this->config.right_to_left) {
        auto horizontal = (random >> 2) % 3;
        this->target_left_to_right = (horizontal == 2) ? BLEND_DIVISOR_MAX : 0;
        this->target_right_to_left = (horizontal == 1) ? BLEND_DIVISOR_MAX : 0;
    } else if (this->config.left_to_right) {
        this->target_left_to_right = (random & 1) ? BLEND_DIVISOR_MAX : 0;
        this->target_right_to_left = 0;
    } else if (this->config.right_to_left) {
        this->target_right_to_left = (random & 1) ? BLEND_DIVISOR_MAX : 0;
        this->target_left_to_right = 0;
    } else {
        this->target_left_to_right = 0;
        this->target_right_to_left = 0;
    }
}

static int inline BLEND_ADAPT(unsigned int a, unsigned int b, uint8_t divisor) {
    return (int)((((a >> 4) & 0x0F0F0F0F) * (16 - divisor)
                  + (((b >> 4) & 0x0F0F0F0F) * divisor)));
}

int E_Mirror::render(char[2][2][576],
                     int is_beat,
                     int* framebuffer,
                     int*,
                     int w,
                     int h) {
    int j;
    int* fbp;
    bool in_transition;

    if (is_beat & 0x80000000) {
        return 0;
    }

    int t = w * h;
    int halfw = w / 2;
    int halfh = h / 2;

    if (this->config.on_beat_random) {
        if (is_beat) {
            this->random_mode();
            if (this->config.transition_duration == 0) {
                this->cur_top_to_bottom = this->target_top_to_bottom;
                this->cur_bottom_to_top = this->target_bottom_to_top;
                this->cur_left_to_right = this->target_left_to_right;
                this->cur_right_to_left = this->target_right_to_left;
            }
        }
    } else {
        this->cur_top_to_bottom = this->target_top_to_bottom =
            this->config.top_to_bottom ? BLEND_DIVISOR_MAX : 0;
        this->cur_bottom_to_top = this->target_bottom_to_top =
            this->config.bottom_to_top ? BLEND_DIVISOR_MAX : 0;
        this->cur_left_to_right = this->target_left_to_right =
            this->config.left_to_right ? BLEND_DIVISOR_MAX : 0;
        this->cur_right_to_left = this->target_right_to_left =
            this->config.right_to_left ? BLEND_DIVISOR_MAX : 0;
    }

    if (this->config.transition_duration > 0) {
        if (this->cur_left_to_right) {
            in_transition = this->target_left_to_right != this->cur_left_to_right;
            fbp = framebuffer;
            if (in_transition) {
                for (int hi = 0; hi < h; hi++) {
                    int* tmp = fbp + w - 1;
                    int n = halfw;
                    while (n--) {
                        *tmp = BLEND_ADAPT(*tmp, *fbp++, this->cur_left_to_right);
                        --tmp;
                    }
                    fbp += halfw;
                }
            } else {
                for (int hi = 0; hi < h; hi++) {
                    int* tmp = fbp + w - 1;
                    int n = halfw;
                    while (n--) {
                        *tmp-- = *fbp++;
                    }
                    fbp += halfw;
                }
            }
        }

        if (this->cur_right_to_left) {
            fbp = framebuffer;
            in_transition = this->target_right_to_left != this->cur_right_to_left;
            if (in_transition) {
                for (int hi = 0; hi < h; hi++) {
                    int* tmp = fbp + w - 1;
                    int n = halfw;
                    while (n--) {
                        *fbp = BLEND_ADAPT(*fbp, *tmp--, this->cur_right_to_left);
                        ++fbp;
                    }
                    fbp += halfw;
                }
            } else {
                for (int hi = 0; hi < h; hi++) {
                    int* tmp = fbp + w - 1;
                    int n = halfw;
                    while (n--) {
                        *fbp++ = *tmp--;
                    }
                    fbp += halfw;
                }
            }
        }

        if (this->cur_top_to_bottom) {
            fbp = framebuffer;
            j = t - w;
            in_transition = this->target_top_to_bottom != this->cur_top_to_bottom;
            if (in_transition) {
                for (int hi = 0; hi < halfh; hi++) {
                    int n = w;
                    while (n--) {
                        fbp[j] = BLEND_ADAPT(fbp[j], *fbp, this->cur_top_to_bottom);
                        ++fbp;
                    }
                    j -= 2 * w;
                }
            } else {
                for (int hi = 0; hi < halfh; hi++) {
                    memcpy(fbp + j, fbp, w * sizeof(int));
                    fbp += w;
                    j -= 2 * w;
                }
            }
        }

        if (this->cur_bottom_to_top) {
            fbp = framebuffer;
            j = t - w;
            in_transition = this->target_bottom_to_top != this->cur_bottom_to_top;
            if (in_transition) {
                for (int hi = 0; hi < halfh; hi++) {
                    int n = w;
                    while (n--) {
                        *fbp = BLEND_ADAPT(*fbp, fbp[j], this->cur_bottom_to_top);
                        ++fbp;
                    }
                    j -= 2 * w;
                }
            } else {
                for (int hi = 0; hi < halfh; hi++) {
                    memcpy(fbp, fbp + j, w * sizeof(int));
                    fbp += w;
                    j -= 2 * w;
                }
            }
        }

    } else {  // transition_duration == 0
        if (this->cur_left_to_right) {
            fbp = framebuffer;
            for (int hi = 0; hi < h; hi++) {
                int* tmp = fbp + w - 1;
                int n = halfw;
                while (n--) {
                    *tmp-- = *fbp++;
                }
                fbp += halfw;
            }
        }

        if (this->cur_right_to_left) {
            fbp = framebuffer;
            for (int hi = 0; hi < h; hi++) {
                int* tmp = fbp + w - 1;
                int n = halfw;
                while (n--) {
                    *fbp++ = *tmp--;
                }
                fbp += halfw;
            }
        }

        if (this->cur_top_to_bottom) {
            fbp = framebuffer;
            j = t - w;
            for (int hi = 0; hi < halfh; hi++) {
                memcpy(fbp + j, fbp, w * sizeof(int));
                fbp += w;
                j -= 2 * w;
            }
        }

        if (this->cur_bottom_to_top) {
            fbp = framebuffer;
            j = t - w;
            for (int hi = 0; hi < halfh; hi++) {
                memcpy(fbp, fbp + j, w * sizeof(int));
                fbp += w;
                j -= 2 * w;
            }
        }
    }

    if (this->config.transition_duration > 0) {
        if (this->transition_stepper > 0) {
            this->transition_stepper--;
        } else {
            if (this->cur_top_to_bottom < this->target_top_to_bottom) {
                this->cur_top_to_bottom++;
            } else if (this->cur_top_to_bottom > this->target_top_to_bottom) {
                this->cur_top_to_bottom--;
            }
            if (this->cur_bottom_to_top < this->target_bottom_to_top) {
                this->cur_bottom_to_top++;
            } else if (this->cur_bottom_to_top > this->target_bottom_to_top) {
                this->cur_bottom_to_top--;
            }
            if (this->cur_left_to_right < this->target_left_to_right) {
                this->cur_left_to_right++;
            } else if (this->cur_left_to_right > this->target_left_to_right) {
                this->cur_left_to_right--;
            }
            if (this->cur_right_to_left < this->target_right_to_left) {
                this->cur_right_to_left++;
            } else if (this->cur_right_to_left > this->target_right_to_left) {
                this->cur_right_to_left--;
            }
            this->transition_stepper = this->config.transition_duration;
        }
    }
    return 0;
}

void E_Mirror::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        uint32_t mode = GET_INT();
        this->config.top_to_bottom = mode & 0b0001;
        this->config.bottom_to_top = mode & 0b0010;
        this->config.left_to_right = mode & 0b0100;
        this->config.right_to_left = mode & 0b1000;
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_random = GET_INT();
        pos += 4;
    }
    bool smooth_transition = false;
    this->config.transition_duration = 0;
    if (len - pos >= 4) {
        smooth_transition = GET_INT();
        if (smooth_transition) {
            this->config.transition_duration = 1;
        }
        pos += 4;
    }
    if (len - pos >= 4) {
        if (smooth_transition) {
            this->config.transition_duration = GET_INT();
        }
        pos += 4;
    }
}

static uint32_t mode_from_config(const Mirror_Config& config) {
    return config.top_to_bottom * 0b0001 | config.bottom_to_top * 0b0010
           | config.left_to_right * 0b0100 | config.right_to_left * 0b1000;
}

int E_Mirror::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->enabled);
    pos += 4;
    uint32_t mode = mode_from_config(this->config);
    PUT_INT(mode);
    pos += 4;
    PUT_INT(this->config.on_beat_random);
    pos += 4;
    bool smooth_transition = this->config.transition_duration != 0;
    PUT_INT(smooth_transition);
    pos += 4;
    int32_t legacy_transition_duration =
        max((int32_t)this->config.transition_duration, 1);
    PUT_INT(legacy_transition_duration);
    pos += 4;
    return pos;
}

Effect_Info* create_Mirror_Info() { return new Mirror_Info(); }
Effect* create_Mirror(AVS_Instance* avs) { return new E_Mirror(avs); }
void set_Mirror_desc(char* desc) { E_Mirror::set_desc(desc); }
