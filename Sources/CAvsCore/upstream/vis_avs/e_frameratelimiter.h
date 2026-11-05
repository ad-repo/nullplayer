#pragma once

#include "effect.h"
#include "effect_info.h"

struct FramerateLimiter_Config : public Effect_Config {
    int64_t limit = 30;
};

void update_time_diff(Effect*, const Parameter*, const std::vector<int64_t>&);

struct FramerateLimiter_Info : public Effect_Info {
    static constexpr char const* group = "Misc";
    static constexpr char const* name = "Framerate Limiter";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = -1;
    static constexpr char* legacy_ape_id = "VFX FRAMERATE LIMITER";

    static constexpr uint32_t num_parameters = 1;
    static constexpr Parameter parameters[num_parameters] = {
        P_IRANGE(offsetof(FramerateLimiter_Config, limit),
                 "FPS Limit",
                 1,
                 60,
                 NULL,
                 update_time_diff),
    };

    EFFECT_INFO_GETTERS;
};

class E_FramerateLimiter
    : public Configurable_Effect<FramerateLimiter_Info, FramerateLimiter_Config> {
   public:
    E_FramerateLimiter(AVS_Instance* avs);
    virtual ~E_FramerateLimiter();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_FramerateLimiter* clone() { return new E_FramerateLimiter(*this); }

    void update_time_diff();

   private:
    int64_t now();
    void sleep(int32_t duration_ms);
    int time_diff;
    int64_t last_time;
};
