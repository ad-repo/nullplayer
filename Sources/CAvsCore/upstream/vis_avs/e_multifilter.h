#pragma once

#include "effect.h"
#include "effect_info.h"

enum MultiFilterEffect {
    MULTIFILTER_CHROME = 0,
    MULTIFILTER_DOUBLE_CHROME = 1,
    MULTIFILTER_TRIPLE_CHROME = 2,
    MULTIFILTER_INFROOT_BORDERCONVO = 3,
};

struct MultiFilter_Config : public Effect_Config {
    int64_t effect = MULTIFILTER_CHROME;
    bool toggle_on_beat = false;
};

struct MultiFilter_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Multi Filter";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = -1;
    static constexpr char const* legacy_ape_id = "Jheriko : MULTIFILTER";

    static const char* const* effects(int64_t* length_out) {
        *length_out = 4;
        static const char* const options[4] = {
            "Chrome",
            "Double Chrome",
            "Triple Chrome",
            "Infinite Root Multiplier + Small Border Convolution",
        };
        return options;
    }

    static constexpr uint32_t num_parameters = 2;
    static constexpr Parameter parameters[num_parameters] = {
        P_SELECT(offsetof(MultiFilter_Config, effect), "Effect", effects),
        P_BOOL(offsetof(MultiFilter_Config, toggle_on_beat), "Toggle On Beat"),
    };

    EFFECT_INFO_GETTERS;
};

class E_MultiFilter : public Configurable_Effect<MultiFilter_Info, MultiFilter_Config> {
   public:
    E_MultiFilter(AVS_Instance* avs);
    virtual ~E_MultiFilter() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_MultiFilter* clone() { return new E_MultiFilter(*this); }

   private:
    void chrome(int* framebuffer, unsigned int fb_length);
    void chrome_sse2(int* framebuffer, unsigned int fb_length);
    static void infroot_borderconvo(int* framebuffer, int w, int h);

    bool toggle_state;
};
