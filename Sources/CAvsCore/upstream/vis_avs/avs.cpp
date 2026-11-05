#include "avs.h"

#include "avs_eelif.h"
#include "avs_internal.h"
#include "blend.h"
#include "effect_library.h"
#include "instance.h"
#include "preset_json_schema.h"

#include <stdio.h>
#include <stdlib.h>
#include <unordered_map>

#ifdef __linux__
#define AVS_API __attribute__((visibility("default")))
#else
#define AVS_API
#endif

std::unordered_map<AVS_Handle, AVS_Instance*> g_instances;
const char* g_error = "";
unsigned char g_blendtable[256][256];

uint64_t const mmx_blend4_revn = 0x00ff00ff00ff00ff;
// {0x1000100,0x1000100}; <<- this is actually more correct, but we're going for
// consistency vs. the non-mmx ver-jf
uint64_t const mmx_blendadj_mask = 0x00ff00ff00ff00ff;
int const mmx_blend4_zero = 0;

AVS_Instance* get_instance_from_handle(AVS_Handle avs) {
    if (avs > 0) {
        auto search = g_instances.find(avs);
        if (search != g_instances.end()) {
            g_error = NULL;
            return search->second;
        }
    }
    g_error = "Invalid AVS handle";
    return NULL;
}

AVS_API
AVS_Handle avs_init(const char* base_path,
                    AVS_Audio_Source audio_source,
                    AVS_Beat_Source beat_source) {
    if (g_instances.empty()) {
        make_effect_lib();
        make_blend_LUTs();
    }
    for (int j = 0; j < 256; j++) {
        for (int i = 0; i < 256; i++) {
            g_blendtable[i][j] = (unsigned char)((i / 255.0) * (float)j);
        }
    }
    if (base_path == nullptr) {
        base_path = ".";
    }
    auto new_instance = new AVS_Instance(base_path, audio_source, beat_source);
    if (new_instance->handle == 0) {
        g_error = "AVS handles exhausted (try unloading the library and reloading it)";
        return 0;
    }
    g_instances[new_instance->handle] = new_instance;
    AVS_EEL_IF_init(new_instance);
    g_error = NULL;
    return new_instance->handle;
}

AVS_API
bool avs_render_frame(AVS_Handle avs,
                      void* framebuffer,
                      size_t width,
                      size_t height,
                      int64_t time_in_ms,
                      bool is_beat,
                      AVS_Pixel_Format pixel_format) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == NULL) {
        return false;
    }
    if (framebuffer == nullptr) {
        instance->error = "Framebuffer must not be NULL";
        return false;
    }
    return instance->render_frame(
        framebuffer, time_in_ms, is_beat, width, height, pixel_format);
}

AVS_API
int32_t avs_audio_set(AVS_Handle avs,
                      const float* left,
                      const float* right,
                      size_t audio_length,
                      size_t samples_per_second,
                      int64_t end_time_samples) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == nullptr) {
        return -1;
    }
    return instance->audio_set(
        left, right, audio_length, samples_per_second, end_time_samples);
}

AVS_API
int32_t avs_audio_device_count(AVS_Handle avs) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == NULL) {
        return NULL;
    }
    if (instance->audio_source == AVS_AUDIO_EXTERNAL) {
        instance->error = "Audio source set to external on init";
        return -1;
    }
    // return instance->audio_device_count();
    instance->error = "Audio device enumeration not implemented";
    return -1;
}
AVS_API
const char* const* avs_audio_device_names(AVS_Handle avs) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == NULL) {
        return NULL;
    }
    if (instance->audio_source == AVS_AUDIO_EXTERNAL) {
        instance->error = "Audio source set to external on init";
        return NULL;
    }
    // return instance->audio_device_names();
    instance->error = "Audio device enumeration not implemented";
    return NULL;
}
AVS_API
bool avs_audio_device_set(AVS_Handle avs, int32_t device) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == NULL) {
        return false;
    }
    if (instance->audio_source == AVS_AUDIO_EXTERNAL) {
        return true;
    }
    // return instance->audio_device_set(device);
    instance->error = "Audio device selection not implemented";
    return false;
}

AVS_API
bool avs_input_key_set(AVS_Handle avs, uint32_t key, bool state) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == NULL) {
        return false;
    }
    return instance->set_key_state(key, state);
}
AVS_API
bool avs_input_mouse_pos_set(AVS_Handle avs, double x, double y) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == NULL) {
        return false;
    }
    instance->set_mouse_pos(x, y);
    return true;
}
AVS_API
bool avs_input_mouse_button_set(AVS_Handle avs, uint32_t button, bool state) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == NULL) {
        return false;
    }
    return instance->set_mouse_button_state(button, state);
}

AVS_API
bool avs_preset_load(AVS_Handle avs, const char* file_path) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == nullptr) {
        return false;
    }
    // TODO [feature]: with transition
    return instance->preset_load_file(file_path);
}
AVS_API
bool avs_preset_set(AVS_Handle avs, const char* preset) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == nullptr) {
        return false;
    }
    // TODO [feature]: with transition
    return instance->preset_load(preset, false);
}
AVS_API
bool avs_preset_save(AVS_Handle avs,
                     const char* file_path,
                     bool as_remix,
                     bool indent) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == nullptr) {
        return false;
    }
    return instance->preset_save_file(file_path, as_remix, indent);
}
AVS_API
const char* avs_preset_get(AVS_Handle avs, bool as_remix, bool indent) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == nullptr) {
        return nullptr;
    }
    return instance->preset_save(as_remix, indent);
}
AVS_API
bool avs_preset_set_legacy(AVS_Handle avs,
                           const uint8_t* preset,
                           size_t preset_length) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == nullptr) {
        return false;
    }
    // TODO [feature]: with transition
    return instance->preset_load_legacy(preset, preset_length, false);
}
AVS_API
const uint8_t* avs_preset_get_legacy(AVS_Handle avs, size_t* preset_length_out) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == nullptr) {
        return nullptr;
    }
    return instance->preset_save_legacy(preset_length_out);
}
AVS_API
bool avs_preset_save_legacy(AVS_Handle avs, const char* file_path) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == nullptr) {
        return false;
    }
    auto result = instance->preset_save_file_legacy(file_path);
    if (result == 1) {
        g_error = "Preset too large to save in legacy format";
    } else if (result == 2) {
        g_error = "Failed to open legacy preset file";
    } else if (result == -1) {
        g_error = "Unknown error during legacy file save";
    }
    return result == 0;
}

AVS_API
const char* avs_preset_format_schema() {
    static std::string schema = preset_json_schema("avs.sh");
    return schema.c_str();
}

AVS_API
const char* avs_error_str(AVS_Handle avs) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == NULL) {
        return g_error;
    } else {
        return instance->error_str();
    }
}

AVS_API
void avs_free(AVS_Handle avs) {
    if (avs == 0) {
        return;
    }
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance != NULL) {
        g_instances.erase(avs);
        delete instance;
    }
}

// TODO [build]: These fields should be set by the build system. For now set them here.
#define AVS_VERSION_MAJOR   2
#define AVS_VERSION_MINOR   81
#define AVS_VERSION_PATCH   4  // It's actually "d", but SemVer can't have letters.
#define AVS_VERSION_RC      0
#define AVS_VERSION_COMMIT  "..................."
#define AVS_VERSION_CHANGES "..................."

AVS_API
AVS_Version avs_version() {
    return AVS_Version{AVS_VERSION_MAJOR,
                       AVS_VERSION_MINOR,
                       AVS_VERSION_PATCH,
                       AVS_VERSION_RC,
                       AVS_VERSION_COMMIT,
                       AVS_VERSION_CHANGES};
}
