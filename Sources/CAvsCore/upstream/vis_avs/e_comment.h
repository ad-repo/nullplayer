#pragma once

#include "effect.h"
#include "effect_info.h"

struct Comment_Info : public Effect_Info {
    static constexpr char const* group = "Misc";
    static constexpr char const* name = "Comment";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 21;
    static constexpr char* legacy_ape_id = NULL;

    EFFECT_INFO_GETTERS_NO_PARAMETERS;
};

class E_Comment : public Configurable_Effect<Comment_Info, Effect_Config> {
   public:
    E_Comment(AVS_Instance* avs);
    virtual ~E_Comment();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Comment* clone() { return new E_Comment(*this); }
};
