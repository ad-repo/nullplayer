#pragma once

#include "effect.h"
#include "effect_info.h"

enum BufferSave_Action {
    BUFFER_ACTION_SAVE = 0,
    BUFFER_ACTION_RESTORE = 1,
    BUFFER_ACTION_SAVE_RESTORE = 2,
    BUFFER_ACTION_RESTORE_SAVE = 3,
};

enum BufferSave_Blend_Modes {
    BUFFER_BLEND_REPLACE = 0,
    BUFFER_BLEND_ADDITIVE = 1,
    BUFFER_BLEND_MAXIMUM = 2,
    BUFFER_BLEND_5050 = 3,
    BUFFER_BLEND_SUB1 = 4,
    BUFFER_BLEND_SUB2 = 5,
    BUFFER_BLEND_MULTIPLY = 6,
    BUFFER_BLEND_ADJUSTABLE = 7,
    BUFFER_BLEND_XOR = 8,
    BUFFER_BLEND_MINIMUM = 9,
    BUFFER_BLEND_EVERY_OTHER_PIXEL = 10,
    BUFFER_BLEND_EVERY_OTHER_LINE = 11,
};

struct BufferSave_Config : public Effect_Config {
    int64_t action = BUFFER_ACTION_SAVE;
    int64_t buffer = 0;
    int64_t blend_mode = BUFFER_BLEND_REPLACE;
    int64_t adjustable_blend = 128;
};

struct BufferSave_Info : public Effect_Info {
    static constexpr char const* group = "Misc";
    static constexpr char const* name = "Buffer Save";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = 18;
    static constexpr char const* legacy_ape_id = nullptr;

    static const char* const* actions(int64_t* length_out) {
        *length_out = 4;
        static const char* const options[4] = {
            "Save",
            "Restore",
            "Alternate Save/Restore",
            "Alternate Restore/Save",
        };
        return options;
    }

    static const char* const* blend_modes(int64_t* length_out) {
        *length_out = 12;
        static const char* const options[12] = {
            /* 0*/ "Replace",
            /* 2*/ "Additive",
            /* 7*/ "Maximum",
            /* 1*/ "50/50",
            /* 4*/ "Subtractive 1",
            /* 9*/ "Subtractive 2",
            /*10*/ "Multiply",
            /*11*/ "Adjustable",
            /* 6*/ "XOR",
            /* 8*/ "Minimum",
            /* 3*/ "Every Other Pixel",
            /* 5*/ "Every Other Line",
        };
        return options;
    }

    static void clear_buffer(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void nudge_parity(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_parameters = 6;
    static constexpr Parameter parameters[num_parameters] = {
        P_SELECT(offsetof(BufferSave_Config, action), "Action", actions),
        P_IRANGE(offsetof(BufferSave_Config, buffer), "Buffer", 1, 8),
        P_SELECT(offsetof(BufferSave_Config, blend_mode), "Blend Mode", blend_modes),
        P_IRANGE(offsetof(BufferSave_Config, adjustable_blend), "Adjust Blend", 0, 255),
        P_ACTION("Clear Buffer", clear_buffer),
        P_ACTION("nudge_parity", nudge_parity),
    };

    EFFECT_INFO_GETTERS;
};

class E_BufferSave : public Configurable_Effect<BufferSave_Info, BufferSave_Config> {
   public:
    E_BufferSave(AVS_Instance* avs);
    virtual ~E_BufferSave() = default;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_BufferSave* clone() { return new E_BufferSave(*this); }

    void clear_buffer();
    void nudge_parity();

   private:
    bool save_restore_toggle;
    bool need_clear;
};
