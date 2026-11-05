#pragma once

#include "effect.h"
#include "effect_info.h"
#include "pixel_format.h"

#include "../platform.h"

#include <string>
#include <vector>

struct Texer_Config : public Effect_Config {
    std::string image;
    bool add_to_input = false;
    bool colorize = false;
    int64_t num_particles = 100;
};

struct Texer_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Texer";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = -1;
    static constexpr char* legacy_ape_id = "Texer";

    static const char* const* image_files(int64_t* length_out);

    static void on_file_change(Effect*, const Parameter*, const std::vector<int64_t>&);
    static constexpr uint32_t num_parameters = 4;
    static constexpr Parameter parameters[num_parameters] = {
        P_RESOURCE(offsetof(Texer_Config, image),
                   "Image",
                   image_files,
                   NULL,
                   on_file_change),
        P_BOOL(offsetof(Texer_Config, add_to_input), "Add to Input"),
        P_BOOL(offsetof(Texer_Config, colorize), "Colorize"),
        P_IRANGE(offsetof(Texer_Config, num_particles), "Particles", 1, 1024),
    };

    EFFECT_INFO_GETTERS;
};

class E_Texer : public Configurable_Effect<Texer_Info, Texer_Config> {
   public:
    E_Texer(AVS_Instance* avs);
    virtual ~E_Texer();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void on_load();
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Texer* clone() { return new E_Texer(*this); }

    void find_image_files();
    void clear_image_files();
    bool load_image();

    static std::vector<std::string> filenames;
    static const char** c_filenames;

   private:
    void render_particle(int* framebuffer, int* fbout, int x, int y, int w, int h);
    void render_particle_sse2(int* framebuffer, int* fbout, int x, int y, int w, int h);

    pixel_rgb0_8* image_data;
    int32_t image_width;
    int32_t image_width_half;
    int32_t image_width_other_half;
    int32_t image_data_width;
    int32_t image_height;
    int32_t image_height_half;
    int32_t image_height_other_half;
    lock_t* image_lock;
    static int instance_count;
};
