#pragma once

#include "AudioSource.h"
#include <mutex>
#include <vector>

// Host-side AudioSource: NullPlayer's audio tap pushes interleaved
// int16 stereo @ 44100 Hz into a ring buffer; Tripex's Effect::Render
// pulls samples per-frame via AudioSource::Read.
//
// Tripex computes its own FFT (Fourier.cpp), so we only need to deliver
// raw PCM. No Hann window / dB normalisation / vDSP work needed Swift-side.

class HostAudioSource : public AudioSource {
public:
    HostAudioSource();
    ~HostAudioSource() override;

    // Producer side (called from Swift via TripexCore_pushPCM).
    void Push(const int16* samples, size_t num_samples);

    // Consumer side — called by Tripex::Render every frame.
    void Read(void* read_data, size_t read_size) override;

private:
    static const size_t RING_CAPACITY = AudioSource::SAMPLE_RATE
                                        * AudioSource::NUM_CHANNELS
                                        * 2; // ~2s @ 44.1kHz stereo

    std::vector<int16> ring_;
    size_t write_pos_;
    size_t read_pos_;
    // Samples available to read. Protected by mutex_ — the outer C ABI lock
    // also serializes producer/consumer, so plain size_t is sufficient.
    size_t available_;
    std::mutex mutex_;
};
