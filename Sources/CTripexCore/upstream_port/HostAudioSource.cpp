#include "HostAudioSource.h"
#include <string.h>
#ifndef NDEBUG
#include <stdio.h>
#endif

HostAudioSource::HostAudioSource()
    : ring_(RING_CAPACITY, 0)
    , write_pos_(0)
    , read_pos_(0)
    , available_(0)
{
}

HostAudioSource::~HostAudioSource() {}

void HostAudioSource::Push(const int16* samples, size_t num_samples)
{
    if (!samples || num_samples == 0) return;

    std::lock_guard<std::mutex> lock(mutex_);

    // If pushing more than capacity, keep only the tail.
    if (num_samples >= RING_CAPACITY) {
        samples += (num_samples - RING_CAPACITY);
        num_samples = RING_CAPACITY;
    }

    // Drop oldest samples if we'd overflow.
    if (num_samples > RING_CAPACITY - available_) {
        size_t drop = num_samples - (RING_CAPACITY - available_);
        read_pos_ = (read_pos_ + drop) % RING_CAPACITY;
        available_ -= drop;
    }

    size_t first = std::min(num_samples, RING_CAPACITY - write_pos_);
    memcpy(&ring_[write_pos_], samples, first * sizeof(int16));
    if (first < num_samples) {
        memcpy(&ring_[0], samples + first, (num_samples - first) * sizeof(int16));
    }
    write_pos_ = (write_pos_ + num_samples) % RING_CAPACITY;
    available_ += num_samples;
    // Post-condition: available_ ≤ RING_CAPACITY (drop above guarantees
    // enough free space for the full num_samples write).
}

void HostAudioSource::Read(void* read_data, size_t read_size)
{
    // Tripex passes byte count; convert to int16 samples.
    size_t samples_needed = read_size / sizeof(int16);
    int16* out = (int16*)read_data;

    std::lock_guard<std::mutex> lock(mutex_);
    size_t to_copy = std::min(samples_needed, available_);

    if (to_copy > 0) {
        size_t first = std::min(to_copy, RING_CAPACITY - read_pos_);
        memcpy(out, &ring_[read_pos_], first * sizeof(int16));
        if (first < to_copy) {
            memcpy(out + first, &ring_[0], (to_copy - first) * sizeof(int16));
        }
        read_pos_ = (read_pos_ + to_copy) % RING_CAPACITY;
        available_ -= to_copy;
    }

    // Pad the rest with silence so callers always get the requested size.
    if (to_copy < samples_needed) {
#ifndef NDEBUG
        static size_t s_underrun_count = 0;
        if ((++s_underrun_count % 256) == 1) {
            fprintf(stderr, "[Tripex] HostAudioSource underrun: needed %zu, had %zu (count=%zu)\n",
                    samples_needed, samples_needed - (samples_needed - to_copy), s_underrun_count);
        }
#endif
        memset(out + to_copy, 0, (samples_needed - to_copy) * sizeof(int16));
    }
}
