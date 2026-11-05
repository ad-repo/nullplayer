#pragma once

#include "audio_in.h"

#include "../platform.h"

#include <cstdint>
#include <map>
#include <tuple>
#include <vector>

#define AUDIO_BUFFER_LEN 576

class FFT;  // in "../3rdparty/md_fft.h"

struct AudioChannels {
    float left[AUDIO_BUFFER_LEN];
    float right[AUDIO_BUFFER_LEN];
    float center[AUDIO_BUFFER_LEN];
    void average_center() {
        for (int i = 0; i < AUDIO_BUFFER_LEN; ++i) {
            this->center[i] = (this->left[i] + this->right[i]) / 2.0f;
        }
    }
};

class Audio {
   private:
    struct RingIter;

   public:
    explicit Audio(size_t ring_buffer_length = 1024);
    ~Audio();
    int32_t set(const float* audio_left,
                const float* audio_right,
                size_t audio_length,
                size_t samples_per_second,
                int64_t end_time_in_samples);
    void get(int64_t until_time_samples = 0);
    static void capture_handler(void* data,
                                AudioFrame* audio,
                                size_t samples_per_second,
                                uint32_t num_samples);
    void audio_in_start();
    void audio_in_stop();

    AudioChannels osc{};
    AudioChannels spec{};
    bool is_beat = false;
    void to_legacy_visdata(char visdata[2][2][AUDIO_BUFFER_LEN]);

   private:
    int32_t samples_remaining(int64_t relative_to) const;

    lock_t* lock = nullptr;
    AVS_Audio_Input* audio_in = nullptr;
    /** audio data ring buffer */
    std::vector<AudioFrame> buffer;
    /** index of the latest audio sample */
    size_t write_head;
    int64_t latest_sample_time;
    size_t samples_per_second;
    FFT* fft;
};
