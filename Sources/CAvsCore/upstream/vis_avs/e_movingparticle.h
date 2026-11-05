#pragma once

#include "effect.h"
#include "effect_info.h"

enum MovingParticle_Blendmodes {
    PARTICLE_BLEND_REPLACE = 0,
    PARTICLE_BLEND_ADDITIVE = 1,
    PARTICLE_BLEND_5050 = 2,
    PARTICLE_BLEND_DEFAULT = 3,
};

struct MovingParticle_Config : public Effect_Config {
    uint64_t color = 0xffffff;
    int64_t distance = 16;
    int64_t size = 8;
    bool on_beat_size_change = false;
    int64_t on_beat_size = 8;
    int64_t blend_mode = PARTICLE_BLEND_ADDITIVE;
};

struct MovingParticle_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Moving Particle";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 8;
    static constexpr char const* legacy_ape_id = nullptr;

    static const char* const* blend_modes(int64_t* length_out) {
        *length_out = 4;
        static const char* const options[4] = {
            "Replace",
            "Additive",
            "50/50",
            "Default",
        };
        return options;
    }

    static void on_size_change(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 6;
    static constexpr Parameter parameters[num_parameters] = {
        P_COLOR(offsetof(MovingParticle_Config, color), "Color"),
        P_IRANGE(offsetof(MovingParticle_Config, distance), "Distance", 1, 32),
        P_IRANGE(offsetof(MovingParticle_Config, size),
                 "Size",
                 1,
                 128,
                 nullptr,
                 on_size_change),
        P_BOOL(offsetof(MovingParticle_Config, on_beat_size_change),
               "On Beat Size Change"),
        P_IRANGE(offsetof(MovingParticle_Config, on_beat_size),
                 "On Beat Size",
                 1,
                 128,
                 nullptr,
                 on_size_change),
        P_SELECT(offsetof(MovingParticle_Config, blend_mode),
                 "Blend Mode",
                 blend_modes),
    };

    EFFECT_INFO_GETTERS;
};

class E_MovingParticle
    : public Configurable_Effect<MovingParticle_Info, MovingParticle_Config> {
   public:
    E_MovingParticle(AVS_Instance* avs);
    virtual ~E_MovingParticle() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_MovingParticle* clone() { return new E_MovingParticle(*this); }

    void set_current_size(int64_t size);

   private:
    int32_t cur_size;
    double c[2];
    double v[2];
    double p[2];
};
