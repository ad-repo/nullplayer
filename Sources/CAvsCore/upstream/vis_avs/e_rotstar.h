#pragma once

#include "effect.h"
#include "effect_info.h"

struct RotStar_Color_Config : public Effect_Config {
    uint64_t color = 0x000000;
    RotStar_Color_Config() = default;
    RotStar_Color_Config(uint64_t color) : color(color) {}
};

struct RotStar_Config : public Effect_Config {
    std::vector<RotStar_Color_Config> colors;
    RotStar_Config() { this->colors.emplace_back(0xffffff); }
};

struct RotStar_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Rotating Stars";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 13;
    static constexpr char const* legacy_ape_id = nullptr;

    static constexpr uint32_t num_color_params = 1;
    static constexpr Parameter color_params[num_color_params] = {
        P_COLOR(offsetof(RotStar_Color_Config, color), "Color"),
    };

    static constexpr uint32_t num_parameters = 1;
    static constexpr Parameter parameters[num_parameters] = {
        P_LIST<RotStar_Color_Config>(offsetof(RotStar_Config, colors),
                                     "Colors",
                                     color_params,
                                     num_color_params,
                                     1,
                                     16),
    };

    EFFECT_INFO_GETTERS;
};

class E_RotStar : public Configurable_Effect<RotStar_Info, RotStar_Config> {
   public:
    E_RotStar(AVS_Instance* avs);
    virtual ~E_RotStar();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_RotStar* clone() { return new E_RotStar(*this); }

    uint32_t color_pos;
    double r;
};
