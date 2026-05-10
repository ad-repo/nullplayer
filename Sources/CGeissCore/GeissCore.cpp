#include "GeissCore.h"

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <new>

#if defined(__APPLE__)
#include <mach/mach_time.h>
#else
#include <time.h>
#endif

// Phase 1 stub: no upstream Geiss sources are referenced. This file proves
// the C ABI seam end-to-end with a deterministic XOR pattern and a
// hue-cycling palette. The real Geiss effect core lands in Phase 4.
//
// Phase 3: introduces `geiss_now_ms()` (replacement for Win32 `GetTickCount`)
// and `GeissAudioState` (replacement for Winamp's `vis.h` host audio struct).
// Both are declared with C linkage so the upstream effect core can call them
// once it is added to the build in phase 4.

// ---------------------------------------------------------------------------
// Phase 3: monotonic millisecond clock — replaces Win32 GetTickCount.
// ---------------------------------------------------------------------------

extern "C" uint32_t geiss_now_ms(void);

extern "C" uint32_t geiss_now_ms(void) {
#if defined(__APPLE__)
    static mach_timebase_info_data_t tb = {0, 0};
    if (tb.denom == 0) {
        mach_timebase_info(&tb);
    }
    uint64_t ns = mach_absolute_time() * (uint64_t)tb.numer / (uint64_t)tb.denom;
    return (uint32_t)(ns / 1000000ULL);
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)((uint64_t)ts.tv_sec * 1000ULL + (uint64_t)ts.tv_nsec / 1000000ULL);
#endif
}

// ---------------------------------------------------------------------------
// Phase 3: GeissAudioState replaces Winamp 2 vis SDK's host-supplied buffers.
// Layout matches the Winamp `vis.h` `winampVisModule` audio fields the upstream
// code reads: signed 8-bit waveform per channel, 8-bit magnitude spectrum per
// channel, 576 bins each. Phase 4 routes upstream reads of `mod->waveformData`
// / `mod->spectrumData` through this struct.
// ---------------------------------------------------------------------------

#define GEISS_AUDIO_BINS 576

extern "C" {
    struct GeissAudioState {
        unsigned char waveformData[2][GEISS_AUDIO_BINS];
        unsigned char spectrumData[2][GEISS_AUDIO_BINS];
    };
}

static GeissAudioState g_geiss_audio = {};

extern "C" GeissAudioState *geiss_audio_state(void);
extern "C" GeissAudioState *geiss_audio_state(void) { return &g_geiss_audio; }

struct GeissCore {
    int width;
    int height;
    uint64_t tick;
};

extern "C" {

GeissCore *GeissCore_create(int width, int height) {
    if (width <= 0 || height <= 0) return nullptr;
    GeissCore *core = new (std::nothrow) GeissCore{};
    if (!core) return nullptr;
    core->width = width;
    core->height = height;
    core->tick = 0;
    return core;
}

void GeissCore_destroy(GeissCore *core) {
    delete core;
}

void GeissCore_resize(GeissCore *core, int width, int height) {
    if (!core || width <= 0 || height <= 0) return;
    core->width = width;
    core->height = height;
}

void GeissCore_addPCM(GeissCore * /*core*/, const float *samples, int count) {
    // Convert mono Float32 PCM (range roughly [-1, 1]) into the signed-8-bit
    // waveform layout the upstream Geiss code expects (range [-128, 127],
    // stored unsigned to match the original char-array typing). Duplicate into
    // both channels so legacy code that averages L+R still sees mono input.
    if (!samples || count <= 0) return;
    const int n = (count > GEISS_AUDIO_BINS) ? GEISS_AUDIO_BINS : count;
    for (int i = 0; i < n; ++i) {
        float s = samples[i];
        if (s >  1.0f) s =  1.0f;
        if (s < -1.0f) s = -1.0f;
        unsigned char b = (unsigned char)(int)(s * 127.0f);
        g_geiss_audio.waveformData[0][i] = b;
        g_geiss_audio.waveformData[1][i] = b;
    }
}

void GeissCore_setSpectrum(GeissCore * /*core*/, const float *mags, int count) {
    // Spectrum is computed by the Swift side via Accelerate (vDSP_fft_zrip)
    // and pushed through this entry point. Quantize to 8-bit per Winamp
    // convention; duplicate into both channels.
    if (!mags || count <= 0) return;
    const int n = (count > GEISS_AUDIO_BINS) ? GEISS_AUDIO_BINS : count;
    for (int i = 0; i < n; ++i) {
        float m = mags[i];
        if (m < 0.0f)   m = 0.0f;
        if (m > 1.0f)   m = 1.0f;
        unsigned char b = (unsigned char)(int)(m * 255.0f);
        g_geiss_audio.spectrumData[0][i] = b;
        g_geiss_audio.spectrumData[1][i] = b;
    }
}

void GeissCore_render(GeissCore *core, unsigned char *indexBuf) {
    if (!core || !indexBuf) return;
    const int w = core->width;
    const int h = core->height;
    const unsigned int t = static_cast<unsigned int>(core->tick & 0xFFu);
    for (int y = 0; y < h; ++y) {
        unsigned char *row = indexBuf + static_cast<size_t>(y) * static_cast<size_t>(w);
        for (int x = 0; x < w; ++x) {
            row[x] = static_cast<unsigned char>(((static_cast<unsigned int>(x) ^ static_cast<unsigned int>(y) ^ t) & 0xFFu));
        }
    }
    ++core->tick;
}

// Convert HSV (h,s,v in [0,1]) to RGB bytes.
static void hsv_to_rgb(float h, float s, float v, unsigned char *r, unsigned char *g, unsigned char *b) {
    float hh = h * 6.0f;
    int i = static_cast<int>(std::floor(hh));
    float f = hh - static_cast<float>(i);
    float p = v * (1.0f - s);
    float q = v * (1.0f - s * f);
    float t = v * (1.0f - s * (1.0f - f));
    float rf = 0, gf = 0, bf = 0;
    switch (i % 6) {
        case 0: rf = v; gf = t; bf = p; break;
        case 1: rf = q; gf = v; bf = p; break;
        case 2: rf = p; gf = v; bf = t; break;
        case 3: rf = p; gf = q; bf = v; break;
        case 4: rf = t; gf = p; bf = v; break;
        case 5: rf = v; gf = p; bf = q; break;
    }
    *r = static_cast<unsigned char>(rf * 255.0f);
    *g = static_cast<unsigned char>(gf * 255.0f);
    *b = static_cast<unsigned char>(bf * 255.0f);
}

void GeissCore_palette(GeissCore *core, unsigned char *rgbaOut) {
    if (!core || !rgbaOut) return;
    // Hue offset advances slowly (one full rotation every ~256 frames at 60fps).
    float offset = static_cast<float>(core->tick) / 256.0f;
    for (int i = 0; i < 256; ++i) {
        float h = std::fmod(static_cast<float>(i) / 256.0f + offset, 1.0f);
        unsigned char r, g, b;
        hsv_to_rgb(h, 1.0f, 1.0f, &r, &g, &b);
        rgbaOut[i * 4 + 0] = r;
        rgbaOut[i * 4 + 1] = g;
        rgbaOut[i * 4 + 2] = b;
        rgbaOut[i * 4 + 3] = 255;
    }
}

void GeissCore_nextEffect(GeissCore * /*core*/)   { /* no-op */ }
void GeissCore_prevEffect(GeissCore * /*core*/)   { /* no-op */ }
void GeissCore_randomEffect(GeissCore * /*core*/) { /* no-op */ }

const char *GeissCore_currentEffectName(GeissCore * /*core*/) {
    return "Stub Effect";
}

} // extern "C"
