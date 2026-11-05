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
// video delay
// copyright tom holden, 2002
// mail: cfp@myrealbox.com

#include "e_multidelay.h"

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))
#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

constexpr Parameter MultiDelay_Info::buffer_parameters[];
constexpr Parameter MultiDelay_Info::parameters[];

void MultiDelay_Info::on_delay(Effect* component,
                               const Parameter*,
                               const std::vector<int64_t>& parameter_path) {
    ((E_MultiDelay*)component)->set_frame_delay(parameter_path[0]);
}

void E_MultiDelay::set_frame_delay(int64_t buffer_index) {
    auto& buffer = this->global->config.buffers[buffer_index];
    buffer.frame_delay =
        (buffer.use_beats ? this->global->config.frames_per_beat : buffer.delay) + 1;
}

E_MultiDelay::E_MultiDelay(AVS_Instance* avs)
    : Configurable_Effect(avs), is_first_instance(this->global->instances.size() == 1) {
    this->enabled = false;
}

int E_MultiDelay::render(char[2][2][576],
                         int is_beat,
                         int* framebuffer,
                         int*,
                         int w,
                         int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }

    auto& g = this->global->config;
    if (g.render_id == this->global->instances.size()) {
        g.render_id = 0;
    }
    g.render_id++;
    if (g.render_id == 1) {
        this->manage_buffers(is_beat, w * h);
    }
    auto& active = g.buffers[this->config.active_buffer];
    if (this->enabled && active.frame_delay > 1) {
        if (this->config.mode == MULTIDELAY_MODE_OUTPUT) {
            memcpy(framebuffer, active.out_pos, g.frame_mem_size);
        } else {
            memcpy(active.in_pos, framebuffer, g.frame_mem_size);
        }
    }
    if (g.render_id == this->global->instances.size()) {
        // NullPlayer: pointer arithmetic in uintptr_t (upstream: uint32_t, 32-bit only).
        for (int i = 0; i < MULTIDELAY_NUM_BUFFERS; i++) {
            auto& b = g.buffers[i];
            b.in_pos = (void*)(((uintptr_t)b.in_pos) + g.frame_mem_size);
            b.out_pos = (void*)(((uintptr_t)b.out_pos) + g.frame_mem_size);
            if ((uintptr_t)b.in_pos >= ((uintptr_t)b.buffer) + b.virtual_size) {
                b.in_pos = b.buffer;
            }
            if ((uintptr_t)b.out_pos >= ((uintptr_t)b.buffer) + b.virtual_size) {
                b.out_pos = b.buffer;
            }
        }
    }
    return 0;
}

inline void E_MultiDelay::manage_buffers(bool is_beat, int64_t frame_size) {
    auto& g = this->global->config;
    g.frame_mem_size = frame_size * 4;
    if (is_beat) {
        g.frames_per_beat = g.frames_since_beat;
        for (int i = 0; i < MULTIDELAY_NUM_BUFFERS; i++) {
            if (g.buffers[i].use_beats) {
                g.buffers[i].frame_delay = g.frames_per_beat + 1;
            }
        }
        g.frames_since_beat = 0;
    }
    g.frames_since_beat++;
    for (int i = 0; i < MULTIDELAY_NUM_BUFFERS; i++) {
        auto& b = g.buffers[i];
        if (b.frame_delay > 1) {
            b.virtual_size = b.frame_delay * g.frame_mem_size;
            if (g.frame_mem_size == g.old_frame_mem_size) {
                // frame size hasn't changed
                if (b.virtual_size != b.old_virtual_size) {
                    // *only* delay value changed, we can reuse individual image buffers
                    if (b.virtual_size > b.old_virtual_size) {
                        // delay has increased: increase ring buffer
                        if (b.virtual_size > b.size) {
                            // needed ring buffer size exceeds actual buffer size
                            // re-alloc to twice the needed size
                            free(b.buffer);
                            if (b.use_beats) {
                                b.size = 2 * b.virtual_size;
                                b.buffer = calloc(b.size, 1);
                                if (b.buffer == NULL) {
                                    b.size = b.virtual_size;
                                    b.buffer = calloc(b.size, 1);
                                }
                            } else {
                                b.size = b.virtual_size;
                                b.buffer = calloc(b.size, 1);
                            }
                            b.out_pos = b.buffer;
                            b.in_pos = (void*)((uintptr_t)b.buffer + b.virtual_size
                                               - g.frame_mem_size);
                            if (b.buffer == NULL) {
                                b.frame_delay = 0;
                                if (b.use_beats) {
                                    g.frames_per_beat = 0;
                                    g.frames_since_beat = 0;
                                    b.frame_delay = 0;
                                    b.delay = 0;
                                }
                            }
                        } else {
                            // needed buffer size is still within actual buffer size
                            uint32_t size = (uintptr_t)b.buffer + b.old_virtual_size
                                            - (uintptr_t)b.out_pos;
                            uintptr_t l = (uintptr_t)b.buffer + b.virtual_size;
                            uintptr_t d = l - size;
                            memmove((void*)d, b.out_pos, size);
                            for (l = (uintptr_t)b.out_pos; l < d;
                                 l += g.frame_mem_size) {
                                memcpy((void*)l, (void*)d, g.frame_mem_size);
                            }
                        }
                    } else {
                        // delay has decreased: reduce ring buffer virtual size
                        uint32_t pre_seg_size =
                            ((uintptr_t)b.out_pos) - ((uintptr_t)b.buffer);
                        if (pre_seg_size > b.virtual_size) {
                            memmove(b.buffer,
                                    (void*)(((uintptr_t)b.buffer) + pre_seg_size
                                            - b.virtual_size),
                                    b.virtual_size);
                            b.in_pos = (void*)(((uintptr_t)b.buffer) + b.virtual_size
                                               - g.frame_mem_size);
                            b.out_pos = b.buffer;
                        } else if (pre_seg_size < b.virtual_size) {
                            memmove(b.out_pos,
                                    (void*)(((uintptr_t)b.buffer) + b.old_virtual_size
                                            + pre_seg_size - b.virtual_size),
                                    b.virtual_size - pre_seg_size);
                        }
                    }
                    b.old_virtual_size = b.virtual_size;
                }
            } else {
                // frame size changed, discard buffers
                free(b.buffer);
                if (b.use_beats) {
                    b.size = 2 * b.virtual_size;
                    b.buffer = calloc(b.size, 1);
                    if (b.buffer == NULL) {
                        b.size = b.virtual_size;
                        b.buffer = calloc(b.size, 1);
                    }
                } else {
                    b.size = b.virtual_size;
                    b.buffer = calloc(b.size, 1);
                }
                b.out_pos = b.buffer;
                b.in_pos =
                    (void*)(((uintptr_t)b.buffer) + b.virtual_size - g.frame_mem_size);
                if (b.buffer == NULL) {
                    b.frame_delay = 0;
                    if (b.use_beats) {
                        g.frames_per_beat = 0;
                        g.frames_since_beat = 0;
                        b.frame_delay = 0;
                        b.delay = 0;
                    }
                }
                b.old_virtual_size = b.virtual_size;
            }
        }
    }
    g.old_frame_mem_size = g.frame_mem_size;
}

void E_MultiDelay::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = true;
        uint32_t mode = GET_INT();
        switch (mode) {
            default:
            case 0: this->enabled = false; break;
            case 1: this->config.mode = MULTIDELAY_MODE_INPUT; break;
            case 2: this->config.mode = MULTIDELAY_MODE_OUTPUT; break;
        }
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.active_buffer = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        for (int i = 0; i < MULTIDELAY_NUM_BUFFERS; i++) {
            if (len - pos >= 4) {
                this->global->config.buffers[i].use_beats = (GET_INT() == 1);
                pos += 4;
            }
            if (len - pos >= 4) {
                this->global->config.buffers[i].delay = GET_INT();
                this->global->config.buffers[i].frame_delay =
                    (this->global->config.buffers[i].use_beats
                         ? this->global->config.frames_per_beat
                         : this->global->config.buffers[i].delay)
                    + 1;
                pos += 4;
            }
        }
    }
}

int E_MultiDelay::save_legacy(unsigned char* data) {
    int pos = 0;
    if (!this->enabled) {
        *(uint32_t*)data = 0;
    } else {
        switch (this->config.mode) {
            default:
            case MULTIDELAY_MODE_INPUT: *(uint32_t*)data = 1; break;
            case MULTIDELAY_MODE_OUTPUT: *(uint32_t*)data = 2; break;
        }
    }
    pos += 4;
    PUT_INT(this->config.active_buffer);
    pos += 4;
    if (this->is_first_instance) {
        for (int i = 0; i < MULTIDELAY_NUM_BUFFERS; i++) {
            PUT_INT((int)this->global->config.buffers[i].use_beats);
            pos += 4;
            PUT_INT(this->global->config.buffers[i].delay);
            pos += 4;
        }
    }
    return pos;
}

Effect_Info* create_MultiDelay_Info() { return new MultiDelay_Info(); }
Effect* create_MultiDelay(AVS_Instance* avs) { return new E_MultiDelay(avs); }
void set_MultiDelay_desc(char* desc) { E_MultiDelay::set_desc(desc); }
