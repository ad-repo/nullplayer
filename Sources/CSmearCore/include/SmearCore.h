#ifndef SMEAR_CORE_H
#define SMEAR_CORE_H

// Smear 1.2 (mykel and xplo, for Sonique) behind a small C ABI; skills/smear-port.
// Each core is independent. A core is not thread-safe: one thread renders and holds.

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SMEAR_CORE_WAVEFORM_SIZE 512
#define SMEAR_CORE_SPECTRUM_SIZE 256

typedef struct SmearState SmearCore;

/// Loads the scripts in `scriptsDirectory` (Moves/*.sms, Color/*.scs, Waveform/*.sws,
/// Particle/*.sps; a missing kind falls back to upstream's built-in script). NULL when out of memory.
SmearCore *SmearCore_create(const char *scriptsDirectory);
void SmearCore_destroy(SmearCore *core);

/// The scripts of one kind that parsed: 0 moves, 1 colors, 2 waveforms, 3 particles.
int SmearCore_scriptCount(const SmearCore *core, int kind);

/// Holds the move script with this file name ("Starwave.sms") and builds it now; Smear's own
/// timer then only re-rolls that script's random parameters. Returns 0 if no such script parsed.
int SmearCore_holdMove(SmearCore *core, const char *fileName);

/// Draws one frame from one channel of signed 8-bit PCM and a 0...255 spectrum (bass first),
/// both used for left and right. Returns `width * height` RGBA pixels, row 0 at the top, owned
/// by the core until the next call.
const uint8_t *SmearCore_render(SmearCore *core, int width, int height,
                                const int8_t *waveform, const uint8_t *spectrum);

#ifdef __cplusplus
}
#endif

#endif
