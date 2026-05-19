// Glue layer between the C ABI in include/TripexCore.h and the C++ Tripex
// core. Every public entry is serialized by a single mutex; renderFrame
// + pushPCM may be called from different threads.

#include "TripexCore.h"
#include "Tripex.h"
#include "Error.h"
#include "RendererOpenGL.h"
#include "HostAudioSource.h"

#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

struct TripexCoreHandle {
    std::mutex                       lock;
    std::shared_ptr<RendererOpenGL>  renderer;
    std::shared_ptr<Tripex>          tripex;
    std::shared_ptr<HostAudioSource> audio;
    std::unordered_map<std::string, int> options;
    std::string                      last_error;
};

static void setError(TripexCoreHandle* h, Error* err) {
    if (!err) { h->last_error.clear(); return; }
    h->last_error = err->GetDescription();
    delete err;
}

extern "C" TripexCoreHandle* TripexCore_create(int width, int height) {
    auto* h = new TripexCoreHandle();
    h->renderer = std::make_shared<RendererOpenGL>(width, height);
    h->audio    = std::make_shared<HostAudioSource>();
    h->tripex   = std::make_shared<Tripex>(h->renderer);
    Error* err = h->tripex->Startup();
    if (err != nullptr) {
        h->last_error = err->GetDescription();
        delete err;
        // Surface failure cleanly: caller gets NULL and (currently) no way
        // to read the error string. Acceptable for Chunk 5 — Chunk 6's
        // Swift wiring will log via os_log on failure path.
        delete h;
        return nullptr;
    }
    return h;
}

extern "C" void TripexCore_destroy(TripexCoreHandle* handle) {
    if (!handle) return;
    {
        std::lock_guard<std::mutex> lk(handle->lock);
        if (handle->tripex) handle->tripex->Shutdown();
    }
    delete handle;
}

extern "C" void TripexCore_resize(TripexCoreHandle* h, int width, int height) {
    if (!h) return;
    std::lock_guard<std::mutex> lk(h->lock);
    if (h->renderer) h->renderer->Resize(width, height);
}

extern "C" void TripexCore_pushPCM(TripexCoreHandle* h, const int16_t* samples, size_t count) {
    if (!h || !samples || count == 0) return;
    std::lock_guard<std::mutex> lk(h->lock);
    if (h->audio) h->audio->Push((const int16*)samples, count);
}

extern "C" int TripexCore_renderFrame(TripexCoreHandle* h) {
    if (!h || !h->tripex || !h->audio) return -1;
    std::lock_guard<std::mutex> lk(h->lock);
    Error* err = h->tripex->Render(*h->audio);
    if (err) { setError(h, err); return 1; }
    h->last_error.clear();
    return 0;
}

extern "C" void TripexCore_prevEffect(TripexCoreHandle* h) {
    if (!h || !h->tripex) return;
    std::lock_guard<std::mutex> lk(h->lock);
    h->tripex->MoveToPrevEffect();
}

extern "C" void TripexCore_nextEffect(TripexCoreHandle* h) {
    if (!h || !h->tripex) return;
    std::lock_guard<std::mutex> lk(h->lock);
    h->tripex->MoveToNextEffect();
}

extern "C" void TripexCore_changeEffect(TripexCoreHandle* h) {
    if (!h || !h->tripex) return;
    std::lock_guard<std::mutex> lk(h->lock);
    h->tripex->ChangeEffect();
}

extern "C" void TripexCore_reconfigureEffect(TripexCoreHandle* h) {
    if (!h || !h->tripex) return;
    std::lock_guard<std::mutex> lk(h->lock);
    h->tripex->ReconfigureEffect();
}

extern "C" void TripexCore_toggleHoldingEffect(TripexCoreHandle* h) {
    if (!h || !h->tripex) return;
    std::lock_guard<std::mutex> lk(h->lock);
    h->tripex->ToggleHoldingEffect();
}

extern "C" void TripexCore_toggleAudioInfo(TripexCoreHandle* h) {
    if (!h || !h->tripex) return;
    std::lock_guard<std::mutex> lk(h->lock);
    h->tripex->ToggleAudioInfo();
}

extern "C" void TripexCore_toggleHelp(TripexCoreHandle* h) {
    if (!h || !h->tripex) return;
    std::lock_guard<std::mutex> lk(h->lock);
    h->tripex->ToggleHelp();
}

extern "C" int TripexCore_effectCount(TripexCoreHandle* h) {
    if (!h || !h->tripex) return 0;
    std::lock_guard<std::mutex> lk(h->lock);
    return h->tripex->PortGetEffectCount();
}

extern "C" const char* TripexCore_effectName(TripexCoreHandle* h, int index) {
    if (!h || !h->tripex) return "";
    std::lock_guard<std::mutex> lk(h->lock);
    return h->tripex->PortGetEffectName(index);
}

extern "C" int TripexCore_currentEffectIndex(TripexCoreHandle* h) {
    if (!h || !h->tripex) return -1;
    std::lock_guard<std::mutex> lk(h->lock);
    return h->tripex->PortGetCurrentEffectIndex();
}

extern "C" void TripexCore_selectEffect(TripexCoreHandle* h, int index) {
    if (!h || !h->tripex) return;
    std::lock_guard<std::mutex> lk(h->lock);
    int total = h->tripex->PortGetEffectCount();
    if (total <= 0) return;
    if (index < 0) index = 0;
    if (index >= total) index = total - 1;
    int current = h->tripex->PortGetCurrentEffectIndex();
    int delta = index - current;
    // Tripex's prev/next are queued — fire all deltas; they'll be applied
    // across subsequent frames. For now, just issue one of each per step.
    while (delta > 0) { h->tripex->MoveToNextEffect(); --delta; }
    while (delta < 0) { h->tripex->MoveToPrevEffect(); ++delta; }
}

extern "C" void TripexCore_setOption(TripexCoreHandle* h, const char* key, int value) {
    if (!h || !key) return;
    std::lock_guard<std::mutex> lk(h->lock);
    h->options[std::string(key)] = value;
}

extern "C" int TripexCore_getOption(TripexCoreHandle* h, const char* key, int fallback) {
    if (!h || !key) return fallback;
    std::lock_guard<std::mutex> lk(h->lock);
    auto it = h->options.find(std::string(key));
    return (it == h->options.end()) ? fallback : it->second;
}

extern "C" const char* TripexCore_lastError(TripexCoreHandle* h) {
    if (!h) return "";
    std::lock_guard<std::mutex> lk(h->lock);
    return h->last_error.c_str();
}
