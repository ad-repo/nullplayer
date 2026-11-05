#pragma once

#include "effect.h"
#include "effect_info.h"

enum BassSpin_Modes {
    BASSSPIN_MODE_OUTLINE = 0,
    BASSSPIN_MODE_FILLED = 1,
};

struct BassSpin_Config : public Effect_Config {
    bool enabled_left = true;
    bool enabled_right = true;
    uint64_t color_left = 0xffffff;
    uint64_t color_right = 0xffffff;
    int64_t mode = BASSSPIN_MODE_FILLED;
};

struct BassSpin_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Bass Spin";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 7;
    static constexpr char const* legacy_ape_id = nullptr;

    static const char* const* modes(int64_t* length_out) {
        *length_out = 2;
        static const char* const options[2] = {
            "Outline",
            "Filled",
        };
        return options;
    }

    static constexpr uint32_t num_parameters = 5;
    static constexpr Parameter parameters[num_parameters] = {
        P_BOOL(offsetof(BassSpin_Config, enabled_left), "Enabled Left"),
        P_BOOL(offsetof(BassSpin_Config, enabled_right), "Enabled Right"),
        P_COLOR(offsetof(BassSpin_Config, color_left), "Color Left"),
        P_COLOR(offsetof(BassSpin_Config, color_right), "Color Right"),
        P_SELECT(offsetof(BassSpin_Config, mode), "Mode", modes),
    };

    EFFECT_INFO_GETTERS;
};

class E_BassSpin : public Configurable_Effect<BassSpin_Info, BassSpin_Config> {
   public:
    E_BassSpin(AVS_Instance* avs);
    virtual ~E_BassSpin() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_BassSpin* clone() { return new E_BassSpin(*this); }

    static void render_triangle(uint32_t* fb,
                                int32_t points[6],
                                int32_t width,
                                int32_t height,
                                uint32_t color);

    int last_a;
    int lx[2][2], ly[2][2];
    double r_v[2];
    double v[2];
    double dir[2];
};
