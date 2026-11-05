#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"
#include "pixel_format.h"

#include "../platform.h"

#include <cstdint>

#include <sys/types.h>

#define P2_NUM_BLEND_MODES 11

enum Picture2_Blend_Modes {
    P2_BLEND_REPLACE = BLEND_REPLACE,
    P2_BLEND_ADDITIVE = BLEND_ADDITIVE,
    P2_BLEND_MAXIMUM = BLEND_MAXIMUM,
    P2_BLEND_5050 = BLEND_5050,
    P2_BLEND_SUB1 = BLEND_SUB1,
    P2_BLEND_SUB2 = BLEND_SUB2,
    P2_BLEND_MULTIPLY = BLEND_MULTIPLY,
    P2_BLEND_ADJUSTABLE = BLEND_ADJUSTABLE,
    P2_BLEND_XOR = BLEND_XOR,
    P2_BLEND_MINIMUM = BLEND_MINIMUM,
    P2_BLEND_IGNORE = BLEND_MINIMUM + 1,
};

struct Picture2_Config : public Effect_Config {
    std::string image;
    int64_t blend_mode = P2_BLEND_REPLACE;
    int64_t on_beat_blend_mode = P2_BLEND_REPLACE;
    bool bilinear = true;
    bool on_beat_bilinear = true;
    int64_t adjust_blend = 128;
    int64_t on_beat_adjust_blend = 128;
    std::string error_msg;
};

struct Picture2_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Picture II";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = -1;
    static constexpr char const* legacy_ape_id = "Picture II";

    static const char* const* image_files(int64_t* length_out);
    static const char* const* blend_modes(int64_t* length_out) {
        *length_out = P2_NUM_BLEND_MODES;
        static const char* const options[P2_NUM_BLEND_MODES] = {
            "Replace",
            "Additive",
            "Maximum",
            "50/50",
            "Subtractive 1",
            "Subtractive 2",
            "Multiply",
            "Adjustable",
            "XOR",
            "Minimum",
            "Ignore",
        };
        return options;
    }

    static void on_file_change(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 8;
    static constexpr Parameter parameters[num_parameters] = {
        P_RESOURCE(offsetof(Picture2_Config, image),
                   "Image",
                   image_files,
                   nullptr,
                   on_file_change),
        P_SELECT(offsetof(Picture2_Config, blend_mode), "Blend Mode", blend_modes),
        P_SELECT(offsetof(Picture2_Config, on_beat_blend_mode),
                 "On Beat Blend Mode",
                 blend_modes),
        P_BOOL(offsetof(Picture2_Config, bilinear), "Bilinear"),
        P_BOOL(offsetof(Picture2_Config, on_beat_bilinear), "On Beat Bilinear"),
        P_IRANGE(offsetof(Picture2_Config, adjust_blend), "Adjustable Blend", 0, 255),
        P_IRANGE(offsetof(Picture2_Config, on_beat_adjust_blend),
                 "On Beat Adjustable Blend",
                 0,
                 255),
        P_STRING(offsetof(Picture2_Config, error_msg), "Error Message")};

    EFFECT_INFO_GETTERS;
};

class E_Picture2 : public Configurable_Effect<Picture2_Info, Picture2_Config> {
   public:
    E_Picture2(AVS_Instance* avs);
    virtual ~E_Picture2();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void on_load();
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Picture2* clone() { return new E_Picture2(*this); }

    static std::vector<const char*> file_list;
    bool load_image();

   private:
    void refresh_image(uint32_t w, uint32_t h);
    void find_image_files();
    static void clear_image_files();

    lock_t* image_lock;
    pixel_rgb0_8* image;
    uint32_t iw;
    uint32_t ih;
    pixel_rgb0_8* work_image;
    pixel_rgb0_8* work_image_bilinear;
    uint32_t wiw;
    uint32_t wih;
    bool need_image_refresh;
};
