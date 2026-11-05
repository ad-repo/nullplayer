#pragma once

#include <cstddef>
#include <stdint.h>
#include <string>
#include <vector>

struct AudioFrame {
    float left;
    float right;
};

typedef void AVS_Audio_Input;
typedef void (*avs_audio_input_handler)(void* data,
                                        AudioFrame* audio,
                                        size_t samples_per_second,
                                        uint32_t num_samples);

AVS_Audio_Input* audio_in_start(avs_audio_input_handler callback, void* data);
void audio_in_stop(AVS_Audio_Input* audio_in);
std::vector<std::string> audio_in_devices();
bool audio_in_select_device(uint32_t device_index);
