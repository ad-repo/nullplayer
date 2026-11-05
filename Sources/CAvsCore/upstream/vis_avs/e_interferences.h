#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"

#define INTERFERENCES_MAX_POINTS 8

struct Interferences_Config : public Effect_Config {
    int64_t num_layers = 2;
    bool separate_rgb = true;
    int64_t distance = 10;
    int64_t alpha = 128;
    int64_t rotation = 0;
    int64_t init_rotation = 0;
    bool on_beat = true;
    int64_t on_beat_distance = 32;
    int64_t on_beat_alpha = 192;
    int64_t on_beat_rotation = 25;
    double on_beat_speed = 0.2;
    int64_t blend_mode = 0;
};

struct Interferences_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Interferences";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 41;
    static constexpr char* legacy_ape_id = NULL;

    static void on_init_rotation(Effect*,
                                 const Parameter*,
                                 const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 12;
    static constexpr Parameter parameters[num_parameters] = {
        P_IRANGE(offsetof(Interferences_Config, num_layers),
                 "Layers",
                 0,
                 INTERFERENCES_MAX_POINTS),
        P_BOOL(offsetof(Interferences_Config, separate_rgb), "Separate RGB"),
        P_IRANGE(offsetof(Interferences_Config, distance), "Distance", 1, 64),
        P_IRANGE(offsetof(Interferences_Config, alpha), "Alpha", 1, 255),
        P_IRANGE(offsetof(Interferences_Config, rotation), "Rotation", -32, 32),
        P_IRANGE(offsetof(Interferences_Config, init_rotation),
                 "Initial Rotation",
                 0,
                 255,
                 NULL,
                 on_init_rotation),
        P_BOOL(offsetof(Interferences_Config, on_beat), "On Beat"),
        P_IRANGE(offsetof(Interferences_Config, on_beat_distance),
                 "On-Beat Distance",
                 1,
                 64),
        P_IRANGE(offsetof(Interferences_Config, on_beat_alpha),
                 "On-Beat Alpha",
                 1,
                 255),
        P_IRANGE(offsetof(Interferences_Config, on_beat_rotation),
                 "On-Beat Rotation",
                 -32,
                 32),
        P_FRANGE(offsetof(Interferences_Config, on_beat_speed),
                 "On-Beat Speed",
                 0.01,
                 1.28),
        P_SELECT(offsetof(Interferences_Config, blend_mode),
                 "Blend Mode",
                 blend_modes_simple),
    };

    EFFECT_INFO_GETTERS;
};

class E_Interferences
    : public Configurable_Effect<Interferences_Info, Interferences_Config> {
   public:
    E_Interferences(AVS_Instance* avs);
    virtual ~E_Interferences() {}
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Interferences* clone() { return new E_Interferences(*this); }

    int cur_rotation;
    double on_beat_fadeout;
};
