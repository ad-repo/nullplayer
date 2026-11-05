#pragma once

#include "effect.h"
#include "effect_common.h"
#include "effect_info.h"

struct Starfield_Config : public Effect_Config {
    uint64_t color = 0xffffff;
    int64_t blend_mode = BLEND_SIMPLE_REPLACE;
    double speed = 6.0;
    int64_t stars = 350;
    bool on_beat = false;
    double on_beat_speed = 4.0;
    int64_t on_beat_duration = 15;
};

struct Starfield_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Starfield";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 27;
    static constexpr char const* legacy_ape_id = nullptr;

    static void initialize(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void set_cur_speed(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 7;
    static constexpr Parameter parameters[num_parameters] = {
        P_COLOR(offsetof(Starfield_Config, color), "Color"),
        P_SELECT(offsetof(Starfield_Config, blend_mode),
                 "Blend Mode",
                 blend_modes_simple),
        P_FRANGE(offsetof(Starfield_Config, speed),
                 "Warp Speed",
                 1.0,
                 500.0,
                 nullptr,
                 set_cur_speed),
        P_IRANGE(offsetof(Starfield_Config, stars),
                 "Stars",
                 100,
                 4095,
                 nullptr,
                 initialize),
        P_BOOL(offsetof(Starfield_Config, on_beat), "On Beat"),
        P_FRANGE(offsetof(Starfield_Config, on_beat_speed),
                 "On-Beat Speed",
                 1.0,
                 500.0),
        P_IRANGE(offsetof(Starfield_Config, on_beat_duration),
                 "On-Beat Duration",
                 1,
                 100),
    };

    EFFECT_INFO_GETTERS;
};

struct StarField_Star {
    int x = 0;
    int y = 0;
    float z = 0;
    float speed = 0.0;
    int ox = 0;
    int oy = 0;
};

class E_Starfield : public Configurable_Effect<Starfield_Info, Starfield_Config> {
   public:
    E_Starfield(AVS_Instance* avs);
    virtual ~E_Starfield() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Starfield* clone() { return new E_Starfield(*this); }
    void initialize_stars();
    void set_cur_speed();

   private:
    void create_star(int i);
    static float GET_FLOAT(const unsigned char* data, int pos);
    static void PUT_FLOAT(float f, unsigned char* data, int pos);

    int abs_stars;
    int x_off;
    int y_off;
    int z_off;
    int width;
    int height;
    double current_speed;
    float on_beat_speed_diff;
    int on_beat_cooldown;
    StarField_Star stars[4096];
};
