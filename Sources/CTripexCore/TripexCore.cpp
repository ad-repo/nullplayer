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
#include <cstdio>

static std::mutex g_startup_error_lock;
static std::string g_last_startup_error;

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
    {
        std::lock_guard<std::mutex> lk(g_startup_error_lock);
        g_last_startup_error.clear();
    }
    auto* h = new TripexCoreHandle();
    h->renderer = std::make_shared<RendererOpenGL>(width, height);
    h->audio    = std::make_shared<HostAudioSource>();
    h->tripex   = std::make_shared<Tripex>(h->renderer);
    Error* err = h->tripex->Startup();
    if (err != nullptr) {
        std::string desc = err->GetDescription();
        delete err;
        {
            std::lock_guard<std::mutex> lk(g_startup_error_lock);
            g_last_startup_error = desc;
        }
        fprintf(stderr, "[Tripex] Startup failed: %s\n", desc.c_str());
        delete h;
        return nullptr;
    }
    // Suppress upstream's on-screen hotkey help overlay (Startup enables
    // it by default). All port-relevant shortcuts live in the right-click
    // Visualization menu; users opt in via "Show Help Overlay".
    h->tripex->ToggleHelp();
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
    int count = h->tripex->PortGetEffectCount();
    if (count <= 0) return;
    int cur = h->tripex->PortGetCurrentEffectIndex();
    int next = (cur < 0) ? 0 : (cur - 1 + count) % count;
    h->tripex->PortJumpToEffect(next);
}

extern "C" void TripexCore_nextEffect(TripexCoreHandle* h) {
    if (!h || !h->tripex) return;
    std::lock_guard<std::mutex> lk(h->lock);
    int count = h->tripex->PortGetEffectCount();
    if (count <= 0) return;
    int cur = h->tripex->PortGetCurrentEffectIndex();
    int next = (cur < 0) ? 0 : (cur + 1) % count;
    h->tripex->PortJumpToEffect(next);
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

extern "C" void TripexCore_setHold(TripexCoreHandle* h, int on) {
    if (!h || !h->tripex) return;
    std::lock_guard<std::mutex> lk(h->lock);
    h->tripex->PortSetHold(on != 0);
}

extern "C" int TripexCore_isHolding(TripexCoreHandle* h) {
    if (!h || !h->tripex) return 0;
    std::lock_guard<std::mutex> lk(h->lock);
    return h->tripex->PortIsHolding() ? 1 : 0;
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

extern "C" void TripexCore_setIntensityScale(TripexCoreHandle* h, float scale) {
    if (!h || !h->tripex) return;
    std::lock_guard<std::mutex> lk(h->lock);
    h->tripex->PortSetIntensityScale(scale);
}

extern "C" float TripexCore_getIntensityScale(TripexCoreHandle* h) {
    if (!h || !h->tripex) return 1.0f;
    std::lock_guard<std::mutex> lk(h->lock);
    return h->tripex->PortGetIntensityScale();
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
    h->tripex->PortJumpToEffect(index);
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

extern "C" const char* TripexCore_lastStartupError(void) {
    std::lock_guard<std::mutex> lk(g_startup_error_lock);
    return g_last_startup_error.c_str();
}
