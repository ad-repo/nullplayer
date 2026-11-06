#include "GoomCore.h"

#include <stdlib.h>
#include "goom.h"
#include "goom_filters.h"

struct GoomCore {
    PluginInfo *info;
    int pendingMode; /* upstream forceMode: 0 none, 1..NB_FX */
};

/* Indexed by the *_MODE constants, so each name stays on its mode whatever their order. */
static const char *const effectNames[GOOM_CORE_EFFECT_COUNT] = {
    [NORMAL_MODE] = "Normal", [WAVE_MODE] = "Wave", [CRYSTAL_BALL_MODE] = "Crystal Ball",
    [SCRUNCH_MODE] = "Scrunch", [AMULETTE_MODE] = "Amulette", [WATER_MODE] = "Water",
    [HYPERCOS1_MODE] = "Hypercos 1", [HYPERCOS2_MODE] = "Hypercos 2", [YONLY_MODE] = "Y Only",
    [SPEEDWAY_MODE] = "Speedway",
    /* NullPlayer port additions */
    [SPIRAL_MODE] = "Spiral", [VORTEX_MODE] = "Vortex", [FLOWER_MODE] = "Flower",
    [HEART_MODE] = "Heart", [PENTAGRAM_MODE] = "Pentagram",
};
_Static_assert(GOOM_CORE_EFFECT_COUNT == NB_FX && NB_FX == NB_ZOOM_MODES, "one name per Goom effect");

GoomCore *GoomCore_create(int width, int height) {
    GoomCore *core = calloc(1, sizeof *core);
    if (core == NULL) return NULL;
    core->info = goom_init((guint32)width, (guint32)height);
    if (core->info == NULL) {
        free(core);
        return NULL;
    }
    return core;
}

void GoomCore_destroy(GoomCore *core) {
    if (core == NULL) return;
    goom_close(core->info);
    free(core);
}

const uint32_t *GoomCore_update(GoomCore *core, const int16_t *pcm) {
    int mode = core->pendingMode;
    core->pendingMode = 0;
    /* fps 0: no fps overlay; no title or message, so Goom draws no text. */
    return goom_update(core->info, (gint16 (*)[512])pcm, mode, 0, NULL, NULL);
}

void GoomCore_forceEffect(GoomCore *core, int index) {
    if (index >= 0 && index < GOOM_CORE_EFFECT_COUNT) core->pendingMode = index + 1;
}

void GoomCore_setHold(GoomCore *core, int hold) {
    core->info->update.holdMode = hold != 0;
}

int GoomCore_currentEffect(const GoomCore *core) {
    return core->info->update.zoomFilterData.mode;
}

const char *GoomCore_effectName(int index) {
    return (index >= 0 && index < GOOM_CORE_EFFECT_COUNT) ? effectNames[index] : "";
}
