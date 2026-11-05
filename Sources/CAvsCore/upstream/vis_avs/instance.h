#pragma once

#include "c_transition.h"
#include "e_root.h"

#include "audio.h"
#include "avs.h"
#include "avs_editor.h"
#include "effect.h"
#include "effect_info.h"
#include "render_context.h"

#include "../platform.h"

#include <string>

class AVS_Instance {
   public:
    AVS_Instance(const char* base_path,
                 AVS_Audio_Source audio_source,
                 AVS_Beat_Source beat_source);
    ~AVS_Instance();

    bool render_frame(void* framebuffer,
                      int64_t time_in_ms,
                      bool is_beat,
                      size_t width,
                      size_t height,
                      AVS_Pixel_Format pixel_format);
    int32_t audio_set(const float* audio_left,
                      const float* audio_right,
                      size_t audio_length,
                      size_t samples_per_second,
                      int64_t end_time_ms);
    int32_t audio_device_count();
    const char* const* audio_device_names();
    void audio_device_set(int32_t device);
    bool preset_load_file(const char* file_path, bool with_transition = false);
    bool preset_load(const std::string& preset, bool with_transition = false);
    bool preset_load_legacy(const uint8_t* preset,
                            size_t preset_length,
                            bool with_transition = false);
    bool preset_save_file(const char* file_path,
                          bool as_remix = false,
                          bool indent = false);
    int preset_save_file_legacy(const char* file_path);
    /** Allocate 1 MiB of memory at `data`. Return value is the actual size. */
    const uint8_t* preset_save_legacy(size_t* preset_length_out,
                                      bool secondary = false);
    const char* preset_save(bool as_remix = false, bool indent = false);
    void clear();
    void clear_secondary();
    const char* error_str();
    bool undo();
    bool redo();

    Effect_Info* get_effect_from_handle(AVS_Effect_Handle effect);
    Effect* get_component_from_handle(AVS_Component_Handle component);

    void* get_buffer(size_t w,
                     size_t h,
                     int32_t buffer_num,
                     bool allocate_if_needed = false);
    void init_global_buffers_if_needed(size_t width,
                                       size_t height,
                                       AVS_Pixel_Format pixel_format);

    void update_time(int64_t time_in_ms);

    int64_t get_current_time_in_ms();
    bool get_key_state(uint32_t key);
    bool set_key_state(uint32_t key, bool state);
    double get_mouse_pos(bool get_y);
    void set_mouse_pos(double x, double y);
    bool get_mouse_button_state(uint32_t button);
    bool set_mouse_button_state(uint32_t button, bool state);

    AVS_Handle handle;

    std::string base_path;
    AVS_Audio_Source audio_source;
    AVS_Beat_Source beat_source;
    Audio audio;
    std::string error;
    const char* audio_devices[1] = {""};

    E_Root root;
    /** Used for transitioning between presets. */
    E_Root root_secondary;
    std::vector<Effect*> scrap;
    Transition transition;

    lock_t* render_lock;

    struct EelState {
        EelState() : errors_lock(lock_init()) {}
        ~EelState() { lock_destroy(this->errors_lock); }
        /* Global memory for such things as gmegabuf & regXX vars. Usually shared among
           all EEL VMs (i.e. an intra-effect shared code context) but we need separation
           per AVS instance. */
        // NullPlayer: these four were left uninitialised; global_ram is freed and the hooks
        // are called before anything sets them, so garbage crashed avs_free / compiles.
        void* global_ram = nullptr;
        char visdata[2][2][AUDIO_BUFFER_LEN] = {};
        bool log_errors = false;
        const char* (*pre_compile_hook)(void* ctx, char* code, void* avs_instance) = nullptr;
        void (*post_compile_hook)(void* avs_instance) = nullptr;

        void error(const char* error_str);
        void clear_errors();
        void errors_to_str(char** out, size_t* out_len);
        size_t error_state() { return this->error_ring_head; }

       private:
        lock_t* errors_lock;
        static constexpr size_t num_errors = 16;
        std::string error_ring[num_errors];
        size_t error_ring_head = 0;
    };
    EelState eel_state;

   private:
    static constexpr char const* legacy_file_magic = "Nullsoft AVS Preset 0.2\x1a";
    static constexpr size_t num_global_buffers = 8;
    std::array<Buffer, num_global_buffers>* global_buffers = nullptr;
    std::string preset_save_buffer;
    uint8_t* preset_legacy_save_buffer = nullptr;

    enum AVS_TimeMode {
        AVS_TIME_MODE_UNKNOWN = -1,
        AVS_TIME_MODE_REALTIME = 0,
        AVS_TIME_MODE_VIDEO = 1,
    };
    int64_t current_time_in_ms = -1;
    int last_time_mode = AVS_TIME_MODE_UNKNOWN;
    int64_t time_mode_switch_offset = 0;

    bool key_states[256];
    double mouse_x = 0.0;
    double mouse_y = 0.0;
    bool mouse_button_states[8];
};
