#include "GoomCore.h"

#include <stdlib.h>
#include "goom.h"

struct GoomCore {
    PluginInfo *info;
    int pendingMode; /* upstream forceMode: 0 none, 1..NB_FX */
};

/* Order of the *_MODE constants in goom_filters.h. */
static const char *const effectNames[GOOM_CORE_EFFECT_COUNT] = {
    "Normal", "Wave", "Crystal Ball", "Scrunch", "Amulette",
    "Water", "Hypercos 1", "Hypercos 2", "Y Only", "Speedway",
    /* NullPlayer port additions */
    "Spiral", "Vortex", "Flower", "Heart", "Pentagram",
};
_Static_assert(GOOM_CORE_EFFECT_COUNT == NB_FX, "one name per Goom effect");

GoomCore *GoomCore_create(int width, int height) {
    GoomCore *core = calloc(1, sizeof *core);
    if (core == NULL) return NULL;
    core->info = goom_init((guint32)width, (guint32)height);
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
