#pragma once

#include "effect.h"
#include "effect_info.h"

enum Blur_Levels {
    BLUR_LIGHT = 0,
    BLUR_MEDIUM = 1,
    BLUR_HEAVY = 2,
};

enum Blur_Round {
    BLUR_ROUND_DOWN = 0,
    BLUR_ROUND_UP = 1,
};

struct Blur_Config : public Effect_Config {
    int64_t level = BLUR_MEDIUM;
    int64_t round = BLUR_ROUND_DOWN;
};

struct Blur_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Blur";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 6;
    static constexpr char* legacy_ape_id = NULL;

    static const char* const* blur_levels(int64_t* length_out) {
        *length_out = 4;
        static const char* const options[4] = {
            "None",
            "Medium",
            "Light",
            "Heavy",
        };
        return options;
    }

    static const char* const* round_modes(int64_t* length_out) {
        *length_out = 2;
        static const char* const options[2] = {
            "Down",
            "Up",
        };
        return options;
    }

    static constexpr uint32_t num_parameters = 2;
    static constexpr Parameter parameters[num_parameters] = {
        P_SELECT(offsetof(Blur_Config, level), "Blur", blur_levels),
        P_SELECT(offsetof(Blur_Config, round), "Round", round_modes),
    };

    EFFECT_INFO_GETTERS;
};

class E_Blur : public Configurable_Effect<Blur_Info, Blur_Config> {
   public:
    E_Blur(AVS_Instance* avs);
    virtual ~E_Blur();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Blur* clone() { return new E_Blur(*this); }

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
                           int h);  // return value is that of render() for fbstuff etc
};
