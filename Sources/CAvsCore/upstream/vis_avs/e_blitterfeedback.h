#pragma once

#include "effect.h"
#include "effect_info.h"

enum BlitterFeedback_Blend_Mode {
    BLITTER_BLEND_REPLACE = 0,
    BLITTER_BLEND_5050 = 1,
};

struct BlitterFeedback_Config : public Effect_Config {
    int64_t zoom = 30;
    bool on_beat = false;
    int64_t on_beat_zoom = 30;
    int64_t blend_mode = BLITTER_BLEND_REPLACE;
    bool bilinear = false;
};

struct BlitterFeedback_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Blitter Feedback";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 4;
    static constexpr char const* legacy_ape_id = nullptr;

    static const char* const* blend_modes(int64_t* length_out) {
        *length_out = 2;
        static const char* const options[2] = {
            "Replace",
            "50/50",
        };
        return options;
    }

    static void on_zoom_change(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 5;
    static constexpr Parameter parameters[num_parameters] = {
        P_IRANGE(offsetof(BlitterFeedback_Config, zoom),
                 "Zoom",
                 0,
                 256,
                 nullptr,
                 on_zoom_change),
        P_BOOL(offsetof(BlitterFeedback_Config, on_beat), "On Beat"),
        P_IRANGE(offsetof(BlitterFeedback_Config, on_beat_zoom),
                 "On Beat Zoom",
                 0,
                 256,
                 nullptr,
                 on_zoom_change),
        P_SELECT(offsetof(BlitterFeedback_Config, blend_mode),
                 "Blend Mode",
                 blend_modes),
        P_BOOL(offsetof(BlitterFeedback_Config, bilinear), "Bilinear"),
    };

    EFFECT_INFO_GETTERS;
};

class E_BlitterFeedback
    : public Configurable_Effect<BlitterFeedback_Info, BlitterFeedback_Config> {
   public:
    E_BlitterFeedback(AVS_Instance* avs);
    virtual ~E_BlitterFeedback() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_BlitterFeedback* clone() { return new E_BlitterFeedback(*this); }
    void set_current_zoom(int32_t zoom);

   private:
    int32_t blitter_normal(uint32_t* framebuffer,
                           uint32_t* fbout,
                           int w,
                           int h,
                           int32_t zoom);
    int32_t blitter_out(uint32_t* framebuffer,
                        uint32_t* fbout,
                        int w,
                        int h,
                        int32_t zoom);
    int32_t current_zoom;
};
