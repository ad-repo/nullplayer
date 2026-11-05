#pragma once

#include "effect.h"
#include "effect_info.h"

#define COLORFADE_VERSION_V2_81D 0
#define COLORFADE_VERSION_V2_81D_UPGRADE_HELP                                   \
    "Saved version has switches sliders 2 & 3 between normal and on-beat mode." \
    " Upgrade to align."
#define COLORFADE_VERSION_CURRENT 1
// The maximum version number is 127, but we shouldn't let it get to that point, i.e.
// versions shouldn't really be handled this way for much longer.

struct Colorfade_Config : public Effect_Config {
    int64_t version = COLORFADE_VERSION_CURRENT;
    int64_t fader_max = -8;
    int64_t fader_2nd = 8;
    int64_t fader_3rd_gray = -8;
    bool on_beat = false;
    bool on_beat_random = false;
    int64_t on_beat_max = -8;
    int64_t on_beat_2nd = 8;
    int64_t on_beat_3rd_gray = -8;
};

struct Colorfade_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Colorfade";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 11;
    static constexpr char* legacy_ape_id = nullptr;

    static constexpr uint32_t num_parameters = 9;
    static constexpr Parameter parameters[num_parameters] = {
        P_IRANGE(offsetof(Colorfade_Config, version),
                 "Effect Version",
                 0,
                 COLORFADE_VERSION_CURRENT),
        P_IRANGE(offsetof(Colorfade_Config, fader_max), "Max Channel", -32, 32),
        P_IRANGE(offsetof(Colorfade_Config, fader_2nd), "2nd Channel", -32, 32),
        P_IRANGE(offsetof(Colorfade_Config, fader_3rd_gray),
                 "3rd Channel or Gray",
                 -32,
                 32),
        P_BOOL(offsetof(Colorfade_Config, on_beat), "On Beat"),
        P_BOOL(offsetof(Colorfade_Config, on_beat_random), "On Beat Random"),
        P_IRANGE(offsetof(Colorfade_Config, on_beat_max), "Beat Max Channel", -32, 32),
        P_IRANGE(offsetof(Colorfade_Config, on_beat_2nd), "Beat 2nd Channel", -32, 32),
        P_IRANGE(offsetof(Colorfade_Config, on_beat_3rd_gray),
                 "Beat 3rd Channel or Gray",
                 -32,
                 32),
    };

    EFFECT_INFO_GETTERS;
};

class E_Colorfade : public Configurable_Effect<Colorfade_Info, Colorfade_Config> {
   public:
    E_Colorfade(AVS_Instance* avs);
    virtual ~E_Colorfade() override = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h) override;
    virtual void load_legacy(unsigned char* data, int len) override;
    virtual int save_legacy(unsigned char* data) override;
    virtual E_Colorfade* clone() { return new E_Colorfade(*this); }

    bool can_multithread() override { return true; }
    int smp_begin(int max_threads,
                  char visdata[2][2][576],
                  int is_beat,
                  int* framebuffer,
                  int* fbout,
                  int w,
                  int h) override;
    void smp_render(int this_thread,
                    int max_threads,
                    char visdata[2][2][576],
                    int is_beat,
                    int* framebuffer,
                    int* fbout,
                    int w,
                    int h) override;
    int smp_finish(char visdata[2][2][576],
                   int is_beat,
                   int* framebuffer,
                   int* fbout,
                   int w,
                   int h) override;

    int64_t cur_max;
    int64_t cur_2nd;
    int64_t cur_3rd_gray;
    int64_t fader_switch[4][3]{};
    unsigned char channel_fader_switch_tab[512][512]{};
    unsigned char clip[40 + 256 + 40]{};

   private:
    void make_channel_fader_switch_tab();
};
