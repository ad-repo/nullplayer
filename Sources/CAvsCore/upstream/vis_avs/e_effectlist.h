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
#pragma once

#include "constants.h"
#include "effect.h"
#include "effect_info.h"
#include "effect_programmable.h"

// size of extended data + 4 -- "cause we fucked up"
#define EFFECTLIST_AVS281D_EXT_SIZE 36

enum EffectList_Blend_Modes {
    LIST_BLEND_IGNORE = 0,
    LIST_BLEND_REPLACE = 1,
    LIST_BLEND_5050 = 2,
    LIST_BLEND_MAXIMUM = 3,
    LIST_BLEND_ADDITIVE = 4,
    LIST_BLEND_SUB_1 = 5,
    LIST_BLEND_SUB_2 = 6,
    LIST_BLEND_EVERY_OTHER_LINE = 7,
    LIST_BLEND_EVERY_OTHER_PIXEL = 8,
    LIST_BLEND_XOR = 9,
    LIST_BLEND_ADJUSTABLE = 10,
    LIST_BLEND_MULTIPLY = 11,
    LIST_BLEND_BUFFER = 12,
    LIST_BLEND_MINIMUM = 13,
};

struct EffectList_Config : public Effect_Config {
    bool on_beat = false;
    int64_t on_beat_frames = 1;
    bool clear_every_frame = false;
    int64_t input_blend_mode = LIST_BLEND_IGNORE;
    int64_t output_blend_mode = LIST_BLEND_REPLACE;
    int64_t input_blend_adjustable = 128;
    int64_t output_blend_adjustable = 128;
    int64_t input_blend_buffer = 1;
    int64_t output_blend_buffer = 1;
    bool input_blend_buffer_invert = false;
    bool output_blend_buffer_invert = false;
    bool use_code = false;
    std::string init;
    std::string frame;
    std::string beat;   // unused
    std::string point;  // unused
};

struct EffectList_Info : public Effect_Info {
    static constexpr char const* group = "";
    static constexpr char const* name = "Effect List";
    static constexpr char const* help =
        "Read/write 'enabled' to get/set whether the effect list is enabled for this"
        " frame\r\n"
        "Read/write 'beat' to get/set whether there is currently a beat\r\n"
        "Read/write 'clear' to get/set whether to clear the framebuffer\r\n"
        "If the input blend is set to adjustable, 'alphain' can be set from 0.0-1.0\r\n"
        "If the output blend is set to adjustable, 'alphaout' can be set from"
        " 0.0-1.0\r\n"
        "'w' and 'h' are set with the current width and height of the frame\r\n";
    static constexpr int32_t legacy_id = -2;
    static constexpr char const* legacy_ape_id = nullptr;
    static constexpr char const* legacy_v28_ape_id = "AVS 2.8+ Effect List Config";

    static const char* const* blend_modes(int64_t* length_out) {
        *length_out = 14;
        static const char* const options[14] = {
            "Ignore",
            "Replace",
            "50/50",
            "Maximum",
            "Additive",
            "Subtractive 1",
            "Subtractive 2",
            "Every Other Line",
            "Every Other Pixel",
            "XOR",
            "Adjustable",
            "Multiply",
            "Buffer",
            "Minimum",
        };
        return options;
    }

    static void recompile(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 14;
    static constexpr Parameter parameters[num_parameters] = {
        P_BOOL(offsetof(EffectList_Config, on_beat), "On Beat"),
        P_IRANGE(offsetof(EffectList_Config, on_beat_frames),
                 "On Beat Frames",
                 0,
                 INT64_MAX),
        P_BOOL(offsetof(EffectList_Config, clear_every_frame), "Clear Every Frame"),
        P_SELECT(offsetof(EffectList_Config, input_blend_mode),
                 "Input Blend Mode",
                 blend_modes),
        P_SELECT(offsetof(EffectList_Config, output_blend_mode),
                 "Output Blend Mode",
                 blend_modes),
        P_IRANGE(offsetof(EffectList_Config, input_blend_adjustable),
                 "Input Blend Adjustable",
                 0,
                 255),
        P_IRANGE(offsetof(EffectList_Config, output_blend_adjustable),
                 "Output Blend Adjustable",
                 0,
                 255),
        P_IRANGE(offsetof(EffectList_Config, input_blend_buffer),
                 "Input Blend Buffer",
                 1,
                 8),
        P_IRANGE(offsetof(EffectList_Config, output_blend_buffer),
                 "Output Blend Buffer",
                 1,
                 8),
        P_BOOL(offsetof(EffectList_Config, input_blend_buffer_invert),
               "Input Blend Buffer Invert"),
        P_BOOL(offsetof(EffectList_Config, output_blend_buffer_invert),
               "Output Blend Buffer Invert"),
        P_BOOL(offsetof(EffectList_Config, use_code), "Use Code"),
        P_STRING(offsetof(EffectList_Config, init), "Init", nullptr, recompile),
        P_STRING(offsetof(EffectList_Config, frame), "Frame", nullptr, recompile),
    };

    virtual bool can_have_child_components() const { return true; }

    EFFECT_INFO_GETTERS;
};

struct EffectList_Vars : public Variables {
    double* enabled;
    double* clear;
    double* beat;
    double* alpha_in;
    double* alpha_out;
    double* w;
    double* h;

    virtual void register_(void*);
    virtual void init(int, int, int, va_list);
};

class E_EffectList
    : public Programmable_Effect<EffectList_Info, EffectList_Config, EffectList_Vars> {
   public:
    E_EffectList(AVS_Instance* avs);
    virtual ~E_EffectList() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_EffectList* clone() { return new E_EffectList(*this); }
    int64_t get_num_renders() { return this->children.size(); }

    virtual bool can_multithread() { return true; }
    void smp_render_list(int min_threads,
                         Effect* component,
                         char visdata[2][2][576],
                         int is_beat,
                         int* framebuffer,
                         int* fbout,
                         int w,
                         int h);
    static void smp_cleanup_threads();

    Effect* get_child(int index);
    int64_t find(Effect* effect);
    bool remove_render(int index, int del);
    bool remove_render_from(Effect* effect, int del);
    int64_t insert_render(Effect* effect, int index);
    void clear_renders();

    typedef struct {
        void* vis_data;
        int nthreads;
        int is_beat;
        int* framebuffer;
        int* fbout;
        int w;
        int h;
        Effect* render;

        signal_t* quit_signal;
        thread_t* threads[MAX_SMP_THREADS];
        signal_t* thread_start[MAX_SMP_THREADS];
        signal_t* thread_done[MAX_SMP_THREADS];

        int num_threads;
    } smp_param_t;
    static uint32_t smp_thread_proc(void* parm);

    static smp_param_t smp;

   private:
    // ...
    uint32_t legacy_save_code_section_size();
    /* pixel_rgb0_8* */ int* list_framebuffer;
    int32_t last_w;
    int32_t last_h;
    int64_t on_beat_frames_cooldown;
};
