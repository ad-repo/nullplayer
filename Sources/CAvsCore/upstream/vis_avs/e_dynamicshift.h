#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"
#include "effect_programmable.h"

struct DynamicShift_Config : public Effect_Config {
    std::string init = "d=0;";
    std::string frame = "x=sin(d)*1.4; y=1.4*cos(d); d=d+0.01;";
    std::string beat = "d=d+2.0";
    // Unused but necessary for Programmable_Effect template:
    std::string point;

    int64_t blend_mode = BLEND_SIMPLE_REPLACE;
    bool bilinear = true;
};

struct DynamicShift_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Dynamic Shift";
    static constexpr char const* help =
        "better Dynamic shift help goes here (send me some :)\r\n"
        "Variables:\r\n"
        "x,y = amount to shift (in pixels - set these)\r\n"
        "w,h = width, height (in pixels)\r\n"
        "b = isBeat\r\n"
        "alpha = alpha value (0.0-1.0) for blend\r\n";
    static constexpr int32_t legacy_id = 42;
    static constexpr char* legacy_ape_id = NULL;

    static const char* const* blend_modes(int64_t* length_out) {
        *length_out = 2;
        static const char* const options[2] = {
            "Replace",
            "50/50",
        };
        return options;
    }

    static void recompile(Effect*, const Parameter*, const std::vector<int64_t>&);
    static constexpr uint32_t num_parameters = 5;
    static constexpr Parameter parameters[num_parameters] = {
        P_STRING(offsetof(DynamicShift_Config, init), "Init", NULL, recompile),
        P_STRING(offsetof(DynamicShift_Config, frame), "Frame", NULL, recompile),
        P_STRING(offsetof(DynamicShift_Config, beat), "Beat", NULL, recompile),
        P_SELECT(offsetof(DynamicShift_Config, blend_mode), "Blend Mode", blend_modes),
        P_BOOL(offsetof(DynamicShift_Config, bilinear), "Bilinear"),
    };

    EFFECT_INFO_GETTERS;
};

struct DynamicShift_Vars : public Variables {
    double* x;
    double* y;
    double* w;
    double* h;
    double* b;
    double* alpha;

    virtual void register_(void*);
    virtual void init(int, int, int, va_list);
};

class E_DynamicShift : public Programmable_Effect<DynamicShift_Info,
                                                  DynamicShift_Config,
                                                  DynamicShift_Vars> {
   public:
    E_DynamicShift(AVS_Instance* avs);
    virtual ~E_DynamicShift();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_DynamicShift* clone() { return new E_DynamicShift(*this); }

    int32_t m_lastw;
    int32_t m_lasth;
};
