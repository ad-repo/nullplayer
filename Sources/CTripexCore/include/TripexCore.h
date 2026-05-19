#ifndef TRIPEX_CORE_H
#define TRIPEX_CORE_H

// C ABI bridge between Swift (TripexEngine.swift) and the vendored Tripex
// C++ core. Chunk 1 ships the skeleton — _create returns NULL, _destroy is a
// no-op. The full surface (resize / pushPCM / renderFrame / effect nav /
// setOption / getOption / lastError) lands in Chunk 5.

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TripexCoreHandle TripexCoreHandle;

TripexCoreHandle* TripexCore_create(int width, int height);
void              TripexCore_destroy(TripexCoreHandle* handle);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // TRIPEX_CORE_H
