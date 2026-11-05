#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"
#include "effect_programmable.h"

struct DynamicMovement_Config : public Effect_Config {
    std::string init = "";
    std::string frame = "";
    std::string beat = "";
    std::string point = "";
    bool bilinear = false;
    int64_t coordinates = COORDS_POLAR;
    int64_t grid_w = 16;
    int64_t grid_h = 16;
    bool blend = false;
    bool wrap = false;
    int64_t buffer = 0;
    bool alpha_only = false;
    int64_t example = 0;
};

struct DynamicMovement_Example {
    const char* name;
    const char* init;
    const char* frame;
    const char* beat;
    const char* point;
    bool rectangular_coordinates;
    bool wrap;
    int grid_w;
    int grid_h;
};

struct DynamicMovement_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Dynamic Movement";
    static constexpr char const* help =
        "Dynamic movement help goes here (send me some :)";
    static constexpr int32_t legacy_id = 43;
    static constexpr char* legacy_ape_id = NULL;

    static constexpr int32_t num_examples = 8;
    static constexpr DynamicMovement_Example examples[num_examples] = {
        {
            "Random Rotate",
            "",
            "",
            "dr = (rand(100) / 100) * $PI;\r\nd = d * .95;",
            "r = r + dr;",
            false,
            true,
            2,
            2,
        },
        {
            "Random Direction",
            "speed=.05;dr = (rand(200) / 100) * $PI;",
            "dx = cos(dr) * speed;\r\ndy = sin(dr) * speed;",
            "dr = (rand(200) / 100) * $PI;",
            "x = x + dx;\r\ny = y + dy;",
            true,
            true,
            2,
            2,
        },
        {
            "In and Out",
            "speed=.2;c=0;",
            "",
            "c = c + ($PI/2);\r\ndd = 1 - (sin(c) * speed);",
            "d = d * dd;",
            false,
            true,
            2,
            2,
        },
        {
            "Unspun Kaleida",
            "c=200;f=0;dt=0;dl=0;beatdiv=8",
            "f = f + 1;\r\nt = ((f * $pi * 2)/c)/beatdiv;\r\ndt = dl + t;\r\n"
            "dr = 4+(cos(dt)*2);",
            "c=f;f=0;dl=dt",
            "r=cos(r*dr);",
            false,
            true,
            33,
            33,
        },
        {
            "Roiling Gridley",
            "c=200;f=0;dt=0;dl=0;beatdiv=8",
            "f = f + 1;\r\nt = ((f * $pi * 2)/c)/beatdiv;\r\ndt = dl + t;\r\n"
            "dx = 14+(cos(dt)*8);\r\ndy = 10+(sin(dt*2)*4);",
            "c=f;f=0;dl=dt",
            "x=x+(sin(y*dx) * .03);\r\ny=y-(cos(x*dy) * .03);",
            true,
            true,
            32,
            32,
        },
        {
            "6-Way Outswirl",
            "c=200;f=0;dt=0;dl=0;beatdiv=8",
            "f = f + 1;\r\nt = ((f * $pi * 2)/c)/beatdiv;\r\ndt = dl + t;\r\n"
            "dr = 18+(cos(dt)*12);",
            "c=f;f=0;dl=dt",
            "d=d*(1+(cos(r*6) * .05));\r\nr=r-(sin(d*dr) * .05);\r\nd = d * .98;",
            false,
            false,
            32,
            32,
        },
        {
            "Wavy",
            "c=200;f=0;dx=0;dl=0;beatdiv=16;speed=.05",
            "f = f + 1;\r\nt = ( (f * 2 * 3.1415) / c ) / beatdiv;\r\ndx = dl + t;",
            "c = f;\r\nf = 0;\r\ndl = dx;",
            "y = y + ((sin((x+dx) * $PI))*speed);\r\nx = x + .025",
            true,
            true,
            6,
            6,
        },
        {
            "Smooth Rotoblitter",
            "c=200;f=0;dt=0;dl=0;beatdiv=4;speed=.15",
            "f = f + 1;\r\nt = ((f * $pi * 2)/c)/beatdiv;\r\ndt = dl + t;\r\n"
            "dr = cos(dt)*speed*2;\r\ndd = 1 - (sin(dt)*speed);",
            "c=f;f=0;dl=dt",
            "r = r + dr;\r\nd = d * dd;",
            false,
            true,
            2,
            2,
        },
    };

    static const char* const* coords(int64_t* length_out) {
        *length_out = 2;
        static const char* const options[2] = {
            "Polar",
            "Cartesian",
        };
        return options;
    }

    static const char* const* example_names(int64_t* length_out) {
        *length_out = 8;
        static const char* const options[8] = {
            examples[0].name,
            examples[1].name,
            examples[2].name,
            examples[3].name,
            examples[4].name,
            examples[5].name,
            examples[6].name,
            examples[7].name,
        };
        return options;
    }

    static void recompile(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void load_example(Effect*, const Parameter*, const std::vector<int64_t>&);
    static constexpr uint32_t num_parameters = 14;
    static constexpr Parameter parameters[num_parameters] = {
        P_STRING(offsetof(DynamicMovement_Config, init), "Init", NULL, recompile),
        P_STRING(offsetof(DynamicMovement_Config, frame), "Frame", NULL, recompile),
        P_STRING(offsetof(DynamicMovement_Config, beat), "Beat", NULL, recompile),
        P_STRING(offsetof(DynamicMovement_Config, point), "Point", NULL, recompile),
        P_BOOL(offsetof(DynamicMovement_Config, bilinear), "Bilinear"),
        P_SELECT(offsetof(DynamicMovement_Config, coordinates), "Coordinates", coords),
        P_IRANGE(offsetof(DynamicMovement_Config, grid_w), "Grid Width", 1, INT64_MAX),
        P_IRANGE(offsetof(DynamicMovement_Config, grid_h), "Grid Height", 1, INT64_MAX),
        P_BOOL(offsetof(DynamicMovement_Config, blend), "Blend"),
        P_BOOL(offsetof(DynamicMovement_Config, wrap), "Wrap"),
        P_IRANGE(offsetof(DynamicMovement_Config, buffer), "Buffer", 0, 8),
        P_BOOL(offsetof(DynamicMovement_Config, alpha_only), "Alpha Only"),
        P_SELECT_X(offsetof(DynamicMovement_Config, example), "Example", example_names),
        P_ACTION("Load Example", load_example, "Load the selected example code"),
    };

    EFFECT_INFO_GETTERS;
};

struct DynamicMovement_Vars : public Variables {
    double* b;
    double* d;
    double* r;
    double* x;
    double* y;
    double* w;
    double* h;
    double* alpha;

    virtual void register_(void*);
    virtual void init(int, int, int, va_list);
};

class E_DynamicMovement : public Programmable_Effect<DynamicMovement_Info,
                                                     DynamicMovement_Config,
                                                     DynamicMovement_Vars> {
   public:
    E_DynamicMovement(AVS_Instance* avs);
    virtual ~E_DynamicMovement();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_DynamicMovement* clone() { return new E_DynamicMovement(*this); }

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

    int last_w, last_h;
    int last_x_res, last_y_res;
    int* w_mul;
    int* tab;

    bool bilinear;
    int64_t coordinates;
    bool blend;
    bool wrap;
    bool alpha_only;
    int w_adj;
    int h_adj;
    int XRES;
    int YRES;
};
