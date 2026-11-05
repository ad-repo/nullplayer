#pragma once

#include "effect.h"
#include "effect_info.h"
#include "effect_programmable.h"

enum GlobalVariables_Load_Options {
    GLOBALVARS_LOAD_NONE = 0,
    GLOBALVARS_LOAD_ONCE,
    GLOBALVARS_LOAD_CODE,
    GLOBALVARS_LOAD_FRAME,
};

struct GlobalVariables_Config : public Effect_Config {
    int64_t load_time = GLOBALVARS_LOAD_NONE;
    std::string init;
    std::string frame;
    std::string beat;
    std::string point;  // Unused but required by Programmable_Effect class interface.
    std::string file;
    std::string save_reg_ranges;
    std::string save_buf_ranges;
    std::string error_msg;
};

struct GlobalVariables_Info : public Effect_Info {
    static constexpr char const* group = "Misc";
    static constexpr char const* name = "Global Variables";
    static constexpr char const* help =
        "The Global Variable Manager is a component designed to ease handling the"
        " gmegabuf and reg## global variables in AVS.\r\n"
        "\r\n"
        "w, h \r\n"
        "  The width and the height of the screen respectively\r\n"
        "\r\n"
        "b\r\n"
        "  Set to 1 on beat and is otherwise 0\r\n"
        "\r\n"
        "load, save\r\n"
        "  These start as 0 every frame and when set to nonzero values in code these"
        " signal to either load or save at the beginning of the next frame.\r\n"
        "\r\n"
        "The first part of the component is custom init, frame and beat code, this"
        " allows you to do things like set up a global timer or work with the gmegabuf"
        " before you access it with superscopes or other programmable components. It"
        " doesn't allow you to render anything directly and works much like a"
        " superscope with n=0.\r\n"
        "\r\n"
        "The second feature is the load/save functionality, which allows you to load"
        " or save reg## or gmegabuf to files. The variables are saved by generating a"
        " block of code which sets them, when loaded this block of code is executed."
        " The code is easily readable and can be hand edited, you may declare variables"
        " and such in here but they won't be maintained after load or passed on into"
        " the main code.\r\n"
        "\r\n"
        "The loading and saving can be code-controlled using the load and save"
        " variables described above, if 'code control' is enabled. Alternatively you"
        " can set it to load once or every frame. The data is always loaded at the"
        " beginning of the next frame so that you can create loading screens.\r\n"
        "\r\n"
        "Enter numerical ranges for the register (reg00..reg99) and gmegabuf values"
        " you want to load/save into the range boxes.\r\n"
        "Enter them like a print range in MS Word, e.g. 1-4,10-38,50,99. If the range"
        " is invalid it won't be used and Err will be displayed next to it. Note that"
        " the range is only used to decide how much data is saved. When loading a file"
        " it is simply loaded and has its code executed which will typically fill the"
        " range specified when that file was saved. The file will be stored with the"
        " specified name in the AVS directory. If you specify a name like"
        " \"path\\filename.gvm\" then you can save to subdirectories within AVS' main"
        " folder too.";
    static constexpr int32_t legacy_id = -1;
    static constexpr char const* legacy_ape_id = "Jheriko: Global";

    static const char* const* load_times(int64_t* length_out) {
        *length_out = 4;
        static const char* const options[4] = {
            "None",
            "Once",
            "Code Control",
            "Every Frame",
        };
        return options;
    }

    static void check_ranges(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void save_ranges(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void recompile(Effect*, const Parameter*, const std::vector<int64_t>&);
    static constexpr uint32_t num_parameters = 9;
    static constexpr Parameter parameters[num_parameters] = {
        P_SELECT(offsetof(GlobalVariables_Config, load_time), "Load Time", load_times),
        P_STRING(offsetof(GlobalVariables_Config, init), "Init", nullptr, recompile),
        P_STRING(offsetof(GlobalVariables_Config, frame), "Frame", nullptr, recompile),
        P_STRING(offsetof(GlobalVariables_Config, beat), "Beat", nullptr, recompile),
        P_STRING(offsetof(GlobalVariables_Config, file), "File"),
        P_STRING(offsetof(GlobalVariables_Config, save_reg_ranges),
                 "Save Reg Range",
                 nullptr,
                 check_ranges),
        P_STRING(offsetof(GlobalVariables_Config, save_buf_ranges),
                 "Save Buf Range",
                 nullptr,
                 check_ranges),
        P_STRING(offsetof(GlobalVariables_Config, error_msg), "Error Message"),
        P_ACTION("Save Ranges", save_ranges),
    };

    EFFECT_INFO_GETTERS;
};

struct GlobalVariables_Vars : public Variables {
    double* w;
    double* h;
    double* b;
    double* load;
    double* save;

    virtual void register_(void*);
    virtual void init(int, int, int, va_list);
};

class E_GlobalVariables : public Programmable_Effect<GlobalVariables_Info,
                                                     GlobalVariables_Config,
                                                     GlobalVariables_Vars> {
    friend GlobalVariables_Info;

   public:
    E_GlobalVariables(AVS_Instance* avs);
    virtual ~E_GlobalVariables();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_GlobalVariables* clone() { return new E_GlobalVariables(*this); }

   private:
    bool is_first_frame;
    bool load_code_next_frame;
    std::string filepath;

    std::vector<int*> reg_ranges;
    static const int max_regs_index;
    std::vector<int*> buf_ranges;
    static const int max_gmb_index;

    void exec_code_from_file(char visdata[2][2][576]);
    void save_ranges_to_file();
    static bool check_set_range(const std::string& input,
                                std::vector<int*>& ranges,
                                int max_index);
    static double reg_value(int index);
    static double buf_value(int index);
};
