#pragma once

#include "effect.h"
#include "effect_info.h"

#define SET_BEAT 0x10000000
#define CLR_BEAT 0x20000000

enum CustomBPM_Mode {
    CUSTOM_BPM_FIXED = 0,
    CUSTOM_BPM_SKIP = 1,
    CUSTOM_BPM_INVERT = 2,
};

struct CustomBPM_Config : public Effect_Config {
    int64_t mode = CUSTOM_BPM_FIXED;
    int64_t fixed_bpm = 120;
    int64_t skip = 1;
    int64_t skip_first_beats = 0;
    int64_t beat_count_in = 0;
    int64_t beat_count_out = 0;
};

struct CustomBPM_Info : public Effect_Info {
    static constexpr char const* group = "Misc";
    static constexpr char const* name = "Custom BPM";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 33;
    static constexpr char const* legacy_ape_id = nullptr;

    static const char* const* bpm_modes(int64_t* length_out) {
        *length_out = 3;
        static const char* const options[3] = {
            "Fixed",
            "Skip Beats",
            "Invert",
        };
        return options;
    }

    static constexpr uint32_t num_parameters = 6;
    static constexpr Parameter parameters[num_parameters] = {
        P_SELECT(offsetof(CustomBPM_Config, mode), "Mode", bpm_modes, nullptr),
        P_IRANGE(offsetof(CustomBPM_Config, fixed_bpm), "Fixed BPM", 6, 300),
        P_IRANGE(offsetof(CustomBPM_Config, skip), "Skip", 1, 16),
        P_IRANGE(offsetof(CustomBPM_Config, skip_first_beats),
                 "Skip First Beats",
                 0,
                 64),
        P_INT_X(offsetof(CustomBPM_Config, beat_count_in), "Input Beat Count"),
        P_INT_X(offsetof(CustomBPM_Config, beat_count_out), "Output Beat Count"),
    };

    EFFECT_INFO_GETTERS;
};

class E_CustomBPM : public Configurable_Effect<CustomBPM_Info, CustomBPM_Config> {
   public:
    E_CustomBPM(AVS_Instance* avs);
    virtual ~E_CustomBPM() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_CustomBPM* clone() { return new E_CustomBPM(*this); }

   private:
    uint64_t fixed_bpm_last_time;
    uint32_t skip_count;
};
