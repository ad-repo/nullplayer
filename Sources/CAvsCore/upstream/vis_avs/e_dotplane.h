#pragma once

#include "effect.h"
#include "effect_info.h"
#include "pixel_format.h"

#define GRID_WIDTH           64
#define COLOR_MAP_LERP_STEPS 16
#define COLOR_MAP_SIZE       4 * COLOR_MAP_LERP_STEPS  // 4 intervals, between 5 colors

struct DotPlane_Color_Config : public Effect_Config {
    uint64_t color = 0xffffff;
    DotPlane_Color_Config() = default;
    DotPlane_Color_Config(uint64_t color) : color(color) {}
};

struct DotPlane_Config : public Effect_Config {
    double rotation = 0.0;
    int64_t rotation_speed = 16;
    int64_t angle = -20;
    std::vector<DotPlane_Color_Config> colors = {
        0x1c6b18,
        0xff0a23,
        0x2a1d74,
        0x9036d9,
        0x6b88ff,
    };
};

struct DotPlane_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Dot Plane";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 1;
    static constexpr char const* legacy_ape_id = nullptr;

    static void init_color_map(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void init_color_map_list(Effect*,
                                    const Parameter*,
                                    const std::vector<int64_t>&,
                                    int64_t index1,
                                    int64_t index2);

    static constexpr uint32_t num_color_params = 1;
    static constexpr Parameter color_params[num_color_params] = {
        P_COLOR(offsetof(DotPlane_Color_Config, color),
                "Color",
                nullptr,
                init_color_map),
    };

    static constexpr uint32_t num_parameters = 4;
    static constexpr Parameter parameters[num_parameters] = {
        P_FLOAT(offsetof(DotPlane_Config, rotation), "Current Rotation"),
        P_IRANGE(offsetof(DotPlane_Config, rotation_speed), "Rotation Speed", -50, 50),
        P_IRANGE(offsetof(DotPlane_Config, angle), "Angle", -90, 91),
        P_LIST<DotPlane_Color_Config>(offsetof(DotPlane_Config, colors),
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

class E_DotPlane : public Configurable_Effect<DotPlane_Info, DotPlane_Config> {
   public:
    E_DotPlane(AVS_Instance* avs);
    virtual ~E_DotPlane() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_DotPlane* clone() { return new E_DotPlane(*this); }

    void init_color_map();

   private:
    float grid_height[GRID_WIDTH * GRID_WIDTH];
    float grid_height_delta[GRID_WIDTH * GRID_WIDTH];
    pixel_rgb0_8 grid_color[GRID_WIDTH * GRID_WIDTH];
    pixel_rgb0_8 color_map[COLOR_MAP_SIZE];
};
