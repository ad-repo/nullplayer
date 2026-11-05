#pragma once

#include "effect.h"
#include "effect_info.h"

enum Multiplier_Factor {
    MULTIPLY_INF_ROOT = 0,
    MULTIPLY_X8 = 1,
    MULTIPLY_X4 = 2,
    MULTIPLY_X2 = 3,
    MULTIPLY_X05 = 4,
    MULTIPLY_X025 = 5,
    MULTIPLY_X0125 = 6,
    MULTIPLY_INF_SQUARE = 7,
};

struct Multiplier_Config : public Effect_Config {
    int64_t multiply = MULTIPLY_X2;
};

struct Multiplier_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Multiplier";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = -1;
    static constexpr char* legacy_ape_id = "Multiplier";

    static const char* const* multiply_modes(int64_t* length_out) {
        *length_out = 8;
        static const char* const options[8] = {
            "Infinite Root",
            "8",
            "4",
            "2",
            "0.5",
            "0.25",
            "0.125",
            "Infinite Square",
        };
        return options;
    }

    static constexpr uint32_t num_parameters = 1;
    static constexpr Parameter parameters[num_parameters] = {
        P_SELECT(offsetof(Multiplier_Config, multiply), "Multiply", multiply_modes),
    };

    EFFECT_INFO_GETTERS;
};

class E_Multiplier : public Configurable_Effect<Multiplier_Info, Multiplier_Config> {
   public:
    E_Multiplier(AVS_Instance* avs);
    virtual ~E_Multiplier();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Multiplier* clone() { return new E_Multiplier(*this); }
};
