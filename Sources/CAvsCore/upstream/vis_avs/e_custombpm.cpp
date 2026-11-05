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
#include "e_custombpm.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define SLIDER_CTRL_IN  1
#define SLIDER_CTRL_OUT 2

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

constexpr Parameter CustomBPM_Info::parameters[];

E_CustomBPM::E_CustomBPM(AVS_Instance* avs)
    : Configurable_Effect(avs), fixed_bpm_last_time(timer_ms()) {}

int E_CustomBPM::render(char[2][2][576], int is_beat, int*, int*, int, int) {
    if (is_beat & 0x80000000) {
        return 0;
    }

    if (is_beat) {
        this->config.beat_count_in += 1;
    }

    if (this->config.skip_first_beats
        && this->config.beat_count_in <= this->config.skip_first_beats) {
        return is_beat ? CLR_BEAT : 0;
    }

    switch (this->config.mode) {
        case CUSTOM_BPM_FIXED: {
            uint64_t now = timer_ms();
            auto beat_freq_ms = 60'000 / this->config.fixed_bpm;
            if (now > this->fixed_bpm_last_time + beat_freq_ms) {
                // Check if FIXED mode was disabled for a while.
                if (this->fixed_bpm_last_time < (now - beat_freq_ms * 2)) {
                    this->fixed_bpm_last_time = now;
                } else {
                    this->fixed_bpm_last_time += beat_freq_ms;
                }
                this->config.beat_count_out += 1;
                return SET_BEAT;
            }
            return CLR_BEAT;
        }

        case CUSTOM_BPM_SKIP: {
            if (is_beat) {
                this->skip_count++;
                if (this->skip_count > this->config.skip) {
                    this->skip_count = 0;
                    this->config.beat_count_out += 1;
                    return SET_BEAT;
                }
            }
            return CLR_BEAT;
        }

        case CUSTOM_BPM_INVERT: {
            if (is_beat) {
                return CLR_BEAT;
            } else {
                this->config.beat_count_out += 1;
                return SET_BEAT;
            }
        }
    }
    return 0;
}

void E_CustomBPM::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        if (GET_INT()) {
            this->config.mode = CUSTOM_BPM_FIXED;
        }
        pos += 4;
    }
    if (len - pos >= 4) {
        if (GET_INT()) {
            this->config.mode = CUSTOM_BPM_SKIP;
        }
        pos += 4;
    }
    if (len - pos >= 4) {
        if (GET_INT()) {
            this->config.mode = CUSTOM_BPM_INVERT;
        }
        pos += 4;
    }
    if (len - pos >= 4) {
        // The legacy version & format operated solely the time between beats in ms.
        this->config.fixed_bpm = 60'000 / GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.skip = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.skip_first_beats = GET_INT();
        pos += 4;
    }
}

int E_CustomBPM::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->enabled);
    pos += 4;
    auto mode_fixed = this->config.mode == CUSTOM_BPM_FIXED;
    PUT_INT(mode_fixed);
    pos += 4;
    auto mode_skip = this->config.mode == CUSTOM_BPM_SKIP;
    PUT_INT(mode_skip);
    pos += 4;
    auto mode_invert = this->config.mode == CUSTOM_BPM_INVERT;
    PUT_INT(mode_invert);
    pos += 4;
    PUT_INT(60'000 / this->config.fixed_bpm);
    pos += 4;
    PUT_INT(this->config.skip);
    pos += 4;
    PUT_INT(this->config.skip_first_beats);
    pos += 4;
    return pos;
}

Effect_Info* create_CustomBPM_Info() { return new CustomBPM_Info(); }
Effect* create_CustomBPM(AVS_Instance* avs) { return new E_CustomBPM(avs); }
void set_CustomBPM_desc(char* desc) { E_CustomBPM::set_desc(desc); }
