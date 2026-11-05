#pragma once

#include "effect.h"
#include "effect_info.h"

enum ColorClip_Modes {
    COLORCLIP_BELOW = 0,
    COLORCLIP_ABOVE = 1,
    COLORCLIP_NEAR = 2,
};

struct ColorClip_Config : public Effect_Config {
    int64_t mode = 0;
    uint64_t color_in = 0x202020;
    uint64_t color_out = 0x202020;
    int64_t distance = 10;
};

struct ColorClip_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Color Clip";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 12;
    static constexpr char const* legacy_ape_id = nullptr;

    static const char* const* modes(int64_t* length_out) {
        *length_out = 4;
        static const char* const options[4] = {
            "Off",
            "Below",
            "Above",
            "Near",
        };
        return options;
    }

    static void copy_in_to_out(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 5;
    static constexpr Parameter parameters[num_parameters] = {
        P_SELECT(offsetof(ColorClip_Config, mode), "Mode", modes),
        P_COLOR(offsetof(ColorClip_Config, color_in), "From Color"),
        P_COLOR(offsetof(ColorClip_Config, color_out), "To Color"),
        P_IRANGE(offsetof(ColorClip_Config, distance), "Distance", 0, 64),
        P_ACTION("Copy in to out color", copy_in_to_out),
    };

    EFFECT_INFO_GETTERS;
};

class E_ColorClip : public Configurable_Effect<ColorClip_Info, ColorClip_Config> {
   public:
    E_ColorClip(AVS_Instance* avs) : Configurable_Effect(avs) {}
    virtual ~E_ColorClip() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_ColorClip* clone() { return new E_ColorClip(*this); }

    void copy_in_to_out();
};
