#pragma once

#include "effect.h"
#include "effect_info.h"

struct VideoDelay_Config : public Effect_Config {
    bool use_beats = false;
    int64_t delay = 10;
};

struct VideoDelay_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Video Delay";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = -1;
    static constexpr char* legacy_ape_id = "Holden04: Video Delay";

    static void on_use_beats_change(Effect*,
                                    const Parameter*,
                                    const std::vector<int64_t>&);
    static void on_delay_change(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 2;
    static constexpr Parameter parameters[num_parameters] = {
        P_BOOL(offsetof(VideoDelay_Config, use_beats),
               "Use Beats",
               NULL,
               on_use_beats_change),
        P_IRANGE(offsetof(VideoDelay_Config, delay),
                 "Delay",
                 0,
                 200,
                 NULL,
                 on_delay_change),
    };

    EFFECT_INFO_GETTERS;
};

class E_VideoDelay : public Configurable_Effect<VideoDelay_Info, VideoDelay_Config> {
   public:
    E_VideoDelay(AVS_Instance* avs);
    virtual ~E_VideoDelay();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_VideoDelay* clone() { return new E_VideoDelay(*this); }

    unsigned long buffersize;
    unsigned long virtual_buffersize;
    unsigned long old_virtual_buffersize;
    void* buffer;
    void* in_out_pos;
    unsigned long frames_since_beat;
    unsigned long frame_delay;
    unsigned long frame_mem;
    unsigned long old_frame_mem;
};
