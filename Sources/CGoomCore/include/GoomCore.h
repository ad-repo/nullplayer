#ifndef GOOM_CORE_H
#define GOOM_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// One Goom instance (upstream `PluginInfo`). Instances are independent; not thread-safe.
typedef struct GoomCore GoomCore;

/// Number of zoom-filter effects Goom can be forced to (upstream `NB_FX`).
#define GOOM_CORE_EFFECT_COUNT 15

GoomCore *GoomCore_create(int width, int height);
void GoomCore_destroy(GoomCore *core);

/// Advances one Goom cycle from 512 stereo int16 frames (`pcm[0..511]` left, `pcm[512..1023]`
/// right) and returns `width * height` pixels, R,G,B,A bytes in memory (alpha undefined). The
/// buffer belongs to the core and is valid until the next call.
const uint32_t *GoomCore_update(GoomCore *core, const int16_t *pcm);

/// Switches to effect `index` (0..GOOM_CORE_EFFECT_COUNT-1) on the next update. Goom keeps
/// choosing its own effects afterwards, as upstream's forced switch does.
void GoomCore_forceEffect(GoomCore *core, int index);
/// Holding stops Goom changing the effect itself; a forced effect still lands. Everything else
/// (speed, centre, scope, colours) keeps following the music.
void GoomCore_setHold(GoomCore *core, int hold);
/// The zoom-filter effect currently running.
int GoomCore_currentEffect(const GoomCore *core);
const char *GoomCore_effectName(int index);

#ifdef __cplusplus
}
#endif

#endif
