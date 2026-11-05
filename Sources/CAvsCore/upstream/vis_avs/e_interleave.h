#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"

struct Interleave_Config : public Effect_Config {
    int64_t x = 1;
    int64_t y = 1;
    uint64_t color = 0x000000;
    bool on_beat = false;
    int64_t on_beat_x = 1;
    int64_t on_beat_y = 1;
    int64_t on_beat_duration = 4;
    int64_t blend_mode = BLEND_SIMPLE_REPLACE;
};

struct Interleave_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Interleave";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 23;
    static constexpr char* legacy_ape_id = NULL;

    static void on_x_change(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void on_y_change(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void on_duration_change(Effect*,
                                   const Parameter*,
                                   const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 8;
    static constexpr Parameter parameters[num_parameters] = {
        P_IRANGE(offsetof(Interleave_Config, x), "X", 0, 64, NULL, on_x_change),
        P_IRANGE(offsetof(Interleave_Config, y), "Y", 0, 64, NULL, on_y_change),
        P_COLOR(offsetof(Interleave_Config, color), "Color"),
        P_BOOL(offsetof(Interleave_Config, on_beat), "On Beat"),
        P_IRANGE(offsetof(Interleave_Config, on_beat_x),
                 "On Beat X",
                 0,
                 64,
                 NULL,
                 on_x_change),
        P_IRANGE(offsetof(Interleave_Config, on_beat_y),
                 "On Beat Y",
                 0,
                 64,
                 NULL,
                 on_y_change),
        P_IRANGE(offsetof(Interleave_Config, on_beat_duration),
                 "On Beat Duration",
                 0,
                 64,
                 NULL,
                 on_duration_change),
        P_SELECT(offsetof(Interleave_Config, blend_mode),
                 "Blend Mode",
                 blend_modes_simple),
    };

    EFFECT_INFO_GETTERS;
};

class E_Interleave : public Configurable_Effect<Interleave_Info, Interleave_Config> {
   public:
    E_Interleave(AVS_Instance* avs);
    virtual ~E_Interleave();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Interleave* clone() { return new E_Interleave(*this); }

    double cur_x, cur_y;
};
