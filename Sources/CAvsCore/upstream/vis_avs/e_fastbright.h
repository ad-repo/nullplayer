#pragma once

#include "effect.h"
#include "effect_info.h"

enum FastBright_Multiply {
    FASTBRIGHT_MULTIPLY_DOUBLE = 0,
    FASTBRIGHT_MULTIPLY_HALF = 1,
};

struct FastBright_Config : public Effect_Config {
    int64_t multiply = FASTBRIGHT_MULTIPLY_DOUBLE;
};

struct FastBright_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Fast Brightness";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 44;
    static constexpr char* legacy_ape_id = NULL;

    static const char* const* multipliers(int64_t* length_out) {
        *length_out = 2;
        static const char* const options[3] = {"2", "0.5"};
        return options;
    }

    static constexpr uint32_t num_parameters = 1;
    static constexpr Parameter parameters[num_parameters] = {
        P_SELECT(offsetof(FastBright_Config, multiply), "Multiply", multipliers),
    };

    EFFECT_INFO_GETTERS;
};

class E_FastBright : public Configurable_Effect<FastBright_Info, FastBright_Config> {
   public:
    E_FastBright(AVS_Instance* avs);
    virtual ~E_FastBright();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_FastBright* clone() { return new E_FastBright(*this); }

#ifdef NO_MMX
    int tab[3][256];
#endif
};
