#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"

struct Brightness_Config : public Effect_Config {
    int64_t blend_mode = BLEND_SIMPLE_5050;
    int64_t red = 0;
    int64_t green = 0;
    int64_t blue = 0;
    bool separate = false;
    bool exclude = false;
    uint64_t exclude_color = 0x000000;
    int64_t distance = 16;
};

struct Brightness_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Brightness";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 22;
    static constexpr char* legacy_ape_id = NULL;

    static void on_color_change(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void on_separate_toggle(Effect*,
                                   const Parameter*,
                                   const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 8;
    static constexpr Parameter parameters[num_parameters] = {
        P_SELECT(offsetof(Brightness_Config, blend_mode),
                 "Blend Mode",
                 blend_modes_simple),
        P_IRANGE(offsetof(Brightness_Config, red),
                 "Red",
                 -4096,
                 4096,
                 NULL,
                 on_color_change),
        P_IRANGE(offsetof(Brightness_Config, green),
                 "Green",
                 -4096,
                 4096,
                 NULL,
                 on_color_change),
        P_IRANGE(offsetof(Brightness_Config, blue),
                 "Blue",
                 -4096,
                 4096,
                 NULL,
                 on_color_change),
        P_BOOL(offsetof(Brightness_Config, separate),
               "Separate",
               NULL,
               on_separate_toggle),
        P_BOOL(offsetof(Brightness_Config, exclude), "Exclude Color Range"),
        P_COLOR(offsetof(Brightness_Config, exclude_color), "Exclusion Base Color"),
        P_IRANGE(offsetof(Brightness_Config, distance), "Exclusion Distance", 0, 255),
    };

    EFFECT_INFO_GETTERS;
};

class E_Brightness : public Configurable_Effect<Brightness_Info, Brightness_Config> {
   public:
    E_Brightness(AVS_Instance* avs);
    virtual ~E_Brightness();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void on_load();
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Brightness* clone() { return new E_Brightness(*this); }

    virtual bool can_multithread() { return true; }
    virtual int smp_begin(int max_threads,
                          char visdata[2][2][576],
                          int is_beat,
                          int* framebuffer,
                          int* fbout,
                          int w,
                          int h);
    virtual void smp_render(int this_thread,
                            int max_threads,
                            char visdata[2][2][576],
                            int is_beat,
                            int* framebuffer,
                            int* fbout,
                            int w,
                            int h);
    virtual int smp_finish(char visdata[2][2][576],
                           int is_beat,
                           int* framebuffer,
                           int* fbout,
                           int w,
                           int h);

    bool need_tab_init;
    int32_t green_tab[256];
    int32_t red_tab[256];
    int32_t blue_tab[256];
};
