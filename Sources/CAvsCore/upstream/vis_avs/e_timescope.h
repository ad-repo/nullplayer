#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"

enum Timescope_Blend_Modes {
    TIMESCOPE_BLEND_REPLACE = 0,
    TIMESCOPE_BLEND_ADDITIVE = 1,
    TIMESCOPE_BLEND_5050 = 2,
    TIMESCOPE_BLEND_DEFAULT = 3,
};

struct Timescope_Config : public Effect_Config {
    uint64_t color = 0xffffff;
    int64_t blend_mode = TIMESCOPE_BLEND_DEFAULT;
    int64_t audio_channel = AUDIO_CENTER;
    int64_t bands = 576;
};

struct Timescope_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Timescope";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 39;
    static constexpr char const* legacy_ape_id = nullptr;

    static const char* const* blend_modes(int64_t* length_out) {
        *length_out = 4;
        static const char* const options[4] = {
            "Replace",
            "Additive",
            "50/50",
            "Default",
        };
        return options;
    }

    static constexpr uint32_t num_parameters = 4;
    static constexpr Parameter parameters[num_parameters] = {
        P_COLOR(offsetof(Timescope_Config, color), "Color"),
        P_SELECT(offsetof(Timescope_Config, blend_mode), "Blend Mode", blend_modes),
        P_SELECT(offsetof(Timescope_Config, audio_channel),
                 "Audio Channel",
                 audio_channels),
        P_IRANGE(offsetof(Timescope_Config, bands), "Bands", 16, 576),
    };

    EFFECT_INFO_GETTERS;
};

class E_Timescope : public Configurable_Effect<Timescope_Info, Timescope_Config> {
   public:
    E_Timescope(AVS_Instance* avs);
    virtual ~E_Timescope() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Timescope* clone() { return new E_Timescope(*this); }

   private:
    uint32_t position;
};
