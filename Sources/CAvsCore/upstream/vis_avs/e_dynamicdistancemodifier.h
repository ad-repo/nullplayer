#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"
#include "effect_programmable.h"

struct DynamicDistanceModifier_Config : public Effect_Config {
    std::string init = "u=1;t=0";
    std::string frame =
        "t=t+u;\r\n"
        "t=min(100,t);\r\n"
        "t=max(0,t);\r\n"
        "u=if(equal(t,100),-1,u);\r\n"
        "u=if(equal(t,0),1,u);\r\n";
    std::string beat = "";
    std::string point = "d=d-sigmoid((t-50)/100,2)";
    int64_t blend_mode = BLEND_SIMPLE_REPLACE;
    bool bilinear = false;
};

struct DynamicDistanceModifier_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Dynamic Distance Modifier";
    static constexpr char const* help =
        "The dynamic distance modifier allows you to dynamically (once per frame)\r\n"
        "change the source pixels for each ring of pixels out from the center.\r\n"
        "In the 'pixel' code section, 'd' represents the distance in pixels\r\n"
        "the current ring is from the center, and code can modify it to\r\n"
        "change the distance from the center where the source pixels for\r\n"
        "that ring would be read. This is a terrible explanation, and if\r\n"
        "you want to make a better one send it to me. \r\n"
        "\r\n"
        "Examples:\r\n"
        "Zoom in: 'd=d*0.9'\r\n"
        "Zoom out: 'd=d*1.1'\r\n"
        "Back and forth: pixel='d=d*(1.0+0.1*cos(t));', frame='t=t+0.1'\r\n";
    ;
    static constexpr int32_t legacy_id = 35;
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
    static constexpr uint32_t num_parameters = 6;
    static constexpr Parameter parameters[num_parameters] = {
        P_STRING(offsetof(DynamicDistanceModifier_Config, init),
                 "Init",
                 NULL,
                 recompile),
        P_STRING(offsetof(DynamicDistanceModifier_Config, frame),
                 "Frame",
                 NULL,
                 recompile),
        P_STRING(offsetof(DynamicDistanceModifier_Config, beat),
                 "Beat",
                 NULL,
                 recompile),
        P_STRING(offsetof(DynamicDistanceModifier_Config, point),
                 "Point",
                 NULL,
                 recompile),
        P_SELECT(offsetof(DynamicDistanceModifier_Config, blend_mode),
                 "Blend Mode",
                 blend_modes),
        P_BOOL(offsetof(DynamicDistanceModifier_Config, bilinear), "Bilinear"),
    };

    EFFECT_INFO_GETTERS;
};

struct DynamicDistanceModifier_Vars : public Variables {
    double* d;
    double* b;

    virtual void register_(void*);
    virtual void init(int, int, int, va_list);
};

class E_DynamicDistanceModifier
    : public Programmable_Effect<DynamicDistanceModifier_Info,
                                 DynamicDistanceModifier_Config,
                                 DynamicDistanceModifier_Vars> {
   public:
    E_DynamicDistanceModifier(AVS_Instance* avs);
    virtual ~E_DynamicDistanceModifier();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_DynamicDistanceModifier* clone() {
        return new E_DynamicDistanceModifier(*this);
    }

    int m_lastw, m_lasth;
    int* m_wmul;
    int* m_tab;
    double *var_d, *var_b;
    double max_d;
};
