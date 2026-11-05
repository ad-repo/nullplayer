#pragma once

#include "effect.h"
#include "effect_info.h"

struct Invert_Config : public Effect_Config {};

struct Invert_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Invert";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 37;
    static constexpr char* legacy_ape_id = NULL;

    EFFECT_INFO_GETTERS_NO_PARAMETERS;
};

class E_Invert : public Configurable_Effect<Invert_Info, Invert_Config> {
   public:
    E_Invert(AVS_Instance* avs);
    virtual ~E_Invert();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Invert* clone() { return new E_Invert(*this); }
};
