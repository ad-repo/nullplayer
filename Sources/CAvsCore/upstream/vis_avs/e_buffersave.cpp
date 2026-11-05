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
#include "e_buffersave.h"

#include "blend.h"
#include "instance.h"

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter BufferSave_Info::parameters[];

void BufferSave_Info::clear_buffer(Effect* component,
                                   const Parameter*,
                                   const std::vector<int64_t>&) {
    ((E_BufferSave*)component)->clear_buffer();
}

void BufferSave_Info::nudge_parity(Effect* component,
                                   const Parameter*,
                                   const std::vector<int64_t>&) {
    ((E_BufferSave*)component)->nudge_parity();
}

E_BufferSave::E_BufferSave(AVS_Instance* avs)
    : Configurable_Effect(avs), save_restore_toggle(false), need_clear(false) {}

void E_BufferSave::clear_buffer() { this->need_clear = true; }
void E_BufferSave::nudge_parity() {
    this->save_restore_toggle = !this->save_restore_toggle;
}

int E_BufferSave::render(char[2][2][576],
                         int is_beat,
                         int* framebuffer,
                         int*,
                         int w,
                         int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }

    void* buffer_ref =
        this->avs->get_buffer(w,
                              h,
                              (int32_t)this->config.buffer - 1,
                              this->config.action != BUFFER_ACTION_RESTORE);
    if (!buffer_ref) {
        return 0;
    }

    if (this->need_clear) {
        this->need_clear = false;
        memset(buffer_ref, 0, sizeof(int) * w * h);
    }

    int64_t frame_action = BUFFER_ACTION_SAVE;
    switch (this->config.action) {
        default:
        case BUFFER_ACTION_SAVE:
        case BUFFER_ACTION_RESTORE: frame_action = this->config.action; break;
        case BUFFER_ACTION_SAVE_RESTORE:
            frame_action =
                this->save_restore_toggle ? BUFFER_ACTION_RESTORE : BUFFER_ACTION_SAVE;
            break;
        case BUFFER_ACTION_RESTORE_SAVE:
            frame_action =
                this->save_restore_toggle ? BUFFER_ACTION_SAVE : BUFFER_ACTION_RESTORE;
            break;
    }
    this->save_restore_toggle = !this->save_restore_toggle;
    uint32_t* fbin =
        (uint32_t*)(frame_action == BUFFER_ACTION_SAVE ? framebuffer : buffer_ref);
    uint32_t* fbout =
        (uint32_t*)(frame_action == BUFFER_ACTION_RESTORE ? framebuffer : buffer_ref);
    switch (this->config.blend_mode) {
        default: [[fallthrough]];
        case BUFFER_BLEND_REPLACE: blend_replace(fbin, fbout, w, h); break;
        case BUFFER_BLEND_ADDITIVE: blend_add(fbin, fbout, fbout, w, h); break;
        case BUFFER_BLEND_MAXIMUM: blend_maximum(fbin, fbout, fbout, w, h); break;
        case BUFFER_BLEND_5050: blend_5050(fbin, fbout, fbout, w, h); break;
        case BUFFER_BLEND_SUB1:
            blend_sub_src1_from_src2(fbin, fbout, fbout, w, h);
            break;
        case BUFFER_BLEND_SUB2:
            blend_sub_src2_from_src1(fbin, fbout, fbout, w, h);
            break;
        case BUFFER_BLEND_MULTIPLY: blend_multiply(fbin, fbout, fbout, w, h); break;
        case BUFFER_BLEND_ADJUSTABLE:
            blend_adjustable(fbin, fbout, fbout, this->config.adjustable_blend, w, h);
            break;
        case BUFFER_BLEND_XOR: blend_xor(fbin, fbout, fbout, w, h); break;
        case BUFFER_BLEND_MINIMUM: blend_minimum(fbin, fbout, fbout, w, h); break;
        case BUFFER_BLEND_EVERY_OTHER_PIXEL:
            blend_every_other_pixel(fbin, fbout, w, h);
            break;
        case BUFFER_BLEND_EVERY_OTHER_LINE:
            blend_every_other_line(fbin, fbout, w, h);
            break;
    }
    return 0;
}

void E_BufferSave::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->config.action = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.buffer = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        uint32_t blend = GET_INT();
        switch (blend) {
            default:
            case 0: this->config.blend_mode = BUFFER_BLEND_REPLACE; break;
            case 2: this->config.blend_mode = BUFFER_BLEND_ADDITIVE; break;
            case 7: this->config.blend_mode = BUFFER_BLEND_MAXIMUM; break;
            case 1: this->config.blend_mode = BUFFER_BLEND_5050; break;
            case 4: this->config.blend_mode = BUFFER_BLEND_SUB1; break;
            case 9: this->config.blend_mode = BUFFER_BLEND_SUB2; break;
            case 10: this->config.blend_mode = BUFFER_BLEND_MULTIPLY; break;
            case 11: this->config.blend_mode = BUFFER_BLEND_ADJUSTABLE; break;
            case 6: this->config.blend_mode = BUFFER_BLEND_XOR; break;
            case 8: this->config.blend_mode = BUFFER_BLEND_MINIMUM; break;
            case 3: this->config.blend_mode = BUFFER_BLEND_EVERY_OTHER_PIXEL; break;
            case 5: this->config.blend_mode = BUFFER_BLEND_EVERY_OTHER_LINE; break;
        }
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.adjustable_blend = GET_INT();
        pos += 4;
    }

    if (this->config.buffer < BufferSave_Info::parameters[1].int_min) {
        this->config.buffer = BufferSave_Info::parameters[1].int_min;
    }
    if (this->config.buffer > BufferSave_Info::parameters[1].int_max) {
        this->config.buffer = BufferSave_Info::parameters[1].int_max;
    }
}

int E_BufferSave::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->config.action);
    pos += 4;
    PUT_INT(this->config.buffer);
    pos += 4;
    uint32_t blend = BUFFER_BLEND_REPLACE;
    switch (this->config.blend_mode) {
        default:
        case BUFFER_BLEND_REPLACE: blend = 0; break;
        case BUFFER_BLEND_ADDITIVE: blend = 2; break;
        case BUFFER_BLEND_MAXIMUM: blend = 7; break;
        case BUFFER_BLEND_5050: blend = 1; break;
        case BUFFER_BLEND_SUB1: blend = 4; break;
        case BUFFER_BLEND_SUB2: blend = 9; break;
        case BUFFER_BLEND_MULTIPLY: blend = 10; break;
        case BUFFER_BLEND_ADJUSTABLE: blend = 11; break;
        case BUFFER_BLEND_XOR: blend = 6; break;
        case BUFFER_BLEND_MINIMUM: blend = 8; break;
        case BUFFER_BLEND_EVERY_OTHER_PIXEL: blend = 3; break;
        case BUFFER_BLEND_EVERY_OTHER_LINE: blend = 5; break;
    }
    PUT_INT(blend);
    pos += 4;
    PUT_INT(this->config.adjustable_blend);
    pos += 4;
    return pos;
}

Effect_Info* create_BufferSave_Info() { return new BufferSave_Info(); }
Effect* create_BufferSave(AVS_Instance* avs) { return new E_BufferSave(avs); }
void set_BufferSave_desc(char* desc) { E_BufferSave::set_desc(desc); }
