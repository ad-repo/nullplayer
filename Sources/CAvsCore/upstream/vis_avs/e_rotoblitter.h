#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"

struct RotoBlitter_Config : public Effect_Config {
    int64_t zoom = 0;
    int64_t rotate = 0;
    int64_t blend_mode = BLEND_SIMPLE_REPLACE;
    bool bilinear = true;
    bool on_beat_reverse_enable = false;
    int64_t on_beat_reverse_speed = 0;
    bool on_beat_zoom_enable = false;
    int64_t on_beat_zoom = 0;
};

struct RotoBlitter_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Roto Blitter";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 9;
    static constexpr char* legacy_ape_id = NULL;

    static const char* const* blend_modes(int64_t* length_out) {
        *length_out = 2;
        static const char* const options[2] = {
            "Replace",
            "50/50",
        };
        return options;
    }

    static void on_zoom_change(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 8;
    static constexpr Parameter parameters[num_parameters] = {
        P_IRANGE(offsetof(RotoBlitter_Config, zoom),
                 "Zoom",
                 -31,
                 225,
                 NULL,
                 on_zoom_change),
        P_IRANGE(offsetof(RotoBlitter_Config, rotate), "Rotate", -32, 32),
        P_SELECT(offsetof(RotoBlitter_Config, blend_mode), "Blend Mode", blend_modes),
        P_BOOL(offsetof(RotoBlitter_Config, bilinear), "Bilinear"),
        P_BOOL(offsetof(RotoBlitter_Config, on_beat_reverse_enable),
               "Enable On Beat Reverse"),
        P_IRANGE(offsetof(RotoBlitter_Config, on_beat_reverse_speed),
                 "On Beat Reverse Speed",
                 0,
                 8),
        P_BOOL(offsetof(RotoBlitter_Config, on_beat_zoom_enable),
               "Enable On Beat Zoom"),
        P_IRANGE(offsetof(RotoBlitter_Config, on_beat_zoom), "On Beat Zoom", -31, 225),
    };

    EFFECT_INFO_GETTERS;
};

class E_RotoBlitter : public Configurable_Effect<RotoBlitter_Info, RotoBlitter_Config> {
    friend RotoBlitter_Info;

   public:
    E_RotoBlitter(AVS_Instance* avs);
    virtual ~E_RotoBlitter();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_RotoBlitter* clone() { return new E_RotoBlitter(*this); }

   private:
    int64_t current_zoom;
    int64_t direction;
    double current_rotation;

    int last_w;
    int last_h;
    int* w_mul;
};
