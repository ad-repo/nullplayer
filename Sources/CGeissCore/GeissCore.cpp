#include "GeissCore.h"

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <new>

// Phase 1 stub: no upstream Geiss sources are referenced. This file proves
// the C ABI seam end-to-end with a deterministic XOR pattern and a
// hue-cycling palette. The real Geiss effect core lands in Phase 4.

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

void GeissCore_addPCM(GeissCore * /*core*/, const float * /*samples*/, int /*count*/) {
    // No-op in Phase 1.
}

void GeissCore_setSpectrum(GeissCore * /*core*/, const float * /*mags*/, int /*count*/) {
    // No-op in Phase 1.
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
