#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"

struct WaterBump_Config : public Effect_Config {
    int64_t fluidity = 6;
    int64_t depth = 600;
    bool random = false;
    int64_t drop_position_x = HPOS_CENTER;
    int64_t drop_position_y = VPOS_CENTER;
    int64_t drop_radius = 40;
    int64_t method = 0;
};

struct WaterBump_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Water Bump";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 31;
    static constexpr char const* legacy_ape_id = nullptr;

    static constexpr uint32_t num_parameters = 6;
    static constexpr Parameter parameters[num_parameters] = {
        P_IRANGE(offsetof(WaterBump_Config, fluidity), "Fluidity", 2, 10),
        P_IRANGE(offsetof(WaterBump_Config, depth), "Depth", 100, 2000),
        P_BOOL(offsetof(WaterBump_Config, random), "Random"),
        P_SELECT(offsetof(WaterBump_Config, drop_position_x),
                 "Drop Position X",
                 h_positions),
        P_SELECT(offsetof(WaterBump_Config, drop_position_y),
                 "Drop Position Y",
                 v_positions),
        P_IRANGE(offsetof(WaterBump_Config, drop_radius), "Drop Radius", 10, 100),
    };

    EFFECT_INFO_GETTERS;
};

class E_WaterBump : public Configurable_Effect<WaterBump_Info, WaterBump_Config> {
   public:
    E_WaterBump(AVS_Instance* avs);
    virtual ~E_WaterBump();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_WaterBump* clone() { return new E_WaterBump(*this); }

    void SineBlob(int x, int y, int radius, int height, int page);
    void CalcWater(int npage, int fluidity);
    /*
    void CalcWaterSludge(int npage, int fluidity);
    void HeightBlob(int x, int y, int radius, int height, int page);
    */

    int* buffers[2];
    int buffer_w, buffer_h;
    int page;
};
