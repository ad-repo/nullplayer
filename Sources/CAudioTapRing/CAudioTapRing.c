#include "CAudioTapRing.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct NPAudioTapRing {
    _Atomic long written;   // samples ever written: the writer's alone to advance
    _Atomic long read;      // samples ever read or discarded: the reader's alone to advance
    long capacity;
    float samples[];
};

NPAudioTapRing *np_audio_tap_ring_create(long capacity) {
    NPAudioTapRing *ring = calloc(1, sizeof(NPAudioTapRing) + (size_t)capacity * sizeof(float));
    if (ring) ring->capacity = capacity;
    return ring;
}

void np_audio_tap_ring_destroy(NPAudioTapRing *ring) { free(ring); }

long np_audio_tap_ring_write(NPAudioTapRing *ring, const float *left, long leftStride,
                             const float *right, long rightStride, long frames) {
    long written = atomic_load_explicit(&ring->written, memory_order_relaxed);
    long read = atomic_load_explicit(&ring->read, memory_order_acquire);
    long room = (ring->capacity - (written - read)) / 2;
    long n = frames < room ? frames : room;
    for (long f = 0; f < n; f++) {
        long i = (written + 2 * f) % ring->capacity;
        ring->samples[i] = left[f * leftStride];
        ring->samples[i + 1] = right[f * rightStride];
    }
    atomic_store_explicit(&ring->written, written + 2 * n, memory_order_release);
    return frames - n;
}

long np_audio_tap_ring_read(NPAudioTapRing *ring, float *out, long count, long keep) {
    long read = atomic_load_explicit(&ring->read, memory_order_relaxed);
    long written = atomic_load_explicit(&ring->written, memory_order_acquire);
    if (written - read > keep) read = written - keep;
    long n = written - read < count ? written - read : count;
    long start = read % ring->capacity;
    long head = n < ring->capacity - start ? n : ring->capacity - start;
    memcpy(out, ring->samples + start, (size_t)head * sizeof(float));
    memcpy(out + head, ring->samples, (size_t)(n - head) * sizeof(float));
    memset(out + n, 0, (size_t)(count - n) * sizeof(float));
    atomic_store_explicit(&ring->read, read + n, memory_order_release);
    return n;
}
