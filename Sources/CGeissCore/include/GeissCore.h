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

#ifdef __cplusplus
}
#endif

#endif
