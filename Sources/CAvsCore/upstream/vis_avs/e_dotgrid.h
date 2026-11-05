#pragma once

#include "effect.h"
#include "effect_info.h"

#include <cstdint>

enum DotGrid_Blend_Mode {
    DOTGRID_BLEND_REPLACE = 0,
    DOTGRID_BLEND_ADDITIVE = 1,
    DOTGRID_BLEND_5050 = 2,
    DOTGRID_BLEND_DEFAULT = 3,
};

struct DotGrid_Color_Config : public Effect_Config {
    uint64_t color = 0x000000;
    DotGrid_Color_Config() = default;
    DotGrid_Color_Config(uint64_t color) : color(color) {}
};

struct DotGrid_Config : public Effect_Config {
    std::vector<DotGrid_Color_Config> colors;
    int64_t spacing = 8;
    int64_t speed_x = 128;
    int64_t speed_y = 128;
    int64_t blend_mode = DOTGRID_BLEND_DEFAULT;
    DotGrid_Config() { this->colors.emplace_back(0xffffff); }
};

struct DotGrid_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Dot Grid";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 17;
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

    static constexpr uint32_t num_color_params = 1;
    static constexpr Parameter color_params[num_color_params] = {
        P_COLOR(offsetof(DotGrid_Color_Config, color), "Color"),
    };

    static void zero_speed_x(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void zero_speed_y(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 7;
    static constexpr Parameter parameters[num_parameters] = {
        P_LIST<DotGrid_Color_Config>(offsetof(DotGrid_Config, colors),
                                     "Colors",
                                     color_params,
                                     num_color_params,
                                     1,
                                     16),
        P_IRANGE(offsetof(DotGrid_Config, spacing), "Spacing", 0, UINT32_MAX),
        P_IRANGE(offsetof(DotGrid_Config, speed_x), "Speed X", -512, 544),
        P_IRANGE(offsetof(DotGrid_Config, speed_y), "Speed Y", -512, 544),
        P_SELECT(offsetof(DotGrid_Config, blend_mode), "Blend Mode", blend_modes),
        P_ACTION("Zero Speed X", zero_speed_x),
        P_ACTION("Zero Speed y", zero_speed_y),
    };

    EFFECT_INFO_GETTERS;
};

class E_DotGrid : public Configurable_Effect<DotGrid_Info, DotGrid_Config> {
   public:
    E_DotGrid(AVS_Instance* avs);
    virtual ~E_DotGrid() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_DotGrid* clone() { return new E_DotGrid(*this); }

    void zero_speed_x();
    void zero_speed_y();

   private:
    uint32_t current_color_pos;
    int xp;
    int yp;
};
