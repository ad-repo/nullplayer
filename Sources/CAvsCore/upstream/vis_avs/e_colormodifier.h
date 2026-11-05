#pragma once

#include "effect.h"
#include "effect_info.h"
#include "effect_programmable.h"

#include <string>

struct ColorModifier_Config : public Effect_Config {
    std::string init = "";
    std::string frame = "";
    std::string beat = "";
    std::string point = "";
    bool recompute_every_frame = true;
    int64_t example;
};

struct ColorModifier_Preset {
    const char* name;
    const char* init;
    const char* frame;
    const char* beat;
    const char* point;
    bool recompute_every_frame;
};

struct ColorModifier_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Color Modifier";
    static constexpr char const* help =
        "The color modifier allows you to modify the intensity of each color\r\n"
        "channel with respect to itself. For example, you could reverse the red\r\n"
        "channel, double the green channel, or half the blue channel.\r\n"
        "\r\n"
        "The code in the 'level' section should adjust the variables\r\n"
        "'red', 'green', and 'blue', whose value represent the channel\r\n"
        "intensity (0..1).\r\n"
        "Code in the 'frame' or 'level' sections can also use the variable\r\n"
        "'beat' to detect if it is currently a beat.\r\n"
        "\r\n"
        "Try loading an example via the 'Load Example' button for examples.";
    static constexpr int32_t legacy_id = 45;
    static constexpr char* legacy_ape_id = NULL;

    static constexpr uint32_t num_examples = 10;
    static constexpr ColorModifier_Preset examples[num_examples] = {
        {"4x Red Brightness, 2x Green, 1x Blue",
         "",
         "",
         "",
         "red=4*red; green=2*green;",
         false},
        {"Solarization",
         "",
         "",
         "",
         "red=(min(1,red*2)-red)*2;\r\ngreen=red; blue=red;",
         false},
        {"Double Solarization",
         "",
         "",
         "",
         "red=(min(1,red*2)-red)*2;\r\nred=(min(1,red*2)-red)*2;\r\ngreen=red; "
         "blue=red;",
         false},
        {"Inverse Solarization (Soft)",
         "",
         "",
         "",
         "red=abs(red - .5) * 1.5;\r\ngreen=red; blue=red;",
         false},
        {"Big Brightness on Beat",
         "scale=1.0",
         "scale=0.07 + (scale*0.93)",
         "scale=16",
         "red=red*scale;\r\ngreen=red; blue=red;",
         true},
        {"Big Brightness on Beat (Interpolative)",
         "c = 200; f = 0;",
         "f = f + 1;\r\nt = (1.025 - (f / c)) * 5;",
         "c = f;f = 0;",
         "red = red * t;\r\ngreen=red;blue=red;",
         true},
        {"Pulsing Brightness (Beat Interpolative)",
         "c = 200; f = 0;",
         "f = f + 1;\r\nt = (f * 2 * $PI) / c;\r\nst = sin(t) + 1;",
         "c = f;f = 0;",
         "red = red * st;\r\ngreen=red;blue=red;",
         true},
        {"Rolling Solarization (Beat Interpolative)",
         "c = 200; f = 0;",
         "f = f + 1;\r\nt = (f * 2 * $PI) / c;\r\nst = ( sin(t) * .75 ) + 2;",
         "c = f;f = 0;",
         "red=(min(1,red*st)-red)*st;\r\nred=(min(1,red*2)-red)*2;\r\ngreen=red; "
         "blue=red;",
         true},
        {"Rolling Tone (Beat Interpolative)",
         "c = 200; f = 0;",
         "f = f + 1;\r\nt = (f * 2 * $PI) / c;\r\nti = (f / c);\r\nst = sin(t) + "
         "1.5;\r\nct = cos(t) + 1.5;",
         "c = f;f = 0;",
         "red = red * st;\r\ngreen = green * ct;\r\nblue = (blue * 4 * ti) - red - "
         "green;",
         true},
        {"Random Inverse Tone (Switch on Beat)",
         "",
         "",
         "token = rand(99) % 3;\r\ndr = if (equal(token, 0), -1, 1);\r\ndg = if "
         "(equal(token, 1), -1, 1);\r\ndb = if (equal(token, 2), -1, 1);",
         "dd = red * 1.5;\r\nred = pow(dd, dr);\r\ngreen = pow(dd, dg);\r\nblue = "
         "pow(dd, db);",
         true},
    };

    static const char* const* example_names(int64_t* length_out) {
        *length_out = num_examples;
        static const char* const options[num_examples]{
            examples[0].name,
            examples[1].name,
            examples[2].name,
            examples[3].name,
            examples[4].name,
            examples[5].name,
            examples[6].name,
            examples[7].name,
            examples[8].name,
            examples[9].name,
        };
        return options;
    }

    static void recompile(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void load_example(Effect*, const Parameter*, const std::vector<int64_t>&);
    static constexpr uint32_t num_parameters = 7;
    static constexpr Parameter parameters[num_parameters] = {
        P_STRING(offsetof(ColorModifier_Config, init), "Init", NULL, recompile),
        P_STRING(offsetof(ColorModifier_Config, frame), "Frame", NULL, recompile),
        P_STRING(offsetof(ColorModifier_Config, beat), "Beat", NULL, recompile),
        P_STRING(offsetof(ColorModifier_Config, point), "Point", NULL, recompile),
        P_BOOL(offsetof(ColorModifier_Config, recompute_every_frame),
               "Recompute Every Frame"),
        P_SELECT_X(offsetof(ColorModifier_Config, example), "Example", example_names),
        P_ACTION("Load Example", load_example, "Load the selected example code"),
    };

    EFFECT_INFO_GETTERS;
};

struct ColorModifier_Vars : public Variables {
    double* red;
    double* green;
    double* blue;
    double* beat;

    virtual void register_(void*);
    virtual void init(int, int, int, va_list);
};

class E_ColorModifier : public Programmable_Effect<ColorModifier_Info,
                                                   ColorModifier_Config,
                                                   ColorModifier_Vars> {
   public:
    E_ColorModifier(AVS_Instance* avs);
    virtual ~E_ColorModifier();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_ColorModifier* clone() { return new E_ColorModifier(*this); }

    bool channel_table_valid;
    unsigned char channel_table[256 * 3];
};
