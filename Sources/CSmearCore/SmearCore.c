// NullPlayer's shim over Smear 1.2 (upstream/, see upstream/LICENSE.TXT): replaces the Sonique
// plugin entry points (QueryModule/visRender) and smearapi's script selection.

#include "SmearCore.h"
#include "smear.h"
#include <time.h>

extern void smearRender(SmearState *, uint32_t *Video, int width, int height, int pitch);

/// The frame smearRender draws (0x00RRGGBB) and the RGBA bytes handed out.
typedef struct {
    SmearState state;
    uint32_t *video;
    size_t videoSize;
} Core;

int smearNow(SmearState *s) {
    return (int)((clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - s->startNs) / 1000000);
}

SmearCore *SmearCore_create(const char *scriptsDirectory) {
    Core *core = calloc(1, sizeof(Core));
    if (!core) return NULL;
    SmearState *s = &core->state;
    s->startNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    s->mapWidth = s->mapHeight = -1;
    s->sbWidth = s->sbHeight = -1;
    s->lineLastWidth = s->lineLastHeight = s->lineLastLine = -1;
    LoadEverything(s, scriptsDirectory);
    return s;
}

void SmearCore_destroy(SmearCore *s) {
    if (!s) return;
    Core *core = (Core *)s;
    ScriptList *lists[] = { &s->moves, &s->colors, &s->waveforms, &s->particles };
    for (int l = 0; l < 4; l++) {
        for (int i = 0; i < lists[l]->count; i++) FreeEnvironment(lists[l]->list[i]);
    }
    for (int i = 0; i < 2; i++) {
        free(s->mapsData[i]);
        free(s->sbAllocs[i]);
    }
    free(core->video);
    free(core);
}

int SmearCore_scriptCount(const SmearCore *s, int kind) {
    switch (kind) {
    case 0: return s->moves.count;
    case 1: return s->colors.count;
    case 2: return s->waveforms.count;
    case 3: return s->particles.count;
    default: return 0;
    }
}

int SmearCore_holdMove(SmearCore *s, const char *fileName) {
    for (int i = 0; i < s->moves.count; i++) {
        if (strcmp(s->moves.list[i]->eFile, fileName) == 0) {
            s->heldMove = s->moves.list[i];
            s->moveForced = 1;
            return 1;
        }
    }
    return 0;
}

const uint8_t *SmearCore_render(SmearCore *s, int width, int height,
                                const int8_t *waveform, const uint8_t *spectrum) {
    Core *core = (Core *)s;
    if (width < 2 || height < 2) return NULL;
    size_t pixels = (size_t)width * height;
    if (core->videoSize != pixels) {
        free(core->video);
        core->video = malloc(pixels * sizeof(uint32_t));
        core->videoSize = core->video ? pixels : 0;
        if (!core->video) return NULL;
    }
    for (int channel = 0; channel < 2; channel++) {
        memcpy(s->waveform[channel], waveform, SMEAR_CORE_WAVEFORM_SIZE);
        memcpy(s->spectrum[channel], spectrum, SMEAR_CORE_SPECTRUM_SIZE);
    }
    smearRender(s, core->video, width, height, width);

    // 0x00RRGGBB to RGBA bytes, in place.
    uint8_t *rgba = (uint8_t *)core->video;
    for (size_t i = 0; i < pixels; i++) {
        uint32_t c = core->video[i];
        rgba[4 * i] = (uint8_t)(c >> 16);
        rgba[4 * i + 1] = (uint8_t)(c >> 8);
        rgba[4 * i + 2] = (uint8_t)c;
        rgba[4 * i + 3] = 255;
    }
    return rgba;
}
