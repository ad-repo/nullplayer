#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"

struct SetRenderMode_Config : public Effect_Config {
    int64_t blend = BLEND_REPLACE;
    int64_t adjustable_blend = 0;
    int64_t line_size = 1;
};

struct SetRenderMode_Info : public Effect_Info {
    static constexpr char const* group = "Misc";
    static constexpr char const* name = "Set Render Mode";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 40;
    static constexpr char const* legacy_ape_id = nullptr;

    static void callback(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 3;
    static constexpr Parameter parameters[num_parameters] = {
        P_SELECT(offsetof(SetRenderMode_Config, blend), "Blend", blend_modes),
        P_IRANGE(offsetof(SetRenderMode_Config, adjustable_blend),
                 "Adjustable Blend",
                 0,
                 255),
        P_IRANGE(offsetof(SetRenderMode_Config, line_size), "Line Size", 0, 255),
    };

    EFFECT_INFO_GETTERS;
};

class E_SetRenderMode
    : public Configurable_Effect<SetRenderMode_Info, SetRenderMode_Config> {
   public:
    E_SetRenderMode(AVS_Instance* avs) : Configurable_Effect(avs) {}
    virtual ~E_SetRenderMode() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_SetRenderMode* clone() { return new E_SetRenderMode(*this); }

   private:
    uint32_t pack_mode();
};
