#pragma once

#include "effect.h"
#include "effect_info.h"

enum ClearScreen_Blend_Modes {
    CLEAR_BLEND_REPLACE = 0,
    CLEAR_BLEND_ADDITIVE = 1,
    CLEAR_BLEND_5050 = 2,
    CLEAR_BLEND_DEFAULT = 3,
};

struct ClearScreen_Config : public Effect_Config {
    uint64_t color = 0xffffff;
    int64_t blend_mode = CLEAR_BLEND_DEFAULT;
    bool only_first = false;
};

struct ClearScreen_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Clear Screen";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 25;
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

    static void on_only_first(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 3;
    static constexpr Parameter parameters[num_parameters] = {
        P_COLOR(offsetof(ClearScreen_Config, color), "Color"),
        P_SELECT(offsetof(ClearScreen_Config, blend_mode), "Blend Mode", blend_modes),
        P_BOOL(offsetof(ClearScreen_Config, only_first),
               "Only First",
               nullptr,
               on_only_first),
    };

    EFFECT_INFO_GETTERS;
};

class E_ClearScreen : public Configurable_Effect<ClearScreen_Info, ClearScreen_Config> {
   public:
    E_ClearScreen(AVS_Instance* avs);
    virtual ~E_ClearScreen() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_ClearScreen* clone() { return new E_ClearScreen(*this); }

    void reset_fcounter_on_only_first();

    int frame_counter;
};
