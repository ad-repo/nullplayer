#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"
#include "effect_programmable.h"
#include "pixel_format.h"

#include "../platform.h"

#include <vector>

#define TEXER_II_VERSION_V2_81D 0
#define TEXER_II_VERSION_V2_81D_UPGRADE_HELP \
    "Saved version wraps x/y only once. Upgrade to wrap around forever."
#define TEXER_II_VERSION_CURRENT 1

#define TEXER_II_DEFAULT_IMAGE_STRING "(default image)"

struct Texer2_Config : public Effect_Config {
    int64_t version = TEXER_II_VERSION_CURRENT;
    std::string image;
    bool resize = false;
    bool wrap = false;
    bool colorize = true;
    std::string init;
    std::string frame;
    std::string beat;
    std::string point;
    int64_t example = 0;
    Texer2_Config();  // Fill with first example
};

struct Texer2_Example {
    const char* name;
    const char* init;
    const char* frame;
    const char* beat;
    const char* point;
    const bool resize;
    const bool wrap;
    const bool colorize;
};

struct Texer2_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Texer II";
    static constexpr char const* help =
        "Texer II is a rendering component that draws what is commonly known as "
        "particles.\r\n"
        "At specified positions on screen, a copy of the source image is placed and "
        "blended in various ways.\r\n"
        "\r\n"
        "\r\n"
        "The usage is similar to that of a dot-superscope.\r\n"
        "The following variables are available:\r\n"
        "\r\n"
        "* n: Contains the amount of particles to draw. Usually set in the init code "
        "or the frame code.\r\n"
        "\r\n"
        "* w,h: Contain the width and height of the window in pixels.\r\n"
        "\r\n"
        "* i: Contains the percentage of progress of particles drawn. Varies from 0 "
        "(first particle) to 1 (last particle).\r\n"
        "\r\n"
        "* x,y: Specify the position of the center of the particle. Range -1 to 1.\r\n"
        "\r\n"
        "* v: Contains the i'th sample of the oscilloscope waveform. Use getspec(...) "
        "or getosc(...) for other data (check the function reference for their "
        "usage).\r\n"
        "\r\n"
        "* b: Contains 1 if a beat is occuring, 0 otherwise.\r\n"
        "\r\n"
        "* iw, ih: Contain the width and height of the Texer bitmap in pixels\r\n"
        "\r\n"
        "* sizex, sizey: Contain the relative horizontal and vertical size of the "
        "current particle. Use 1.0 for original size. Negative values cause the image "
        "to be mirrored or flipped. Changing size only works if Resizing is on; "
        "mirroring/flipping works in all modes.\r\n"
        "\r\n"
        "* red, green, blue: Set the color of the current particle in terms of its "
        "red, green and blue component. Only works if color filtering is on.\r\n"
        "\r\n"
        "* skip: Default is 0. If set to 1, indicates that the current particle should "
        "not be drawn.\r\n"
        "\r\n"
        "\r\n"
        "\r\n"
        "The options available are:\r\n"
        "\r\n"
        "* Color filtering: blends the image multiplicatively with the color specified "
        "by the red, green and blue variables.\r\n"
        "\r\n"
        "* Resizing: resizes the image according to the variables sizex and sizey.\r\n"
        "\r\n"
        "* Wrap around: wraps any image data that falls off the border of the screen "
        "around to the other side. Useful for making tiled patterns.\r\n"
        "\r\n"
        "\r\n"
        "\r\n"
        "Texer II supports the standard AVS blend modes. Just place a Misc / Set "
        "Render Mode before the Texer II and choose the appropriate setting. You will "
        "most likely use Additive or Maximum blend.\r\n"
        "\r\n"
        "Texer II was written by Steven Wittens. Thanks to everyone at the Winamp.com "
        "forums for feedback, especially Deamon and gaekwad2 for providing the "
        "examples and Tuggummi for providing the default image.\r\n";

    static constexpr int32_t legacy_id = -1;
    static constexpr char* legacy_ape_id = "Acko.net: Texer II";

    static constexpr int32_t num_examples = 4;
    static constexpr Texer2_Example examples[num_examples] = {
        {
            "Colored Oscilloscope",
            "// This example needs Maximum render mode\r\n"
            "n=300;",
            "",
            "",
            "x=(i*2-1)*2;y=v;\r\n"
            "red=1-y*2;green=abs(y)*2;blue=y*2-1;",
            false,
            false,
            true,
        },
        {
            "Flummy Spectrum",
            "// This example needs Maximum render mode",
            "n=w/20+1;",
            "",
            "x=i*1.8-.9;\r\n"
            "y=0;\r\n"
            "vol=1.001-getspec(abs(x)*.5,.05,0)*min(1,abs(x)+.5)*2;\r\n"
            "sizex=vol;sizey=(1/vol)*2;\r\n"
            "j=abs(x);red=1-j;green=1-abs(.5-j);blue=j",
            true,
            false,
            true,
        },
        {
            "Beat-responsive Circle",
            "// This example needs Maximum render mode\r\n"
            "n=30;newradius=.5;",
            "rotation=rotation+step;step=step*.9;\r\n"
            "radius=radius*.9+newradius*.1;\r\n"
            "point=0;\r\n"
            "aspect=h/w;",
            "step=.05;\r\n"
            "newradius=rand(100)*.005+.5;",
            "angle=rotation+point/n*$pi*2;\r\n"
            "x=cos(angle)*radius*aspect;y=sin(angle)*radius;\r\n"
            "red=sin(i*$pi*2)*.5+.5;green=1-red;blue=.5;\r\n"
            "point=point+1;",
            false,
            false,
            true,
        },
        {
            "3D Beat Rings",
            "// This shows how to use texer for 3D particles\r\n"
            "// Additive or maximum blend mode should be used\r\n"
            "xr=(rand(50)/500)-0.05;\r\n"
            "yr=(rand(50)/500)-0.05;\r\n"
            "zr=(rand(50)/500)-0.05;",
            "// Rotation along x/y/z axes\r\n"
            "xt=xt+xr;yt=yt+yr;zt=zt+zr;\r\n"
            "// Shrink rings\r\n"
            "bt=max(0,bt*.95+.01);\r\n"
            "// Aspect correction\r\n"
            "asp=w/h;\r\n"
            "// Dynamically adjust particle count based on ring size\r\n"
            "n=((bt*40)|0)*3;",
            "// New rotation speeds\r\n"
            "xr=(rand(50)/500)-0.05;\r\n"
            "yr=(rand(50)/500)-0.05;\r\n"
            "zr=(rand(50)/500)-0.05;\r\n"
            "// Ring size\r\n"
            "bt=1.2;\r\n"
            "n=((bt*40)|0)*3;",
            "// 3D object\r\n"
            "x1=sin(i*$pi*6)/2*bt;\r\n"
            "y1=above(i,.66)-below(i,.33);\r\n"
            "z1=cos(i*$pi*6)/2*bt;\r\n"
            "\r\n"
            "// 3D rotations\r\n"
            "x2=x1*sin(zt)-y1*cos(zt);y2=x1*cos(zt)+y1*sin(zt);\r\n"
            "z2=x2*cos(yt)+z1*sin(yt);x3=x2*sin(yt)-z1*cos(yt);\r\n"
            "y3=y2*sin(xt)-z2*cos(xt);z3=y2*cos(xt)+z2 *sin(xt);\r\n"
            "\r\n"
            "// 2D Projection\r\n"
            "iz=1/(z3+2);\r\n"
            "x=x3*iz;y=y3*iz*asp;\r\n"
            "sizex=iz*2;sizey=iz*2;",
            true,
            false,
            false,
        },
    };

    static const char* const* example_names(int64_t* length_out) {
        *length_out = 4;
        static const char* const options[4] = {
            examples[0].name,
            examples[1].name,
            examples[2].name,
            examples[3].name,
        };
        return options;
    }
    static const char* const* image_files(int64_t* length_out);

    static void on_file_change(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void recompile(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void load_example(Effect*, const Parameter*, const std::vector<int64_t>&);
    static constexpr uint32_t num_parameters = 11;
    static constexpr Parameter parameters[num_parameters] = {
        P_IRANGE(offsetof(Texer2_Config, version),
                 "Effect Version",
                 0,
                 TEXER_II_VERSION_CURRENT),
        P_RESOURCE(offsetof(Texer2_Config, image),
                   "Image",
                   image_files,
                   NULL,
                   on_file_change),
        P_BOOL(offsetof(Texer2_Config, resize), "Resize"),
        P_BOOL(offsetof(Texer2_Config, wrap), "Wrap"),
        P_BOOL(offsetof(Texer2_Config, colorize), "Colorize"),
        P_STRING(offsetof(Texer2_Config, init), "Init", NULL, recompile),
        P_STRING(offsetof(Texer2_Config, frame), "Frame", NULL, recompile),
        P_STRING(offsetof(Texer2_Config, beat), "Beat", NULL, recompile),
        P_STRING(offsetof(Texer2_Config, point), "Point", NULL, recompile),
        P_SELECT_X(offsetof(Texer2_Config, example), "Example", example_names),
        P_ACTION("Load Example", load_example, "Load the selected example code"),
    };

    EFFECT_INFO_GETTERS;
};

struct Texer2_Vars : public Variables {
    double* n;
    double* i;
    double* x;
    double* y;
    double* v;
    double* w;
    double* h;
    double* b;
    double* iw;
    double* ih;
    double* sizex;
    double* sizey;
    double* red;
    double* green;
    double* blue;
    double* skip;

    virtual void register_(void*);
    virtual void init(int, int, int, va_list);
};

class E_Texer2 : public Programmable_Effect<Texer2_Info, Texer2_Config, Texer2_Vars> {
   public:
    E_Texer2(AVS_Instance* avs);
    virtual ~E_Texer2();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Texer2* clone() { return new E_Texer2(*this); }

    void find_image_files();
    void clear_image_files();
    void load_image();
    void load_default_image();
    void delete_image();

    void DrawParticle(int* framebuffer,
                      pixel_rgb0_8* texture,
                      int w,
                      int h,
                      double x,
                      double y,
                      double sizex,
                      double sizey,
                      unsigned int color);

    static std::vector<std::string> filenames;
    static const char** c_filenames;
    int iw;
    int ih;
    pixel_rgb0_8* image_normal;
    pixel_rgb0_8* image_flipped;
    pixel_rgb0_8* image_mirrored;
    pixel_rgb0_8* image_rot180;

    lock_t* image_lock;
};
