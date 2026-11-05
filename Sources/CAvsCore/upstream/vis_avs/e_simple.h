#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"

struct Simple_Color_Config : public Effect_Config {
    uint64_t color = 0x000000;
    Simple_Color_Config() = default;
    Simple_Color_Config(uint64_t color) : color(color) {}
};

struct Simple_Config : public Effect_Config {
    int64_t audio_source = AUDIO_SPECTRUM;
    int64_t draw_mode = DRAW_SOLID;
    int64_t audio_channel = AUDIO_CENTER;
    int64_t position = VPOS_CENTER;
    std::vector<Simple_Color_Config> colors;
    Simple_Config() { this->colors.emplace_back(0xffffff); }
};

struct Simple_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Simple";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 0;
    static constexpr char* legacy_ape_id = NULL;

    static constexpr uint32_t num_color_params = 1;
    static constexpr Parameter color_params[num_color_params] = {
        P_COLOR(offsetof(Simple_Color_Config, color), "Color"),
    };

    static constexpr uint32_t num_parameters = 5;
    static constexpr Parameter parameters[num_parameters] = {
        P_SELECT(offsetof(Simple_Config, audio_source), "Audio Source", audio_sources),
        P_SELECT(offsetof(Simple_Config, draw_mode), "Draw Mode", draw_modes),
        P_SELECT(offsetof(Simple_Config, audio_channel),
                 "Audio Channel",
                 audio_channels),
        P_SELECT(offsetof(Simple_Config, position), "Position", v_positions),
        P_LIST<Simple_Color_Config>(offsetof(Simple_Config, colors),
                                    "Colors",
                                    color_params,
                                    num_color_params,
                                    1,
                                    16),
    };

    EFFECT_INFO_GETTERS;
};

class E_Simple : public Configurable_Effect<Simple_Info, Simple_Config> {
   public:
    E_Simple(AVS_Instance* avs);
    virtual ~E_Simple();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Simple* clone() { return new E_Simple(*this); }

    uint32_t color_pos;
};
