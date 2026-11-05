#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"
#include "effect_programmable.h"

struct Bump_Config : public Effect_Config {
    std::string init = "t=0;";
    std::string frame = "x=0.5+cos(t)*0.3;\r\ny=0.5+sin(t)*0.3;\r\nt=t+0.1;";
    std::string beat = "";
    std::string point;  // unused, but required by Programmable_Effect template
    int64_t depth = 30;
    bool on_beat = false;
    int64_t on_beat_duration = 15;
    int64_t on_beat_depth = 100;
    int64_t blend_mode = BLEND_SIMPLE_REPLACE;
    bool show_light_pos = false;
    bool invert_depth = false;
    int64_t depth_buffer = 0;
};

struct Bump_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Bump";
    static constexpr char const* help =
        "How to use the custom light position evaluator:\r\n"
        " * Init code will be executed each time the window size is changed or when "
        "the effect loads\r\n"
        " * Frame code is executed before rendering a new frame\r\n"
        " * Beat code is executed when a beat is detected\r\n"
        "\r\n"
        "Predefined variables:\r\n"
        " x : Light x position, ranges from 0 (left) to 1 (right) (0.5 = center)\r\n"
        " y : Light y position, ranges from 0 (top) to 1 (bottom) (0.5 = center)\r\n"
        " isBeat : 1 if no beat, -1 if beat (weird, but old)\r\n"
        " isLBeat: same as isBeat but persists according to 'shorter/longer' settings "
        "(usable only with OnBeat checked)\r\n"
        " bi: Bump intensity, ranges  from 0 (flat) to 1 (max specified bump, "
        "default)\r\n"
        " You may also use temporary variables accross code segments.\r\n"
        "\r\n"
        "Some examples:\r\n"
        "   Circular move\r\n"
        "      Init : t=0\r\n"
        "      Frame: x=0.5+cos(t)*0.3; y=0.5+sin(t)*0.3; t=t+0.1;\r\n"
        "   Nice motion:\r\n"
        "      Init : t=0;u=0\r\n"
        "      Frame: x=0.5+cos(t)*0.3; y=0.5+cos(u)*0.3; t=t+0.1; u=u+0.012;\r\n";
    static constexpr int32_t legacy_id = 29;
    static constexpr char* legacy_ape_id = NULL;

    static void recompile(Effect*, const Parameter*, const std::vector<int64_t>&);
    static constexpr uint32_t num_parameters = 11;
    static constexpr Parameter parameters[num_parameters] = {
        P_STRING(offsetof(Bump_Config, init), "Init", NULL, recompile),
        P_STRING(offsetof(Bump_Config, frame), "Frame", NULL, recompile),
        P_STRING(offsetof(Bump_Config, beat), "Beat", NULL, recompile),
        P_IRANGE(offsetof(Bump_Config, depth), "Depth", 1, 100),
        P_BOOL(offsetof(Bump_Config, on_beat), "On Beat"),
        P_IRANGE(offsetof(Bump_Config, on_beat_duration), "On Beat Duration", 0, 100),
        P_IRANGE(offsetof(Bump_Config, on_beat_depth), "On Beat Depth", 1, 100),
        P_SELECT(offsetof(Bump_Config, blend_mode), "Blend Mode", blend_modes_simple),
        P_BOOL(offsetof(Bump_Config, show_light_pos), "Show Light Position"),
        P_BOOL(offsetof(Bump_Config, invert_depth), "Invert Depth"),
        P_IRANGE(offsetof(Bump_Config, depth_buffer), "Depth Buffer", 0, 8),
    };

    EFFECT_INFO_GETTERS;
};

struct Bump_Vars : public Variables {
    double* bi;
    double* x;
    double* y;
    double* is_beat;
    double* is_long_beat;

    virtual void register_(void*);
    virtual void init(int, int, int, va_list);
};

class E_Bump : public Programmable_Effect<Bump_Info, Bump_Config, Bump_Vars> {
   public:
    E_Bump(AVS_Instance* avs);
    virtual ~E_Bump();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Bump* clone() { return new E_Bump(*this); }

    int cur_depth;
    int on_beat_fadeout;
    bool use_old_xy_range;
};
