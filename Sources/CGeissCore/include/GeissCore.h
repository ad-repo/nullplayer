#ifndef GEISS_CORE_H
#define GEISS_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GeissCore GeissCore;

GeissCore *GeissCore_create(int width, int height);
void       GeissCore_destroy(GeissCore *core);
void       GeissCore_resize(GeissCore *core, int width, int height);

void       GeissCore_addPCM(GeissCore *core, const float *samples, int count);
void       GeissCore_setSpectrum(GeissCore *core, const float *mags, int count);

// Writes width*height bytes of 8-bit palette indices into indexBuf.
// Caller owns indexBuf and guarantees it is at least width*height bytes.
void       GeissCore_render(GeissCore *core, unsigned char *indexBuf);

// Writes 256*4 RGBA bytes into rgbaOut. Caller owns rgbaOut.
void       GeissCore_palette(GeissCore *core, unsigned char *rgbaOut);

void        GeissCore_nextEffect(GeissCore *core);
void        GeissCore_prevEffect(GeissCore *core);
void        GeissCore_randomEffect(GeissCore *core);
const char *GeissCore_currentEffectName(GeissCore *core);

// Diagnostic accessor — exposes engine state for tests / debugging.
// Returns the int via the out-pointer; the int8 array `effects8` (length 9)
// receives the per-effect on/off state (1 = active, -1 = off, 0 = unset).
// Intended for the phase-4 closeout smoke test.
typedef struct GeissCoreDiag {
    int active_mode;       // current `mode` global
    int new_mode;          // staged `new_mode` global
    int y_map_pos;         // current map-build position (-1 = idle)
    int frames_this_mode;  // frames since last mode switch
    int8_t effects[9];     // effect[CHASERS..SPECTRAL]
    int gXC, gYC;
    int iDispBits;
    int FXW, FXH;
} GeissCoreDiag;

void GeissCore_diag(GeissCore *core, GeissCoreDiag *out);

#ifdef __cplusplus
}
#endif

#endif
