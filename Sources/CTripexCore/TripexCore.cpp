// Chunk 1 skeleton — see Sources/CTripexCore/PORT_NOTES.md for the chunk plan
// and Sources/CTripexCore/include/TripexCore.h for the C ABI.
//
// _create currently returns NULL; the renderer + Tripex instance are wired
// up in Chunks 3–5 once RendererOpenGL and HostAudioSource exist.

#include "TripexCore.h"

extern "C" TripexCoreHandle* TripexCore_create(int /*width*/, int /*height*/) {
    return nullptr;
}

extern "C" void TripexCore_destroy(TripexCoreHandle* /*handle*/) {
    // no-op until Chunk 5
}
