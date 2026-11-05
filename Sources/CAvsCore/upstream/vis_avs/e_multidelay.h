#pragma once

#include "effect.h"
#include "effect_info.h"

#include <unordered_map>

#define MULTIDELAY_NUM_BUFFERS 6

enum MultiDelay_Modes {
    MULTIDELAY_MODE_INPUT = 0,
    MULTIDELAY_MODE_OUTPUT = 1,
};

struct MultiDelay_Config : public Effect_Config {
    int64_t mode = MULTIDELAY_MODE_INPUT;
    int64_t active_buffer = 0;
};

struct MultiDelay_Global_Buffer : public Effect_Config {
    void* buffer = NULL;
    void* in_pos = NULL;
    void* out_pos = NULL;
    uint32_t size = 1;
    uint32_t virtual_size = 1;
    uint32_t old_virtual_size = 1;
    bool use_beats = false;
    uint32_t delay = 0;
    uint32_t frame_delay = 0;
    MultiDelay_Global_Buffer()
        : buffer(calloc(1, 1)), in_pos(this->buffer), out_pos(this->buffer) {}
    ~MultiDelay_Global_Buffer() { free(this->buffer); }
};

struct MultiDelay_Global_Config : public Effect_Config {
    std::vector<MultiDelay_Global_Buffer> buffers;
    uint32_t num_instances = 0;
    uint32_t frames_since_beat = 0;
    uint32_t frames_per_beat = 0;
    uint32_t frame_mem_size = 1;
    uint32_t old_frame_mem_size = 1;
    uint32_t render_id = 0;
    MultiDelay_Global_Config() { this->buffers.resize(MULTIDELAY_NUM_BUFFERS); }
};

struct MultiDelay_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Multi Delay";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = -1;
    static constexpr char* legacy_ape_id = "Holden05: Multi Delay";

    static const char* const* modes(int64_t* length_out) {
        *length_out = 2;
        static const char* const options[2] = {
            "Input",
            "Output",
        };
        return options;
    }

    static void on_delay(Effect*, const Parameter*, const std::vector<int64_t>&);

    static constexpr uint32_t num_buffer_parameters = 2;
    static constexpr Parameter buffer_parameters[num_buffer_parameters] = {
        P_BOOL_G(offsetof(MultiDelay_Global_Buffer, use_beats), "Use Beats"),
        P_IRANGE_G(offsetof(MultiDelay_Global_Buffer, delay),
                   "Delay",
                   0,
                   400,
                   NULL,
                   on_delay),
    };

    static constexpr uint32_t num_parameters = 3;
    static constexpr Parameter parameters[num_parameters] = {
        P_SELECT(offsetof(MultiDelay_Config, mode), "Mode", modes),
        P_IRANGE(offsetof(MultiDelay_Config, active_buffer),
                 "Active Buffer",
                 0,
                 MULTIDELAY_NUM_BUFFERS - 1),
        P_LIST_G<MultiDelay_Global_Buffer>(offsetof(MultiDelay_Global_Config, buffers),
                                           "Buffers",
                                           buffer_parameters,
                                           num_buffer_parameters,
                                           MULTIDELAY_NUM_BUFFERS,
                                           MULTIDELAY_NUM_BUFFERS),
    };

    EFFECT_INFO_GETTERS;
};

class E_MultiDelay : public Configurable_Effect<MultiDelay_Info,
                                                MultiDelay_Config,
                                                MultiDelay_Global_Config> {
   public:
    E_MultiDelay(AVS_Instance* avs);
    virtual ~E_MultiDelay() {}
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_MultiDelay* clone() { return new E_MultiDelay(*this); }
    void set_frame_delay(int64_t buffer_index);
    inline void manage_buffers(bool is_beat, int64_t frame_size);

    bool is_first_instance;
};
