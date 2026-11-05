#pragma once

#include "effect.h"
#include "effect_info.h"

#include <cstdint>
#include <mmintrin.h>

#define CONVO_KERNEL_DIM       7
#define CONVO_KERNEL_SIZE      CONVO_KERNEL_DIM* CONVO_KERNEL_DIM
// The total file size is CONVO_FILE_STATIC_SIZE + the filename string length (w/o '\0')
#define CONVO_FILE_STATIC_SIZE ((CONVO_KERNEL_SIZE + 6 /*config*/) * sizeof(uint32_t))

struct Convolution_Kernel_Config : public Effect_Config {
    int64_t value = 0;
    Convolution_Kernel_Config() = default;
    explicit Convolution_Kernel_Config(int64_t value) : value(value) {}
};

struct Convolution_Config : public Effect_Config {
    bool wrap = false;
    bool absolute = false;
    bool two_pass = false;
    int64_t bias = 0;
    int64_t scale = 1;
    std::vector<Convolution_Kernel_Config> kernel;
    std::string save_file;
    Convolution_Config() {
        for (int i = 0; i < CONVO_KERNEL_SIZE; ++i) {
            // Put a 1 in the middle field, 0 elsewhere
            kernel.emplace_back(i == (CONVO_KERNEL_SIZE / 2));
        }
    }
};

struct Convolution_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Convolution Filter";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = -1;
    static constexpr char const* legacy_ape_id = "Holden03: Convolution Filter";

    static const char* const* edge_modes(int64_t* length_out) {
        *length_out = 2;
        static const char* const options[2] = {
            "Extend",
            "Wrap",
        };
        return options;
    }

    static void update_kernel(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void on_wrap_or_absolute_change(Effect*,
                                           const Parameter*,
                                           const std::vector<int64_t>&);
    static void on_scale_change(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void autoscale(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void kernel_clear(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void kernel_save(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void kernel_load(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_kernel_params = 1;
    static constexpr Parameter kernel_params[num_kernel_params] = {
        P_IRANGE(offsetof(Convolution_Kernel_Config, value),
                 "Value",
                 INT16_MIN,
                 INT16_MAX,
                 "Take the pixel here, at this position from the center, multiply it by"
                 " this value and add it to the center pixel",
                 update_kernel),
    };

    static constexpr uint32_t num_parameters = 11;
    static constexpr Parameter parameters[num_parameters] = {
        P_BOOL(offsetof(Convolution_Config, wrap),
               "Wrap",
               "If the result becomes negative wrap around to white",
               on_wrap_or_absolute_change),
        P_BOOL(offsetof(Convolution_Config, absolute),
               "Absolute",
               "If the result becomes negative wrap and throw away the sign",
               on_wrap_or_absolute_change),
        P_BOOL(offsetof(Convolution_Config, two_pass),
               "Two Pass",
               "Apply the filter a second time, rotated by 90deg, and add it to the"
               " first pass",
               update_kernel),
        P_IRANGE(offsetof(Convolution_Config, bias),
                 "Bias",
                 INT16_MIN,
                 INT16_MAX,
                 "Offsets all values by this value",
                 update_kernel),
        P_IRANGE(offsetof(Convolution_Config, scale),
                 "Scale",
                 INT16_MIN,
                 INT16_MAX,
                 "Divides all values by this value",
                 on_scale_change),
        P_LIST<Convolution_Kernel_Config>(offsetof(Convolution_Config, kernel),
                                          "Kernel",
                                          kernel_params,
                                          num_kernel_params,
                                          CONVO_KERNEL_SIZE,
                                          CONVO_KERNEL_SIZE),
        P_STRING(offsetof(Convolution_Config, save_file), "Filename"),
        P_ACTION("Auto-Scale",
                 autoscale,
                 "Restore the default filter, which doesn't change the image"),
        P_ACTION("Clear", kernel_clear, "Reset all parameters to default"),
        P_ACTION("Save", kernel_save, "Save the current configuration to a .cff file"),
        P_ACTION("Load", kernel_load, "Load a saved .cff file"),
    };

    EFFECT_INFO_GETTERS;
};

typedef int (*draw_func)(void* framebuffer, void* fbout, void* m64f_array);

class E_Convolution : public Configurable_Effect<Convolution_Info, Convolution_Config> {
   public:
    E_Convolution(AVS_Instance* avs);
    virtual ~E_Convolution();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Convolution* clone() { return new E_Convolution(*this); }

    void create_draw_func();
    inline void delete_draw_func();
    void check_scale_not_zero();
    void check_mutually_exclusive_abs_wrap(bool wrap_changed_last = true);
    void autoscale();
    void kernel_clear();
    void kernel_save();
    void kernel_load();

    draw_func draw;

    // abs(farray) packed into the four unsigned shorts that make up an m64
    __m64 m64_farray[CONVO_KERNEL_SIZE];
    __m64 m64_bias;
    int width;
    int height;
    bool draw_created;
    bool need_draw_update;
    int code_length;
};
