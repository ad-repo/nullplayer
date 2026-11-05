#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"

struct Mosaic_Config : public Effect_Config {
    int64_t size = 50;
    int64_t on_beat_size = 0;
    bool on_beat_size_change = false;
    int64_t on_beat_duration = 15;
    int64_t blend_mode = BLEND_SIMPLE_REPLACE;
};

struct Mosaic_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Mosaic";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 30;
    static constexpr char const* legacy_ape_id = nullptr;

    static constexpr uint32_t num_parameters = 5;
    static constexpr Parameter parameters[num_parameters] = {
        P_IRANGE(offsetof(Mosaic_Config, size), "Size", 1, 100),
        P_IRANGE(offsetof(Mosaic_Config, on_beat_size), "On Beat Size", 1, 100),
        P_BOOL(offsetof(Mosaic_Config, on_beat_size_change), "On Beat Size Change"),
        P_IRANGE(offsetof(Mosaic_Config, on_beat_duration), "On Beat Duration", 1, 100),
        P_SELECT(offsetof(Mosaic_Config, blend_mode), "Blend Mode", blend_modes_simple),
    };

    EFFECT_INFO_GETTERS;
};

class E_Mosaic : public Configurable_Effect<Mosaic_Info, Mosaic_Config> {
   public:
    E_Mosaic(AVS_Instance* avs);
    virtual ~E_Mosaic() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Mosaic* clone() { return new E_Mosaic(*this); }

    int32_t on_beat_cooldown;
    int32_t cur_size;
};
