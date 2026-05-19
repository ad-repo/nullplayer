// Glue layer between the C ABI in include/TripexCore.h and the C++ Tripex
// core. Chunks 1–4 only construct the objects; the full ABI (resize,
// pushPCM, renderFrame, effect navigation, options) lands in Chunk 5.

#include "TripexCore.h"
#include "Tripex.h"
#include "RendererOpenGL.h"
#include "HostAudioSource.h"
#include <memory>

struct TripexCoreHandle {
    std::shared_ptr<RendererOpenGL> renderer;
    std::shared_ptr<Tripex>         tripex;
    std::shared_ptr<HostAudioSource> audio;
};

extern "C" TripexCoreHandle* TripexCore_create(int width, int height) {
    auto* h = new TripexCoreHandle();
    h->renderer = std::make_shared<RendererOpenGL>(width, height);
    h->audio    = std::make_shared<HostAudioSource>();
    h->tripex   = std::make_shared<Tripex>(h->renderer);
    // Tripex::Startup loads textures and constructs effects. Per
    // PORT_NOTES, CreateTextureFromImage is unimplemented in Chunk 3 — if
    // an effect requires it, Startup will return non-null and we surface
    // failure to the caller via a NULL handle. Chunk 5 will replace this
    // with a proper lastError surface.
    if (h->tripex->Startup() != nullptr) {
        delete h;
        return nullptr;
    }
    return h;
}

extern "C" void TripexCore_destroy(TripexCoreHandle* handle) {
    if (!handle) return;
    if (handle->tripex) handle->tripex->Shutdown();
    delete handle;
}
