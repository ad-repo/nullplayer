#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"
#include "pixel_format.h"

enum Picture_Fit_Mode {
    PICTURE_FIT_STRETCH = 0,
    PICTURE_FIT_WIDTH = 1,
    PICTURE_FIT_HEIGHT = 2,
};

struct Picture_Config : public Effect_Config {
    std::string image;
    int64_t blend_mode = BLEND_SIMPLE_5050;
    bool on_beat_additive = false;
    int64_t on_beat_duration = 6;
    int64_t fit = PICTURE_FIT_STRETCH;
    std::string error_msg;
};

struct Picture_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Picture";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 34;
    static constexpr char const* legacy_ape_id = nullptr;

    static const char* const* image_files(int64_t* length_out);
    static const char* const* fits(int64_t* length_out) {
        *length_out = 3;
        static const char* const options[3] = {"Stretch", "Fit Width", "Fit Height"};
        return options;
    }

    static void on_file_change(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void on_fit_change(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 6;
    static constexpr Parameter parameters[num_parameters] = {
        P_RESOURCE(offsetof(Picture_Config, image),
                   "Image",
                   image_files,
                   nullptr,
                   on_file_change),
        P_SELECT(offsetof(Picture_Config, blend_mode),
                 "Blend Mode",
                 blend_modes_simple),
        P_BOOL(offsetof(Picture_Config, on_beat_additive), "On-Beat Additive"),
        P_IRANGE(offsetof(Picture_Config, on_beat_duration), "On Beat Duration", 0, 32),
        P_SELECT(offsetof(Picture_Config, fit),
                 "Image Fit",
                 fits,
                 nullptr,
                 on_fit_change),
        P_STRING(offsetof(Picture_Config, error_msg), "Error Message"),
    };

    EFFECT_INFO_GETTERS;
};

class E_Picture : public Configurable_Effect<Picture_Info, Picture_Config> {
   public:
    E_Picture(AVS_Instance* avs);
    virtual ~E_Picture();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Picture* clone() { return new E_Picture(*this); }

    static std::vector<const char*> file_list;
    void load_image();

   private:
    void find_image_files();
    static void clear_image_files();

    int32_t width;
    int32_t height;
    int32_t on_beat_cooldown;
    pixel_rgb0_8* image_data;
    lock_t* image_lock;
};
