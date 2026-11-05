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

#include "e_videodelay.h"

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))
#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

constexpr Parameter VideoDelay_Info::parameters[];

void VideoDelay_Info::on_use_beats_change(Effect* component,
                                          const Parameter*,
                                          const std::vector<int64_t>&) {
    E_VideoDelay* delay = (E_VideoDelay*)component;
    if (delay->config.use_beats) {
        delay->frame_delay = 0;
        delay->frames_since_beat = 0;
    } else {
        delay->frame_delay = delay->config.delay;
    }
}

void VideoDelay_Info::on_delay_change(Effect* component,
                                      const Parameter*,
                                      const std::vector<int64_t>&) {
    E_VideoDelay* delay = (E_VideoDelay*)component;
    if (delay->config.use_beats) {
        delay->frame_delay = 0;
        if (delay->config.delay > 16) {
            delay->config.delay = 16;
        }
    } else {
        delay->frame_delay = delay->config.delay;
    }
}

E_VideoDelay::E_VideoDelay(AVS_Instance* avs)
    : Configurable_Effect(avs),
      buffersize(1),
      virtual_buffersize(1),
      old_virtual_buffersize(1),
      buffer(calloc(this->buffersize, 1)),
      in_out_pos(this->buffer),
      frames_since_beat(0),
      frame_delay(10),
      old_frame_mem(0) {}

E_VideoDelay::~E_VideoDelay() { free(this->buffer); }

int E_VideoDelay::render(char[2][2][576],
                         int is_beat,
                         int* framebuffer,
                         int* fbout,
                         int w,
                         int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }

    this->frame_mem = w * h * 4;
    if (this->config.use_beats) {
        if (is_beat) {
            this->frame_delay = this->frames_since_beat * this->config.delay;
            if (this->frame_delay > 400) {
                this->frame_delay = 400;
            }
            this->frames_since_beat = 0;
        }
        this->frames_since_beat++;
    }
    if (this->frame_delay == 0) {
        return 0;
    }
    this->virtual_buffersize = this->frame_delay * this->frame_mem;
    if (this->frame_mem == this->old_frame_mem) {
        if (this->virtual_buffersize != this->old_virtual_buffersize) {
            if (this->virtual_buffersize > this->old_virtual_buffersize) {
                if (this->virtual_buffersize > this->buffersize) {
                    free(this->buffer);
                    if (this->config.use_beats) {
                        this->buffersize = 2 * this->virtual_buffersize;
                        if (this->buffersize > this->frame_mem * 400) {
                            this->buffersize = this->frame_mem * 400;
                        }
                        this->buffer = calloc(this->buffersize, 1);
                        if (this->buffer == NULL) {
                            this->buffersize = this->virtual_buffersize;
                            this->buffer = calloc(this->buffersize, 1);
                        }
                    } else {
                        this->buffersize = this->virtual_buffersize;
                        this->buffer = calloc(this->buffersize, 1);
                    }
                    this->in_out_pos = this->buffer;
                    if (this->buffer == NULL) {
                        this->frame_delay = 0;
                        this->frames_since_beat = 0;
                        return 0;
                    }
                } else {
                    // NullPlayer: pointer arithmetic in uintptr_t (upstream: uint32_t, 32-bit only).
                    uint32_t size =
                        (((uintptr_t)this->buffer) + this->old_virtual_buffersize)
                        - ((uintptr_t)this->in_out_pos);
                    uintptr_t l = ((uintptr_t)this->buffer) + this->virtual_buffersize;
                    uintptr_t d = l - size;
                    memmove((void*)d, this->in_out_pos, size);
                    for (l = (uintptr_t)this->in_out_pos; l < d; l += this->frame_mem) {
                        memcpy((void*)l, (void*)d, this->frame_mem);
                    }
                }
            } else {  // this->virtual_buffersize < old_virtual_buffersize  NullPlayer: uintptr_t below
                uint32_t presegsize = ((uintptr_t)this->in_out_pos)
                                      - ((uintptr_t)this->buffer) + this->frame_mem;
                if (presegsize > this->virtual_buffersize) {
                    memmove(this->buffer,
                            (void*)(((uintptr_t)this->buffer) + presegsize
                                    - this->virtual_buffersize),
                            this->virtual_buffersize);
                    this->in_out_pos =
                        (void*)(((uintptr_t)this->buffer) + this->virtual_buffersize
                                - this->frame_mem);
                } else if (presegsize < this->virtual_buffersize) {
                    memmove(
                        (void*)(((uintptr_t)this->in_out_pos) + this->frame_mem),
                        (void*)(((uintptr_t)this->buffer) + this->old_virtual_buffersize
                                + presegsize - this->virtual_buffersize),
                        this->virtual_buffersize - presegsize);
                }
            }
            this->old_virtual_buffersize = this->virtual_buffersize;
        }
    } else {
        free(this->buffer);
        if (this->config.use_beats) {
            this->buffersize = 2 * this->virtual_buffersize;
            this->buffer = calloc(this->buffersize, 1);
            if (this->buffer == NULL) {
                this->buffersize = this->virtual_buffersize;
                this->buffer = calloc(this->buffersize, 1);
            }
        } else {
            this->buffersize = this->virtual_buffersize;
            this->buffer = calloc(this->buffersize, 1);
        }
        this->in_out_pos = this->buffer;
        if (this->buffer == NULL) {
            this->frame_delay = 0;
            this->frames_since_beat = 0;
            return 0;
        }
        this->old_virtual_buffersize = this->virtual_buffersize;
    }
    this->old_frame_mem = this->frame_mem;
    memcpy(fbout, this->in_out_pos, this->frame_mem);
    memcpy(this->in_out_pos, framebuffer, this->frame_mem);
    // NullPlayer: uintptr_t, as above.
    this->in_out_pos = (void*)(((uintptr_t)this->in_out_pos) + this->frame_mem);
    if ((uintptr_t)this->in_out_pos
        >= ((uintptr_t)this->buffer) + this->virtual_buffersize) {
        this->in_out_pos = this->buffer;
    }
    return 1;
}

void E_VideoDelay::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = (GET_INT() == 1);
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.use_beats = (GET_INT() == 1);
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.delay = GET_INT();
        if (this->config.use_beats) {
            if (this->config.delay > 16) {
                this->config.delay = 16;
            }
        } else {
            if (this->config.delay > 200) {
                this->config.delay = 200;
            }
        }

        pos += 4;
    }
}

int E_VideoDelay::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT((int)this->enabled);
    pos += 4;
    PUT_INT((int)this->config.use_beats);
    pos += 4;
    PUT_INT((unsigned int)this->config.delay);
    pos += 4;
    return pos;
}

Effect_Info* create_VideoDelay_Info() { return new VideoDelay_Info(); }
Effect* create_VideoDelay(AVS_Instance* avs) { return new E_VideoDelay(avs); }
void set_VideoDelay_desc(char* desc) { E_VideoDelay::set_desc(desc); }
