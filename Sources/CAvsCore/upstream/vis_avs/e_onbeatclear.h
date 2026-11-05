#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"

struct OnBeatClear_Config : public Effect_Config {
    uint64_t color = 0xffffff;
    int64_t blend_mode = BLEND_SIMPLE_REPLACE;
    int64_t every_n_beats = 1;
};

struct OnBeatClear_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "On Beat Clear";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 5;
    static constexpr char const* legacy_ape_id = nullptr;

    static const char* const* blend_modes(int64_t* length_out) {
        *length_out = 2;
        static const char* const options[2] = {
            "Replace",
            "50/50",
        };
        return options;
    }

    static void callback(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 3;
    static constexpr Parameter parameters[num_parameters] = {
        P_COLOR(offsetof(OnBeatClear_Config, color), "Color"),
        P_SELECT(offsetof(OnBeatClear_Config, blend_mode), "Blend Mode", blend_modes),
        P_IRANGE(offsetof(OnBeatClear_Config, every_n_beats), "Every N Beats", 0, 100),
    };

    EFFECT_INFO_GETTERS;
};

class E_OnBeatClear : public Configurable_Effect<OnBeatClear_Info, OnBeatClear_Config> {
   public:
    E_OnBeatClear(AVS_Instance* avs);
    virtual ~E_OnBeatClear() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_OnBeatClear* clone() { return new E_OnBeatClear(*this); }

   private:
    int32_t beat_counter;
};
