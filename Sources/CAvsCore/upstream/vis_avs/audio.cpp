#include "audio.h"

#include "../3rdparty/md_fft.h"

#include <cmath>
#include <cstdio>
#include <cstring>

// The `ring` member is supposed to be used as the pointer into the ring buffer, while
// the `linear` member is supposed to be used as the pointer into the linear source or
// destination buffer.
struct Audio::RingIter {
    RingIter(size_t length, size_t from, bool reverse = false)
        : length((int64_t)length),
          ring((int64_t)(from % length)),
          linear(reverse ? length - 1 : 0),
          reverse(reverse) {
        // printf("RingIter: %ld %ld %d\n", length, from, reverse);
    }
    int64_t length;
    int64_t ring;
    size_t linear;
    size_t reverse;
    RingIter& operator++() {
        if (this->length == 0) {
            return *this;
        }
        if (this->reverse) {
            --this->ring;
            while (this->ring < 0) {
                this->ring += this->length;
            }
            --this->linear;
        } else {
            ++this->ring;
            while (this->ring >= this->length) {
                this->ring -= this->length;
            }
            ++this->linear;
        }
        return *this;
    }
};

Audio::Audio(size_t ring_buffer_length)
    : lock(lock_init()),
      write_head(0),
      latest_sample_time(0),
      samples_per_second(0),
      fft(new FFT()) {
    this->buffer.resize(ring_buffer_length, {0, 0});
    if (this->fft) {
        this->fft->Init(ring_buffer_length,
                        ring_buffer_length,
                        1.0f,  // equalize
                        1.0f   // window-function exponent
        );
    }
}

Audio::~Audio() {
    lock_destroy(this->lock);
    if (this->fft) {
        this->fft->CleanUp();
    }
    delete this->fft;
}

void Audio::get(int64_t until_time_samples) {
    size_t dest_back_offset = 0;
    if (until_time_samples == 0) {
        until_time_samples = this->latest_sample_time;
    } else if (until_time_samples > this->latest_sample_time) {
        auto silence_samples = until_time_samples - this->latest_sample_time;
        dest_back_offset += silence_samples;
        auto dest_silence_start = AUDIO_BUFFER_LEN - silence_samples;
        memset(&this->osc.left[dest_silence_start], 0, silence_samples * sizeof(float));
        memset(
            &this->osc.right[dest_silence_start], 0, silence_samples * sizeof(float));
        memset(
            &this->spec.left[dest_silence_start], 0, silence_samples * sizeof(float));
        memset(
            &this->spec.right[dest_silence_start], 0, silence_samples * sizeof(float));
    }
    for (RingIter it(this->buffer.size() - dest_back_offset, this->write_head, true);
         it.linear > dest_back_offset;
         ++it) {
        this->osc.left[it.linear - dest_back_offset] = this->buffer[it.ring].left;
        this->osc.right[it.linear - dest_back_offset] = this->buffer[it.ring].right;
    }
    this->fft->time_to_frequency_domain(this->osc.left, this->spec.left);
    this->fft->time_to_frequency_domain(this->osc.right, this->spec.right);
    this->osc.average_center();
    this->spec.average_center();
}

int32_t Audio::set(const float* audio_left,
                   const float* audio_right,
                   size_t audio_length,
                   size_t samples_per_second,
                   int64_t end_time_samples) {
    // NullPlayer: upstream debug printf removed; it ran on every audio buffer.
    auto remaining = this->samples_remaining(end_time_samples);
    if (audio_length != 0 && this->latest_sample_time < end_time_samples) {
        if (audio_left == nullptr || audio_right == nullptr
            || samples_per_second == 0) {
            return -1;
        }
        size_t source_audio_offset = 0;
        if (audio_length > this->buffer.capacity()) {
            source_audio_offset = audio_length - this->buffer.capacity();
        }
        lock_lock(this->lock);
        if (this->samples_per_second != samples_per_second) {
            this->write_head = 0;
            this->buffer.clear();
            this->buffer.resize(this->buffer.capacity(), {0, 0});
        }
        this->samples_per_second = samples_per_second;
        for (RingIter it(this->buffer.capacity(), this->write_head);
             it.linear < audio_length;
             ++it, ++this->write_head) {
            this->buffer[it.ring].left =
                fminf(1.0, fmaxf(-1.0, audio_left[source_audio_offset + it.linear]));
            this->buffer[it.ring].right =
                fminf(1.0, fmaxf(-1.0, audio_right[source_audio_offset + it.linear]));
        }
        this->latest_sample_time = end_time_samples;
        lock_unlock(this->lock);
    }
    return remaining;
}

void Audio::to_legacy_visdata(char visdata[2][2][AUDIO_BUFFER_LEN]) {
    for (int i = 0; i < AUDIO_BUFFER_LEN; ++i) {
        auto ileft = (int8_t)(this->osc.left[i] * 127.0f);
        auto iright = (int8_t)(this->osc.right[i] * 127.0f);
        visdata[1 /*osc*/][0][i] = ileft;
        visdata[1 /*osc*/][1][i] = iright;
    }
    for (int i = 0; i < AUDIO_BUFFER_LEN; ++i) {
        auto ileft = (uint8_t)(this->spec.left[i] * 255.0f);
        auto iright = (uint8_t)(this->spec.right[i] * 255.0f);
        visdata[0 /*spec*/][0][i] = (int8_t)ileft;
        visdata[0 /*spec*/][1][i] = (int8_t)iright;
    }
}

int32_t Audio::samples_remaining(int64_t relative_to) const {
    if (this->samples_per_second == 0) {
        return -1;
    }
    return (int32_t)(relative_to - this->latest_sample_time);
}

void Audio::capture_handler(void* data,
                            AudioFrame* audio_data,
                            size_t samples_per_second,
                            uint32_t num_samples) {
    auto audio = (Audio*)data;
    for (RingIter it(audio->buffer.capacity(), audio->write_head);
         it.linear < num_samples;
         ++it, ++audio->write_head) {
        audio->buffer[it.ring] = audio_data[it.linear];
    }
}

void Audio::audio_in_start() {
    if (this->audio_in == nullptr) {
        this->audio_in = ::audio_in_start(capture_handler, this);
    }
}

void Audio::audio_in_stop() {
    if (this->audio_in != nullptr) {
        ::audio_in_stop(this->audio_in);
    }
}
