#ifndef CAUDIOTAPRING_H
#define CAUDIOTAPRING_H

/// A single-producer, single-consumer float ring for the visualization cast's audio
/// (`AudioTapRing` in ProcessAudioTap.swift). Core Audio's IO thread writes and the encoder's queue
/// reads; neither blocks, and the writer never allocates. In C for the C11 atomics: Swift's own
/// `Atomic` needs macOS 15 and the app runs on 14.
typedef struct NPAudioTapRing NPAudioTapRing;

/// A ring of `capacity` samples (interleaved stereo, so even). Free with `np_audio_tap_ring_destroy`.
NPAudioTapRing *np_audio_tap_ring_create(long capacity);
void np_audio_tap_ring_destroy(NPAudioTapRing *ring);

/// Writer: `frames` stereo frames, each channel read at its own stride. A full ring drops what does
/// not fit; returns the frames dropped.
long np_audio_tap_ring_write(NPAudioTapRing *ring, const float *left, long leftStride,
                             const float *right, long rightStride, long frames);

/// Reader: first discards all but the newest `keep` samples, then copies up to `count` into `out`
/// and zero-fills the rest. Returns the samples copied.
long np_audio_tap_ring_read(NPAudioTapRing *ring, float *out, long count, long keep);

#endif
