#ifndef TRIPEX_WIN_COMPAT_H
#define TRIPEX_WIN_COMPAT_H

// Minimal Win32/MSVC compatibility shim for vendoring ben-marsh/tripex on
// macOS/clang. Tripex is a D3D9 + Win32 app; we replace D3D with an OpenGL
// renderer (RendererOpenGL) and stub the Win32 surface the math/effect code
// references. main.cpp + RendererDirect3d.{cpp,h} + AudioDevice.cpp are
// excluded from compilation entirely — those carry the bulk of Win32/D3D.

#include <stddef.h>
#include <stdint.h>
#include <chrono>

// MSVC integer aliases used by Platform.h pattern (Tripex's Platform.h does
// not define these — Tripex code uses int8/uint8 etc., not MSVC __intN — but
// keep parity with the Geiss shim for safety).
typedef int8_t   __int8_compat;
typedef int16_t  __int16_compat;
typedef int32_t  __int32_compat;
typedef int64_t  __int64_compat;

// Win32 handle/type aliases referenced by retained Tripex code paths. Most
// upstream files do not actually reference these (D3D + Win32 live in the
// excluded TUs), but a handful of headers/casts mention HRESULT/DWORD.
typedef int            BOOL;
typedef unsigned char  BYTE;
typedef unsigned short WORD;
typedef uint32_t       DWORD;
typedef int32_t        LONG;
typedef uint32_t       ULONG;
typedef uint32_t       UINT;
typedef uint64_t       ULONGLONG;
typedef int32_t        HRESULT;
typedef uintptr_t      WPARAM;
typedef intptr_t       LPARAM;
typedef intptr_t       LRESULT;
typedef char           *LPSTR;
typedef const char     *LPCSTR;
typedef void           *HANDLE;
typedef void           *HWND;
typedef void           *HINSTANCE;
typedef void           *HMODULE;

#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

#ifndef WINAPI
#define WINAPI
#endif
#ifndef CALLBACK
#define CALLBACK
#endif

// GetTickCount64 → monotonic milliseconds since first call.
static inline ULONGLONG GetTickCount64(void) {
    using clock = std::chrono::steady_clock;
    static const auto t0 = clock::now();
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(clock::now() - t0).count();
    return (ULONGLONG)ms;
}

static inline DWORD GetTickCount(void) {
    return (DWORD)GetTickCount64();
}

// timeGetTime() is used by some Tripex timing paths; alias to GetTickCount.
static inline DWORD timeGetTime(void) { return GetTickCount(); }

#endif // TRIPEX_WIN_COMPAT_H
