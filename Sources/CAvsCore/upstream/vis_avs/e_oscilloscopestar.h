#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"

struct OscilloscopeStar_Color_Config : public Effect_Config {
    uint64_t color = 0x000000;
    OscilloscopeStar_Color_Config() = default;
    OscilloscopeStar_Color_Config(uint64_t color) : color(color) {}
};

struct OscilloscopeStar_Config : public Effect_Config {
    int64_t audio_channel = AUDIO_CENTER;
    int64_t position = HPOS_CENTER;
    int64_t size = 8;
    int64_t rotation = 3;
    std::vector<OscilloscopeStar_Color_Config> colors;
    OscilloscopeStar_Config() { this->colors.emplace_back(0xffffff); }
};

struct OscilloscopeStar_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Oscilloscope Star";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 2;
    static constexpr char const* legacy_ape_id = nullptr;

    static constexpr uint32_t num_color_params = 1;
    static constexpr Parameter color_params[num_color_params] = {
        P_COLOR(offsetof(OscilloscopeStar_Color_Config, color), "Color"),
    };

    static constexpr uint32_t num_parameters = 5;
    static constexpr Parameter parameters[num_parameters] = {
        P_SELECT(offsetof(OscilloscopeStar_Config, audio_channel),
                 "Audio Channel",
                 audio_channels),
        P_SELECT(offsetof(OscilloscopeStar_Config, position), "Position", h_positions),
        P_IRANGE(offsetof(OscilloscopeStar_Config, size), "Size", 0, 32),
        P_IRANGE(offsetof(OscilloscopeStar_Config, rotation), "Rotation", -16, 16),
        P_LIST<OscilloscopeStar_Color_Config>(offsetof(OscilloscopeStar_Config, colors),
                                              "Colors",
                                              color_params,
                                              num_color_params,
                                              1,
                                              16),
    };

    EFFECT_INFO_GETTERS;
};

class E_OscilloscopeStar
    : public Configurable_Effect<OscilloscopeStar_Info, OscilloscopeStar_Config> {
   public:
    E_OscilloscopeStar(AVS_Instance* avs);
    virtual ~E_OscilloscopeStar() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_OscilloscopeStar* clone() { return new E_OscilloscopeStar(*this); }

   private:
    uint32_t current_color_pos;
    double current_rotation;
};
