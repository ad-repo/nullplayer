#ifndef CORONA_CORE_H
#define CORONA_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// One Corona instance (upstream `Corona` plus its `PaletteCycler`). Instances are independent;
/// not thread-safe.
typedef struct CoronaCore CoronaCore;

/// Corona's palettes: libvisual's 23 plus the 8 more in its `autopal.h`.
#define CORONA_CORE_PALETTE_COUNT 31

CoronaCore *CoronaCore_create(int width, int height);
void CoronaCore_destroy(CoronaCore *core);

/// Advances one Corona frame. `spectrum` is 512 bins, 0..255, lowest frequency first (Sonique's
/// host spectrum); `elapsedMs` is the time since the last update. Returns `width * height`
/// pixels, R,G,B,A bytes in memory, row 0 at the bottom. The buffer belongs to the core and is
/// valid until the next call.
const uint32_t *CoronaCore_update(CoronaCore *core, const uint8_t spectrum[512], unsigned elapsedMs);

/// Fades (or, with `fade` 0, switches) to palette `index` and holds it: Corona stops picking
/// its own.
void CoronaCore_setPalette(CoronaCore *core, int index, int fade);
const char *CoronaCore_paletteName(int index);

/// Blaze (upstream `PRESET_BLAZE`) draws the particles three times a frame; off is Corona.
void CoronaCore_setBlaze(CoronaCore *core, int blaze);

#ifdef __cplusplus
}
#endif

#endif
