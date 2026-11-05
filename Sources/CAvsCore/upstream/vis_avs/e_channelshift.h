#pragma once

#include "effect.h"
#include "effect_info.h"

enum ChannelShift_Modes {
    CHANSHIFT_MODE_RGB = 0,
    CHANSHIFT_MODE_GBR = 1,
    CHANSHIFT_MODE_BRG = 2,
    CHANSHIFT_MODE_RBG = 3,
    CHANSHIFT_MODE_BGR = 4,
    CHANSHIFT_MODE_GRB = 5,
};

struct ChannelShift_Config : public Effect_Config {
    int64_t mode = 3;
    bool on_beat_random = true;
};

struct ChannelShift_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Channel Shift";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = -1;
    static constexpr char* legacy_ape_id = "Channel Shift";

    static const char* const* modes(int64_t* length_out) {
        *length_out = 6;
        static const char* const options[6] = {
            "RGB",
            "GBR",
            "BRG",
            "RBG",
            "BGR",
            "GRB",
        };
        return options;
    }

    static constexpr uint32_t num_parameters = 2;
    static constexpr Parameter parameters[num_parameters] = {
        P_SELECT(offsetof(ChannelShift_Config, mode), "Mode", modes),
        P_BOOL(offsetof(ChannelShift_Config, on_beat_random), "On-Beat Random"),
    };

    EFFECT_INFO_GETTERS;
};

class E_ChannelShift
    : public Configurable_Effect<ChannelShift_Info, ChannelShift_Config> {
   public:
    E_ChannelShift(AVS_Instance* avs);
    virtual ~E_ChannelShift();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_ChannelShift* clone() { return new E_ChannelShift(*this); }

   private:
    void shift(int* framebuffer, int l);
    void shift_ssse3(int* framebuffer, int l);
};
