#include "e_root.h"

#include "avs.h"
#include "constants.h"
#include "effect_library.h"
#include "handles.h"
#include "instance.h"
#include "pixel_format.h"
#include "render_context.h"

#include "../3rdparty/WDL-EEL2/eel2/ns-eel.h"

#include <cstdio>

AVS_Instance::AVS_Instance(const char* base_path,
                           AVS_Audio_Source audio_source,
                           AVS_Beat_Source beat_source)
    : handle(h_instances.get()),
      base_path(base_path),
      audio_source(audio_source),
      beat_source(beat_source),
      root(this),
      root_secondary(this),
      transition(this),
      render_lock(lock_init()) {
    make_effect_lib();
    if (this->audio_source == AVS_AUDIO_INTERNAL) {
        this->audio.audio_in_start();
    }
}

AVS_Instance::~AVS_Instance() {
    if (this->audio_source == AVS_AUDIO_INTERNAL) {
        this->audio.audio_in_stop();
    }
    for (auto& effect : this->scrap) {
        delete effect;
    }
    NSEEL_VM_FreeGRAM(&this->eel_state.global_ram);
    lock_destroy(this->render_lock);
    delete this->global_buffers;
    free(this->preset_legacy_save_buffer);
}

bool AVS_Instance::render_frame(void* framebuffer,
                                int64_t time_in_ms,
                                bool is_beat,
                                size_t width,
                                size_t height,
                                AVS_Pixel_Format pixel_format) {
    this->init_global_buffers_if_needed(width, height, pixel_format);
    this->update_time(time_in_ms);
    auto render_context = RenderContext(
        width, height, pixel_format, *this->global_buffers, this->audio, framebuffer);
    this->audio.get();
    if (this->beat_source == AVS_BEAT_EXTERNAL) {
        this->audio.is_beat = is_beat;
    } else if (this->beat_source == AVS_BEAT_INTERNAL && is_beat) {
        log_warn("`is_beat` is set to true but beat_source is AVS_BEAT_INTERNAL");
    }
    this->root.render_with_context(render_context);

    // char visdata[2][2][AUDIO_BUFFER_LEN];
    // this->root.render(
    //     visdata, is_beat, (int*)framebuffer, (int*)framebuffer, width, height);

    return true;
}

void AVS_Instance::init_global_buffers_if_needed(size_t width,
                                                 size_t height,
                                                 AVS_Pixel_Format pixel_format) {
    if (this->global_buffers != nullptr
        && ((*this->global_buffers)[0].w != width
            || (*this->global_buffers)[0].h != height
            || (*this->global_buffers)[0].pixel_format != pixel_format)) {
        delete this->global_buffers;
        this->global_buffers = nullptr;
    }
    if (this->global_buffers == nullptr) {
        this->global_buffers = new std::array<Buffer, AVS_Instance::num_global_buffers>{
            Buffer(width, height, pixel_format),
            Buffer(width, height, pixel_format),
            Buffer(width, height, pixel_format),
            Buffer(width, height, pixel_format),
            Buffer(width, height, pixel_format),
            Buffer(width, height, pixel_format),
            Buffer(width, height, pixel_format),
            Buffer(width, height, pixel_format)};
    }
}

void AVS_Instance::update_time(int64_t time_in_ms) {
    if (time_in_ms >= 0) {  // Video Mode
        if (this->last_time_mode == AVS_TIME_MODE_REALTIME) {
            // Switching time mode during rendering should be rare, but in case it does
            // happen, we want to ensure that
            //   a) time always advances, and
            //   b) the next frame is a meaningful timestep away from the previous one.
            // When switching from realtime to video mode, offset by the previous time,
            // add the new given timestamp and finally subtract 1 so that the first
            // video-mode frame doesn't have the same time as the last realtime frame.
            this->time_mode_switch_offset = -this->current_time_in_ms + time_in_ms - 1;
            log_info("Time mode switch: Realtime -> Video, offset: %lld, time: %lld",
                     this->time_mode_switch_offset,
                     this->current_time_in_ms);
        }
        this->last_time_mode = AVS_TIME_MODE_VIDEO;
        if (time_in_ms > this->current_time_in_ms) {
            this->current_time_in_ms = time_in_ms - this->time_mode_switch_offset;
        } else {
            // This 2ms increment (when the caller doesn't increment) is specified in
            // the API contract in avs.h. Changing this value requires amending the
            // comment in avs.h and probably a version bump too.
            this->current_time_in_ms += 2;
        }
    } else {  // Realtime Mode
        if (this->last_time_mode == AVS_TIME_MODE_VIDEO) {
            // See above about switching time modes.
            // When switching from video to realtime mode, similar requirements apply.
            // Offset by the previous time, add the current realtime and subtract 1.
            this->time_mode_switch_offset = -this->current_time_in_ms + timer_ms() - 1;
            log_info("Time mode switch: Video -> Realtime, offset: %lld, time: %lld",
                     this->time_mode_switch_offset,
                     this->current_time_in_ms);
        }
        this->last_time_mode = AVS_TIME_MODE_REALTIME;
        this->current_time_in_ms = timer_ms() - this->time_mode_switch_offset;
    }
}

int32_t AVS_Instance::audio_set(const float* audio_left,
                                const float* audio_right,
                                size_t audio_length,
                                size_t samples_per_second,
                                int64_t end_time_samples) {
    if (this->audio_source == AVS_AUDIO_INTERNAL) {
        this->error = "audio_set() is not supported with AVS_AUDIO_INTERNAL";
        return -1;
    }
    return this->audio.set(
        audio_left, audio_right, audio_length, samples_per_second, end_time_samples);
}

int32_t AVS_Instance::audio_device_count() { return 1; }

const char* const* AVS_Instance::audio_device_names() { return this->audio_devices; }

void AVS_Instance::audio_device_set(int32_t device) {}

bool AVS_Instance::preset_load_file(const char* file_path, bool with_transition) {
    bool success = false;
    FILE* fp = fopen(file_path, "rb");
    if (fp != nullptr) {
        fseek(fp, 0, SEEK_END);
        size_t len = ftell(fp);
        fseek(fp, 0, SEEK_SET);
        if (len > MAX_LEGACY_PRESET_FILESIZE_BYTES) {
            len = MAX_LEGACY_PRESET_FILESIZE_BYTES;
        }
        auto data = (uint8_t*)calloc(len, 1);
        if (data == nullptr) {
            fclose(fp);
            this->error = "out of memory while loading preset file: ";
            this->error += file_path;
            return success;
        }
        if (!fread(data, 1, len, fp)) {
            len = 0;
        }
        fclose(fp);
        success = this->preset_load_legacy(data, len, with_transition);
        if (!success) {
            std::string preset_string((char*)data, len);
            success = this->preset_load(preset_string, with_transition);
        }
        free(data);
    } else {
        this->error = "Cannot open file for reading: ";
        this->error += file_path;
    }
    return success;
}

bool AVS_Instance::preset_load(const std::string& preset, bool with_transition) {
    try {
        auto preset_root = json::parse(preset, nullptr, true, true);
        this->clear_secondary();
        this->root_secondary.load(preset_root);
    } catch (const std::exception& e) {
        log_err("error loading json preset: %s", e.what());
        this->error = e.what();
        this->clear_secondary();
        return false;
    }
    lock_lock(this->render_lock);
    this->root.swap(this->root_secondary);
    lock_unlock(this->render_lock);
    // this->root.print_tree();
    return true;
}

bool AVS_Instance::preset_load_legacy(const uint8_t* preset,
                                      size_t preset_length,
                                      bool with_transition) {
    auto file_magic_length = strlen(AVS_Instance::legacy_file_magic);
    if (preset_length > file_magic_length + 2
        && !memcmp(preset, AVS_Instance::legacy_file_magic, file_magic_length - 2)
        && preset[file_magic_length - 2] >= '1' && preset[file_magic_length - 2] <= '2'
        && preset[file_magic_length - 1] == '\x1a') {
        this->clear_secondary();
        //                               trustmebro! (i.e. TODO: make data param const)
        this->root_secondary.load_legacy((unsigned char*)preset + file_magic_length,
                                         (int)(preset_length - file_magic_length));
        if (with_transition) {
            // unimplemented!
            // this->transition.do_transition();
        }
        lock_lock(this->render_lock);
        this->root.swap(this->root_secondary);
        lock_unlock(this->render_lock);
        // NullPlayer: debug dump of the whole tree to stdout on every legacy load, disabled
        // like the JSON loader's above.
        // this->root.print_tree();
        return true;
    }
    return false;
}

bool AVS_Instance::preset_save_file(const char* file_path, bool as_remix, bool indent) {
    auto preset_str = this->preset_save(as_remix, indent);
    FILE* fp = fopen(file_path, "wb");
    if (fp != nullptr) {
        fwrite(preset_str, 1, strlen(preset_str), fp);
        fclose(fp);
        return true;
    } else {
        this->error = "cannot open file for writing: ";
        this->error += file_path;
    }
    return false;
}

int AVS_Instance::preset_save_file_legacy(const char* file_path) {
    int result = -1;
    size_t size = 0;
    auto data = this->preset_save_legacy(&size);
    if (size < MAX_LEGACY_PRESET_FILESIZE_BYTES) {
        FILE* fp = fopen(file_path, "wb");
        if (fp != nullptr) {
            result = 0;
            fwrite(data, 1, size, fp);
            fclose(fp);
        } else {
            result = 2;
        }
    } else {
        result = 1;
    }
    return result;
}

const char* AVS_Instance::preset_save(bool as_remix, bool indent) {
    json j;
    j["preset format version"] = "0";
    j["avs version"] = "2.81.4";
    if (as_remix) {
        this->root.remix();
    }
    this->root.config.date_last = current_date_str();
    try {
        j.update(this->root.save());
        j.erase("effect");
        this->preset_save_buffer =
            j.dump(4, ' ', false, json::error_handler_t::replace) + "\n";
    } catch (const std::exception& err) {
        this->error = err.what();
        return nullptr;
    }
    return this->preset_save_buffer.c_str();
}

const uint8_t* AVS_Instance::preset_save_legacy(size_t* preset_length_out,
                                                bool secondary) {
    if (this->preset_legacy_save_buffer == nullptr) {
        this->preset_legacy_save_buffer =
            (uint8_t*)calloc(MAX_LEGACY_PRESET_FILESIZE_BYTES, sizeof(uint8_t));
    }
    size_t pos = 0;
    if (this->preset_legacy_save_buffer != nullptr && preset_length_out != nullptr) {
        auto file_magic_length = strlen(AVS_Instance::legacy_file_magic);
        memcpy(this->preset_legacy_save_buffer,
               AVS_Instance::legacy_file_magic,
               file_magic_length);
        pos += file_magic_length;
        auto legacy_preset_content =
            this->preset_legacy_save_buffer + file_magic_length;
        lock_lock(this->render_lock);
        if (secondary) {
            pos += this->root_secondary.save_legacy(legacy_preset_content);
        } else {
            pos += this->root.save_legacy(legacy_preset_content);
        }
        lock_unlock(this->render_lock);
    }
    *preset_length_out = pos;
    return this->preset_legacy_save_buffer;
}

void AVS_Instance::clear() { this->root = E_Root(this); }
void AVS_Instance::clear_secondary() { this->root_secondary = E_Root(this); }

const char* AVS_Instance::error_str() { return this->error.c_str(); }

bool AVS_Instance::undo() { return false; }
bool AVS_Instance::redo() { return false; }

Effect* AVS_Instance::get_component_from_handle(AVS_Component_Handle component) {
    return this->root.find_by_handle(component);
}

void* AVS_Instance::get_buffer(size_t, size_t, int32_t buffer_num, bool) {
    if (buffer_num >= 0 && (uint32_t)buffer_num <= AVS_Instance::num_global_buffers) {
        return (*this->global_buffers)[buffer_num].data;
    }
    return nullptr;
}

int64_t AVS_Instance::get_current_time_in_ms() { return this->current_time_in_ms; }

bool AVS_Instance::get_key_state(uint32_t key) {
    if (key >= 0 && key < sizeof(this->key_states) / sizeof(this->key_states[0])) {
        return this->key_states[key];
    }
    return false;
}
bool AVS_Instance::set_key_state(uint32_t key, bool state) {
    if (key >= 0 && key < sizeof(this->key_states) / sizeof(this->key_states[0])) {
        this->key_states[key] = state;
        return true;
    }
    return false;
}
double AVS_Instance::get_mouse_pos(bool get_y) {
    if (get_y) {
        return this->mouse_y;
    }
    return this->mouse_x;
}
void AVS_Instance::set_mouse_pos(double x, double y) {
    this->mouse_x = x;
    this->mouse_y = y;
}
bool AVS_Instance::get_mouse_button_state(uint32_t button) {
    if (button >= 0
        && button < sizeof(this->mouse_button_states)
                        / sizeof(this->mouse_button_states[0])) {
        return this->mouse_button_states[button];
    }
    return false;
}
bool AVS_Instance::set_mouse_button_state(uint32_t button, bool state) {
    if (button >= 0
        && button < sizeof(this->mouse_button_states)
                        / sizeof(this->mouse_button_states[0])) {
        this->mouse_button_states[button] = state;
        return true;
    }
    return false;
}

void AVS_Instance::EelState::error(const char* error_str) {
    lock_lock(this->errors_lock);
    this->error_ring[this->error_ring_head] = error_str;
    if (++this->error_ring_head >= this->num_errors) {
        this->error_ring_head = 0;
    }
    lock_unlock(this->errors_lock);
}

void AVS_Instance::EelState::clear_errors() {
    lock_lock(this->errors_lock);
    for (size_t i = 0; i < this->num_errors; i++) {
        this->error_ring[i].clear();
    }
    this->error_ring_head = 0;
    lock_unlock(this->errors_lock);
}

void AVS_Instance::EelState::errors_to_str(char** errors_out, size_t* out_len) {
    lock_lock(this->errors_lock);
    size_t len = 0;
    for (size_t i = 0; i < this->num_errors; i++) {
        len += this->error_ring[i].size() + 1;
    }
    if (len == 0) {
        *errors_out = nullptr;
        *out_len = 0;
        lock_unlock(this->errors_lock);
        return;
    }
    *errors_out = (char*)calloc(len + this->num_errors, 1);
    if (*errors_out == nullptr) {
        *out_len = 0;
        lock_unlock(this->errors_lock);
        return;
    }
    char* out = *errors_out;
    for (size_t i = 0; i < this->num_errors; i++) {
        auto error = this->error_ring[(this->error_ring_head + i) % this->num_errors];
        if (error.empty()) {
            continue;
        }
        memcpy(out, error.c_str(), error.size());
        out += error.size() + 1;
        out[-1] = '\n';
    }
    *out_len = len;
    lock_unlock(this->errors_lock);
}
