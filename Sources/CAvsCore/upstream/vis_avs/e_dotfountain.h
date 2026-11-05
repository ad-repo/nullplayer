#pragma once

#include "effect.h"
#include "effect_info.h"
#include "pixel_format.h"

#include <sys/types.h>

#define NUM_ROT_DIV          30
#define NUM_ROT_HEIGHT       256
#define COLOR_MAP_LERP_STEPS 16
#define COLOR_MAP_SIZE       4 * COLOR_MAP_LERP_STEPS  // 4 intervals, between 5 colors

struct DotFountain_Color_Config : public Effect_Config {
    uint64_t color = 0xffffff;
    DotFountain_Color_Config() = default;
    DotFountain_Color_Config(uint64_t color) : color(color) {}
};

struct DotFountain_Config : public Effect_Config {
    double rotation = 0;
    int64_t rotation_speed = 16;
    int64_t angle = -20;
    std::vector<DotFountain_Color_Config> colors = {
        0x1c6b18,
        0xff0a23,
        0x2a1d74,
        0x9036d9,
        0x6b88ff,
    };
};

struct DotFountain_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Dot Fountain";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 19;
    static constexpr char const* legacy_ape_id = nullptr;

    static void init_color_map(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void init_color_map_list(Effect*,
                                    const Parameter*,
                                    const std::vector<int64_t>&,
                                    int64_t index1,
                                    int64_t index2);

    static constexpr uint32_t num_color_params = 1;
    static constexpr Parameter color_params[num_color_params] = {
        P_COLOR(offsetof(DotFountain_Color_Config, color),
                "Color",
                nullptr,
                init_color_map),
    };

    static constexpr uint32_t num_parameters = 4;
    static constexpr Parameter parameters[num_parameters] = {
        P_FLOAT(offsetof(DotFountain_Config, rotation), "Current Rotation"),
        P_IRANGE(offsetof(DotFountain_Config, rotation_speed),
                 "Rotation Speed",
                 -50,
                 50),
        P_IRANGE(offsetof(DotFountain_Config, angle), "Angle", -90, 91),
        P_LIST<DotFountain_Color_Config>(offsetof(DotFountain_Config, colors),
                                         "Colors",
                                         color_params,
                                         num_color_params,
                                         5,
                                         5,
                                         nullptr,
                                         init_color_map_list,
                                         init_color_map_list,
                                         init_color_map_list),
    };

    EFFECT_INFO_GETTERS;
};

struct DotFountain_Point {
    float radius;
    float delta_radius;
    float height;
    float delta_height;
    float ax;
    float ay;
    pixel_rgb0_8 color;
};

class E_DotFountain : public Configurable_Effect<DotFountain_Info, DotFountain_Config> {
   public:
    E_DotFountain(AVS_Instance* avs);
    virtual ~E_DotFountain() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_DotFountain* clone() { return new E_DotFountain(*this); }
    void init_color_map();

   private:
    DotFountain_Point points[NUM_ROT_HEIGHT][NUM_ROT_DIV];
    pixel_rgb0_8 color_map[COLOR_MAP_SIZE];
};
