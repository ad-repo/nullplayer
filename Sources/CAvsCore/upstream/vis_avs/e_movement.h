#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"
#include "effect_programmable.h"

#define LEGACY_SAVE_USE_CUSTOM_CODE    32767
// Ancient versions of AVS crash if effect is > 15. See `save_legacy()`.
#define LEGACY_ANCIENT_SAVE_MAX_EFFECT 15

struct Movement_Config : public Effect_Config {
    bool source_map = false;
    bool on_beat_toggle_source_map = false;
    bool wrap = false;
    int64_t blend_mode = BLEND_SIMPLE_REPLACE;
    bool bilinear = true;
    int64_t coordinates = COORDS_POLAR;
    std::string init;
    // Only init is used, but all 4 fields are required by `Programmable_Effect`.
    std::string frame;
    std::string beat;
    std::string point;
    int64_t effect = 0;
    bool use_custom_code = false;
};

struct Movement_Effect {
    const char* name;
    const char* code;
    Coordinates coordinates;
    bool wrap;
    bool use_eel;
};

struct Movement_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Movement";
    static constexpr char const* help =
        "Movement help goes here (send me some :)\r\n"
        "To use the custom table, modify r,d,x or y.\r\n"
        "Rect coords: x,y are in (-1..1). Otherwise: d is (0..1) and r is (0..2PI).\r\n"
        "You can also access 'sw' and 'sh' for screen dimensions in pixels"
        " (might be useful)\r\n";
    static constexpr int32_t legacy_id = 15;
    static constexpr char* legacy_ape_id = NULL;

    static constexpr int32_t num_effects = 23;
    static constexpr Movement_Effect effects[num_effects] = {
        /* 0 */
        {"Slight Fuzzify",
         "x = x + (rand(3) - 1) / (sw /2);\r\n"
         "y = y + (rand(3) - 1) / (sh /2);\r\n"
         "\r\n"
         "// remove the next two lines if you don't need the exact\r\n"
         "// legacy top-/bottom edge behavior\r\n"
         "if(below(y, -1), exec2(assign(x, -1), assign(y, -1)), 0);\r\n"
         "if(above(y, 1-(2/sh)), exec2(assign(x, 1), assign(y, 1)), 0);\r\n",
         COORDS_CARTESIAN,
         false,
         false},
        /* 1 */
        {"Shift Rotate Left", "x=x+(1/32)-(1/sw);\r\n", COORDS_CARTESIAN, true, false},
        /* 2 */
        {"Big Swirl Out",
         "r = r + (0.1 - (0.2 * d));\r\n"
         "d = d * 0.96;\r\n",
         COORDS_POLAR,
         false,
         false},
        /* 3 */
        {"Medium Swirl",
         "d = d * (0.99 * (1.0 - sin(r-$PI*0.5) / 32.0));\r\n"
         "r = r + (0.03 * sin(d * $PI * 4));\r\n",
         COORDS_POLAR,
         false,
         false},
        /* 4 */
        {"Sunburster",
         "d = d * (0.94 + (cos((r-$PI*0.5) * 32.0) * 0.06));\r\n",
         COORDS_POLAR,
         false,
         false},
        /* 5 */
        {"Swirl To Center",
         "d = d * (1.01 + (cos((r-$PI*0.5) * 4) * 0.04));\r\n"
         "r = r + (0.03 * sin(d * $PI * 4));\r\n",
         COORDS_POLAR,
         false,
         false},
        /* 6 */
        {"Blocky, Partial Out",
         "x_src = x_px;\r\n"
         "y_src = y_px;\r\n"
         "\r\n"
         "w_half = floor(sw / 2);\r\n"
         "h_half = floor(sh / 2);\r\n"
         "keep = bor(x_px & 2, y_px & 2);\r\n"
         "x_src = if(keep, x_src, (x_px - (x_px&1) - w_half) * 7 / 8 + w_half);\r\n"
         "y_src = if(keep, y_src, (y_px - (y_px&1) - h_half) * 7 / 8 + h_half);\r\n"
         "\r\n"
         "// Replace the two lines above with the following overengineered mess\r\n"
         "// if you need a pixel-for-pixel match with the builtin effect.\r\n"
         "// Note that a few specific resolutions still produce tiny differences.\r\n"
         "//\r\n"
         "// x_src = if(keep, x_src,\r\n"
         "//             floor(((x_px - (x_px&1) - w_half) * 7) / 8) + w_half\r\n"
         "//             + if (below(x, 0),\r\n"
         "//                   if(above(sw % 8, 1),\r\n"
         "//                       1,\r\n"
         "//                       if(sw % 16,\r\n"
         "//                           bnot(x_px & 4),\r\n"
         "//                           above(x_px & 4, 0))), 0));\r\n"
         "// y_src = if(keep, y_src,\r\n"
         "//            floor(((y_px - (y_px&1) - h_half) * 7) / 8) + h_half\r\n"
         "//            + if (below(y, 0),\r\n"
         "//                  if(above(sh % 8, 1),\r\n"
         "//                      1,\r\n"
         "//                      if(sh % 16,\r\n"
         "//                          bnot(y_px & 4),\r\n"
         "//                          above(y_px & 4, 0))), 0));\r\n"
         "\r\n"
         "x = (x_src / w_half - 1);\r\n"
         "y = (y_src / h_half - 1);\r\n"
         "\r\n"
         "// Iterate x and y in pixel coordinates\r\n"
         "x_px = x_px + 1;\r\n"
         "if (below(x_px, sw), 0, exec2(assign(x_px, 0), assign(y_px, y_px + 1)));\r\n",
         COORDS_CARTESIAN,
         false,
         false},
        /* 7 */
        {"Swirling Around Both Ways At Once",
         "r = r + (0.1 * sin(d * $PI * 5));\r\n",
         COORDS_POLAR,
         false,
         false},
        /* 8 */
        {"Bubbling Outward",
         "t = sin(d * $PI);\r\n"
         "d = d - (8*t*t*t*t*t)/sqrt((sw*sw+sh*sh)/4);\r\n",
         COORDS_POLAR,
         false,
         false},
        /* 9 */
        {"Bubbling Outward With Swirl",
         "t = sin(d * $PI);\r\n"
         "d = d - (8*t*t*t*t*t)/sqrt((sw*sw+sh*sh)/4);\r\n"
         "t=cos(d*$PI/2.0);\r\n"
         "r= r + 0.1*t*t*t;\r\n",
         COORDS_POLAR,
         false,
         false},
        /* 10 */
        {"5 Pointed Distro",
         "d = d * (0.95 + (cos(((r-$PI*0.5) * 5.0) - ($PI / 2.50)) * 0.03));\r\n",
         COORDS_POLAR,
         false,
         false},
        /* 11 */
        {"Tunneling",
         "r = r + 0.04;\r\n"
         "d = d * (0.96 + cos(d * $PI) * 0.05);\r\n",
         COORDS_POLAR,
         false,
         false},
        /* 12 */
        {"Bleedin'",
         "t = cos(d * $PI);\r\n"
         "r = r + (0.07 * t);\r\n"
         "d = d * (0.98 + t * 0.10);\r\n",
         COORDS_POLAR,
         false,
         false},
        /* 13 */
        {"Shifted Big Swirl Out",
         "w_half = floor(sw / 2);\r\n"
         "h_half = floor(sh / 2);\r\n"
         "d_max = sqrt(sw*sw + sh*sh) / 4;\r\n"
         "x_src = x_px - w_half;\r\n"
         "y_src = y_px - h_half;\r\n"
         "d = sqrt(x_src*x_src + y_src*y_src);\r\n"
         "r = atan2(y_src, x_src);\r\n"
         "r = r + 0.1 - 0.1 * d / d_max;\r\n"
         "d = d*0.96;\r\n"
         "x = cos(r) * d / w_half + 8/128;\r\n"
         "y = sin(r) * d / h_half;\r\n"
         "x_px = x_px + 1;\r\n"
         "if (below(x_px, sw), 0, exec2(assign(x_px, 0), assign(y_px, y_px + 1)));\r\n",
         COORDS_CARTESIAN,
         false,
         false},
        /* 14 */
        {"Psychotic Beaming Outward", "d = 0.15;\r\n", COORDS_POLAR, false, false},
        /* 15 */
        {"Cosine Radial 3-way",
         "r = cos((r - $PI/2) * 3) + $PI/2;\r\n"
         "// much simpler, but slightly different than the builtin:\r\n"
         "// r = cos(r * 3);",
         COORDS_POLAR,
         false,
         false},
        /* 16 */
        {"Spinny Tube",
         "d = d * (1 - ((d - .35) * .5));\r\n"
         "r = r + .1;\r\n",
         COORDS_POLAR,
         false,
         false},
        /* 17 */
        {"Radial Swirlies",
         "d = d * (1 - (sin((r-$PI*0.5) * 7) * .03));\r\n"
         "r = r + (cos(d * 12) * .03);\r\n",
         COORDS_POLAR,
         false,
         true},
        /* 18 */
        {"Swill",
         "d = d * (1 - (sin((r - $PI*0.5) * 12) * .05));\r\n"
         "r = r + (cos(d * 18) * .05);\r\n"
         "d = d * (1-((d - .4) * .03));\r\n"
         "r = r + ((d - .4) * .13);\r\n",
         COORDS_POLAR,
         false,
         true},
        /* 19 */
        {"Gridley",
         "x = x + (cos(y * 18) * .02);\r\n"
         "y = y + (sin(x * 14) * .03);\r\n",
         COORDS_CARTESIAN,
         false,
         true},
        /* 20 */
        {"Grapevine",
         "x = x + (cos(abs(y-.5) * 8) * .02);\r\n"
         "y = y + (sin(abs(x-.5) * 8) * .05);\r\n"
         "x = x * .95;\r\n"
         "y = y * .95;\r\n",
         COORDS_CARTESIAN,
         false,
         true},
        /* 21 */
        {"Quadrant",
         "y = y * ( 1 + (sin(r + $PI/2) * .3) );\r\n"
         "x = x * ( 1 + (cos(r + $PI/2) * .3) );\r\n"
         "x = x * .995;\r\n"
         "y = y * .995;\r\n",
         COORDS_CARTESIAN,
         false,
         true},
        /* 22 */
        {"6-way Kaleida", "y = (r*6)/($PI); x = d;\r\n", COORDS_CARTESIAN, true, true},
    };

    static const char* const* blend_modes(int64_t* length_out) {
        *length_out = 2;
        static const char* const options[2] = {
            "Replace",
            "50/50",
        };
        return options;
    }

    static const char* const* coordinates(int64_t* length_out) {
        *length_out = 2;
        static const char* const options[2] = {
            "Polar",
            "Cartesian",
        };
        return options;
    }

    static const char* const* effect_names(int64_t* length_out) {
        *length_out = num_effects;
        static const char* const options[num_effects] = {
            effects[0].name,  effects[1].name,  effects[2].name,  effects[3].name,
            effects[4].name,  effects[5].name,  effects[6].name,  effects[7].name,
            effects[8].name,  effects[9].name,  effects[10].name, effects[11].name,
            effects[12].name, effects[13].name, effects[14].name, effects[15].name,
            effects[16].name, effects[17].name, effects[18].name, effects[19].name,
            effects[20].name, effects[21].name, effects[22].name,
        };
        return options;
    }

    static void recreate_tab(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void recompile(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void load_effect(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 10;
    static constexpr Parameter parameters[num_parameters] = {
        P_BOOL(offsetof(Movement_Config, source_map), "Source Map", NULL, recreate_tab),
        P_BOOL(offsetof(Movement_Config, on_beat_toggle_source_map),
               "On-Beat Toggle Source Map",
               NULL,
               recreate_tab),
        P_BOOL(offsetof(Movement_Config, wrap), "Wrap", NULL, recreate_tab),
        P_SELECT(offsetof(Movement_Config, blend_mode),
                 "Blend Mode",
                 blend_modes,
                 NULL,
                 recreate_tab),
        P_BOOL(offsetof(Movement_Config, bilinear), "Bilinear", NULL, recreate_tab),
        P_SELECT(offsetof(Movement_Config, coordinates),
                 "Coordinates",
                 coordinates,
                 NULL,
                 recreate_tab),
        P_STRING(offsetof(Movement_Config, init), "Code", NULL, recompile),
        P_SELECT(offsetof(Movement_Config, effect), "Effect", effect_names),
        P_BOOL(offsetof(Movement_Config, use_custom_code), "Use Custom Code"),
        P_ACTION("Load Effect", load_effect, "Load the selected effect"),
    };

    EFFECT_INFO_GETTERS;
};

struct Movement_Vars : public Variables {
    double* d;
    double* r;
    double* x;
    double* y;
    double* w;
    double* h;

    virtual void register_(void*);

    virtual void init(int, int, int, va_list);
};

class E_Movement
    : public Programmable_Effect<Movement_Info, Movement_Config, Movement_Vars> {
   public:
    E_Movement(AVS_Instance* avs);
    virtual ~E_Movement();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Movement* clone() { return new E_Movement(*this); }

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

    void regenerate_transform_table(int effect, char visdata[2][2][576], int w, int h);

    struct Transform {
        uint32_t* table = NULL;
        int w = 0;
        int h = 0;
        bool bilinear = false;
        bool need_regen = true;
        lock_t* lock;

        Transform();
        ~Transform();
    };
    Transform transform;
    bool use_eel = true;
};
