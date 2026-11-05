#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"

struct UniqueTone_Config : public Effect_Config {
    uint64_t color = 0xffffff;
    int64_t blend_mode = 0;
    bool invert = false;
};

struct UniqueTone_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Unique Tone";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 38;
    static constexpr char const* legacy_ape_id = nullptr;

    static void on_color_change(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 3;
    static constexpr Parameter parameters[num_parameters] = {
        P_COLOR(offsetof(UniqueTone_Config, color), "Color", nullptr, on_color_change),
        P_SELECT(offsetof(UniqueTone_Config, blend_mode),
                 "Blend Mode",
                 blend_modes_simple),
        P_BOOL(offsetof(UniqueTone_Config, invert), "Invert"),
    };

    EFFECT_INFO_GETTERS;
};

class E_UniqueTone : public Configurable_Effect<UniqueTone_Info, UniqueTone_Config> {
   public:
    E_UniqueTone(AVS_Instance* avs);
    virtual ~E_UniqueTone() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void on_load();
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_UniqueTone* clone() { return new E_UniqueTone(*this); }

    void rebuild_table();
    int __inline depth_of(int32_t c);

    unsigned char table_r[256];
    unsigned char table_g[256];
    unsigned char table_b[256];
};
