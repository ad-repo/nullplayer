#ifndef TRIPEX_CORE_H
#define TRIPEX_CORE_H

// C ABI bridge between Swift (TripexEngine.swift) and the vendored Tripex
// C++ core. All entry points are mutex-serialized inside TripexCore.cpp;
// callers may invoke them from any thread (typical NullPlayer usage:
// _pushPCM from the audio tap thread, _renderFrame from the GL display
// link thread, all other calls from the main thread).

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TripexCoreHandle TripexCoreHandle;

// Lifecycle. _create returns NULL on Tripex::Startup() failure; the caller
// can then read TripexCore_lastError() for diagnostics.
TripexCoreHandle* TripexCore_create(int width, int height);
void              TripexCore_destroy(TripexCoreHandle* handle);
void              TripexCore_resize(TripexCoreHandle* handle, int width, int height);

// Audio. Push interleaved int16 stereo PCM at 44100 Hz. `count` is the
// total number of int16 samples (i.e. 2 × frame count for stereo).
void              TripexCore_pushPCM(TripexCoreHandle* handle, const int16_t* samples, size_t count);

// Renders one frame using the host's current GL context. Returns 0 on
// success, non-zero if Tripex::Render returned an error (description
// available via TripexCore_lastError).
int               TripexCore_renderFrame(TripexCoreHandle* handle);

// Effect navigation. The Tripex core enqueues these via internal `txs`
// flags; effective on the next renderFrame.
void              TripexCore_prevEffect(TripexCoreHandle* handle);
void              TripexCore_nextEffect(TripexCoreHandle* handle);
void              TripexCore_changeEffect(TripexCoreHandle* handle);      // random
void              TripexCore_reconfigureEffect(TripexCoreHandle* handle); // re-randomise current effect params
void              TripexCore_toggleHoldingEffect(TripexCoreHandle* handle);
void              TripexCore_setHold(TripexCoreHandle* handle, int on);
int               TripexCore_isHolding(TripexCoreHandle* handle);
void              TripexCore_toggleAudioInfo(TripexCoreHandle* handle);
void              TripexCore_toggleHelp(TripexCoreHandle* handle);

int               TripexCore_effectCount(TripexCoreHandle* handle);
const char*       TripexCore_effectName(TripexCoreHandle* handle, int index);
int               TripexCore_currentEffectIndex(TripexCoreHandle* handle);
// Reach `index` by issuing Prev/Next deltas; bounded to [0, effectCount).
void              TripexCore_selectEffect(TripexCoreHandle* handle, int index);

// Generic int-option store. Backed by a std::unordered_map<std::string,int>
// inside the handle; bindings to Tripex internals come later. Returns
// `fallback` if the key was never set.
void              TripexCore_setOption(TripexCoreHandle* handle, const char* key, int value);
int               TripexCore_getOption(TripexCoreHandle* handle, const char* key, int fallback);

// Last error description (NUL-terminated, owned by the handle, valid until
// the next ABI call). Returns empty string when no error is pending.
const char*       TripexCore_lastError(TripexCoreHandle* handle);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // TRIPEX_CORE_H
