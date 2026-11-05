#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"

struct Grain_Config : public Effect_Config {
    int64_t blend_mode = BLEND_SIMPLE_REPLACE;
    int64_t amount = 100;
    bool static_ = false;
};

struct Grain_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Grain";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 24;
    static constexpr char* legacy_ape_id = NULL;

    static const char* const* blend_modes(int64_t* length_out) {
        *length_out = 3;
        static const char* const options[3] = {
            "Replace",
            "50/50",
            "Additive",
        };
        return options;
    }

    static constexpr uint32_t num_parameters = 3;
    static constexpr Parameter parameters[num_parameters] = {
        P_SELECT(offsetof(Grain_Config, blend_mode), "Blend Mode", blend_modes),
        P_IRANGE(offsetof(Grain_Config, amount), "Amount", 0, 100),
        P_BOOL(offsetof(Grain_Config, static_), "Static"),
    };

    EFFECT_INFO_GETTERS;
};

class E_Grain : public Configurable_Effect<Grain_Info, Grain_Config> {
   public:
    E_Grain(AVS_Instance* avs);
    virtual ~E_Grain();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Grain* clone() { return new E_Grain(*this); }

    unsigned char inline fastrandbyte(void);
    void reinit(int w, int h);

    int old_x;
    int old_y;
    unsigned char* depth_buffer;
    unsigned char randtab[491];
    int randtab_pos;
};
