#pragma once

#include "effect.h"
#include "effect_info.h"

struct Mirror_Config : public Effect_Config {
    bool top_to_bottom = true;
    bool bottom_to_top = false;
    bool left_to_right = false;
    bool right_to_left = false;
    bool on_beat_random = false;
    int64_t transition_duration = 4;
};

struct Mirror_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Mirror";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 26;
    static constexpr char const* legacy_ape_id = nullptr;

    static void on_mode_change(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void on_random_change(Effect*,
                                 const Parameter*,
                                 const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 6;
    static constexpr Parameter parameters[num_parameters] = {
        P_BOOL(offsetof(Mirror_Config, top_to_bottom),
               "Top to Bottom",
               nullptr,
               on_mode_change),
        P_BOOL(offsetof(Mirror_Config, bottom_to_top),
               "Bottom to Top",
               nullptr,
               on_mode_change),
        P_BOOL(offsetof(Mirror_Config, left_to_right),
               "Left to Right",
               nullptr,
               on_mode_change),
        P_BOOL(offsetof(Mirror_Config, right_to_left),
               "Right to Left",
               nullptr,
               on_mode_change),
        P_BOOL(offsetof(Mirror_Config, on_beat_random),
               "On Beat Random",
               nullptr,
               on_random_change),
        P_IRANGE(offsetof(Mirror_Config, transition_duration),
                 "Transition Duration",
                 0,
                 16),
    };

    EFFECT_INFO_GETTERS;
};

class E_Mirror : public Configurable_Effect<Mirror_Info, Mirror_Config> {
   public:
    E_Mirror(AVS_Instance* avs);
    virtual ~E_Mirror() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Mirror* clone() { return new E_Mirror(*this); }
    void on_mode_change(const Parameter* param);
    void on_random_change();

   private:
    void random_mode();
    uint8_t cur_top_to_bottom;
    uint8_t cur_bottom_to_top;
    uint8_t cur_left_to_right;
    uint8_t cur_right_to_left;
    uint8_t target_top_to_bottom;
    uint8_t target_bottom_to_top;
    uint8_t target_left_to_right;
    uint8_t target_right_to_left;
    uint32_t transition_stepper;
};
