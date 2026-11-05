#pragma once

#include "effect.h"
#include "effect_info.h"

struct AddBorders_Config : public Effect_Config {
    uint64_t color = 0x000000;
    int64_t size = 1;
};

struct AddBorders_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Add Borders";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = -1;
    static constexpr char* legacy_ape_id = "Virtual Effect: Addborders";

    static constexpr uint32_t num_parameters = 2;
    static constexpr Parameter parameters[num_parameters] = {
        P_COLOR(offsetof(AddBorders_Config, color), "Color"),
        P_IRANGE(offsetof(AddBorders_Config, size), "Size", 1, 50),
    };

    EFFECT_INFO_GETTERS;
};

class E_AddBorders : public Configurable_Effect<AddBorders_Info, AddBorders_Config> {
   public:
    E_AddBorders(AVS_Instance* avs);
    virtual ~E_AddBorders();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_AddBorders* clone() { return new E_AddBorders(*this); }
};
