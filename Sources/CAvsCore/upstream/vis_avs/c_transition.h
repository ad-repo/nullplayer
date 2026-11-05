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

#include "effect.h"
#include "effect_info.h"
#include "undo.h"

#include "../platform.h"

enum Transition_Effect {
    TRANSITION_RANDOM = 0,
    TRANSITION_CROSS_DISSOLVE = 1,
    TRANSITION_PUSH_LEFT_RIGHT = 2,
    TRANSITION_PUSH_RIGHT_LEFT = 3,
    TRANSITION_PUSH_TOP_BOTTOM = 4,
    TRANSITION_PUSH_BOTTOM_TOP = 5,
    TRANSITION_NINE_RANDOM_BLOCKS = 6,
    TRANSITION_SPLIT_LEFT_RIGHT_PUSH = 7,
    TRANSITION_PUSH_LEFT_RIGHT_TO_CENTER = 8,
    TRANSITION_SQUEEZE_LEFT_RIGHT_TO_CENTER = 9,
    TRANSITION_WIPE_LEFT_RIGHT = 10,
    TRANSITION_WIPE_RIGHT_LEFT = 11,
    TRANSITION_WIPE_TOP_BOTTOM = 12,
    TRANSITION_WIPE_BOTTOM_TOP = 13,
    TRANSITION_DOT_DISSOLVE = 14,
};
#define TRANSITION_NUM_EFFECTS 14  // exclude "random"

enum Transition_Switch {
    TRANSITION_SWITCH_LOAD = 0,
    TRANSITION_SWITCH_NEXT_PREV = 1,
    TRANSITION_SWITCH_RANDOM = 2,
};

struct Transition_Config : public Effect_Config {
    int64_t effect = TRANSITION_CROSS_DISSOLVE;  // cfg_transition_mode & 0x7fff
    int64_t time_ms = 2000;                      // cfg_transitions_speed
    bool on_load = false;                        // cfg_transitions & 0x0001
    bool on_next_prev = false;                   // cfg_transitions & 0x0002
    bool on_random = true;                       // cfg_transitions & 0x0004
    bool keep_rendering_old_preset = true;       // cfg_transition_mode & 0x8000
    bool preinit_on_load = false;                // cfg_transitions2 & 0x0001
    bool preinit_on_next_prev = false;           // cfg_transitions2 & 0x0002
    bool preinit_on_random = true;               // cfg_transitions2 & 0x0004
    bool preinit_low_priority = true;            // cfg_transitions2 & 0x0020
    bool preinit_only_in_fullscreen = true;      // !(cfg_transitions2 & 0x0080)
};

struct Transition_Info : public Effect_Info {
    static constexpr char const* group = "";
    static constexpr char const* name = "Transition";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = -5;
    static constexpr char const* legacy_ape_id = nullptr;

    static constexpr uint32_t num_effects = 15;
    static constexpr char const* effects[num_effects] = {
        "Random",
        "Cross dissolve",
        "L/R Push",
        "R/L Push",
        "T/B Push",
        "B/T Push",
        "9 Random Blocks",
        "Split L/R Push",
        "L/R to Center Push",
        "L/R to Center Squeeze",
        "L/R Wipe",
        "R/L Wipe",
        "T/B Wipe",
        "B/T Wipe",
        "Dot Dissolve",
    };

    static const char* const* effect_names(int64_t* length_out) {
        *length_out = num_effects;
        return effects;
    }

    static constexpr uint32_t num_parameters = 11;
    static constexpr Parameter parameters[num_parameters] = {
        P_SELECT(offsetof(Transition_Config, effect), "Effect", effect_names),
        P_IRANGE(offsetof(Transition_Config, time_ms), "Time", 250, 80000),
        P_BOOL(offsetof(Transition_Config, on_load), "On Load"),
        P_BOOL(offsetof(Transition_Config, on_next_prev), "On Next/Prev"),
        P_BOOL(offsetof(Transition_Config, on_random), "On Random"),
        P_BOOL(offsetof(Transition_Config, keep_rendering_old_preset),
               "Keep rendering old preset"),
        P_BOOL(offsetof(Transition_Config, preinit_on_load), "Pre-Init on Load"),
        P_BOOL(offsetof(Transition_Config, preinit_on_next_prev),
               "Pre-Init on Next/Prev"),
        P_BOOL(offsetof(Transition_Config, preinit_on_random), "Pre-Init on Random"),
        P_BOOL(offsetof(Transition_Config, preinit_low_priority),
               "Low-Priority Pre-Init"),
        P_BOOL(offsetof(Transition_Config, preinit_only_in_fullscreen),
               "Pre-Init Only in Fullscreen"),
    };

    virtual bool can_have_child_components() const { return true; }
    virtual bool is_createable_by_user() const { return false; }

    EFFECT_INFO_GETTERS;
};

class Transition : public Configurable_Effect<Transition_Info, Transition_Config> {
   protected:
    int* framebuffers_primary[2]{};
    int* framebuffers_secondary[2]{};
    int fb_select_primary;
    int fb_select_secondary;
    int last_w = 0;
    int last_h = 0;
    uint64_t start_time = 0;
    int64_t current_effect = TRANSITION_RANDOM;
    bool current_keep_rendering_old_preset = false;
    int mask = 0;
    thread_t* init_thread = nullptr;
    std::string last_file;
    Transition_Switch switch_type = TRANSITION_SWITCH_LOAD;
    int transition_flags = 0;
    bool prev_renders_need_cleanup = false;

   public:
    static uint32_t init_thread_func(void* p);

    int load_preset(char* file,
                    Transition_Switch switch_type,
                    C_UndoItem* item = nullptr);
    void clean_prev_renders_if_needed();
    Transition(AVS_Instance* avs);
    virtual ~Transition();

    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    void make_legacy_config(int32_t& cfg_effect_and_keep_rendering_out,
                            int32_t& cfg_switch_out,
                            int32_t& cfg_preinit_out,
                            int32_t& cfg_speed_out);
    void apply_legacy_config(int32_t cfg_effect_and_keep_rendering,
                             int32_t cfg_switch,
                             int32_t cfg_preinit,
                             int32_t cfg_speed);
    Transition* clone() { return nullptr; }

   private:
    bool transition_enabled_for(Transition_Switch switch_type);
    bool preinit_enabled_for(Transition_Switch switch_type);
    void reset_framebuffers();
};
