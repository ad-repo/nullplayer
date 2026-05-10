#ifndef GEISS_WIN_COMPAT_H
#define GEISS_WIN_COMPAT_H

// ---------------------------------------------------------------------------
// Phase 4c-1: minimal Win32 compatibility shim used by the Geiss port code.
//
// The upstream Geiss source (`upstream/main.cpp`, `upstream/Effects.h`,
// `upstream/video.h`) is written against the Win32 + DirectDraw + Winamp 2
// vis SDK platform. NullPlayer hosts Geiss on macOS via a dedicated port
// translation unit (`upstream_port/geiss_port.cpp`); that file pulls the real
// Geiss visual algorithms (Effects.h) into the build, replacing only the
// Win32 calls and the DirectDraw blit path. This header provides:
//
//   1. Typedefs for Win32 integral and handle types so upstream declarations
//      and casts parse under clang on macOS (BOOL, BYTE, DWORD, LONG, HWND…).
//   2. Macro stubs for MSVC/Win32 calling-convention attributes that have no
//      meaning on the System V ABI (WINAPI, CALLBACK, FAR, PASCAL, __cdecl…).
//   3. Stub macros and inline functions for Win32 APIs that survive in the
//      ported subset but whose effect is irrelevant on macOS (SetCursor,
//      OutputDebugString, Get/WritePrivateProfileString, MessageBox, …).
//
// Anything that genuinely affects the visualization (audio buffers, palette,
// framebuffer output) is *not* stubbed here — the port file translates those
// to NullPlayer-side equivalents (GeissAudioState, GeissCore_palette,
// GeissCore_render's indexBuf).
// ---------------------------------------------------------------------------

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Integral / handle typedefs
// ---------------------------------------------------------------------------

typedef int            BOOL;
typedef unsigned char  BYTE;
typedef unsigned short WORD;
typedef uint32_t       DWORD;
typedef int32_t        LONG;
typedef uint32_t       ULONG;
typedef uint32_t       UINT;
typedef int            INT;
typedef uintptr_t      WPARAM;
typedef intptr_t       LPARAM;
typedef intptr_t       LRESULT;
typedef int32_t        HRESULT;
typedef size_t         SIZE_T;
typedef intptr_t       LONG_PTR;
typedef uintptr_t      ULONG_PTR;
typedef uintptr_t      DWORD_PTR;

// MSVC integer aliases used in upstream code.
typedef int8_t   __int8;
typedef int16_t  __int16;
typedef int32_t  __int32;
typedef int64_t  __int64;

// Pointers and strings.
typedef char        *LPSTR;
typedef const char  *LPCSTR;
typedef char        *LPTSTR;
typedef const char  *LPCTSTR;
typedef BYTE        *LPBYTE;
typedef WORD        *LPWORD;
typedef DWORD       *LPDWORD;
typedef void        *LPVOID;
typedef const void  *LPCVOID;
typedef BOOL        *LPBOOL;

// Handles — all opaque void* on macOS.
typedef void *HANDLE;
typedef void *HINSTANCE;
typedef void *HMODULE;
typedef void *HWND;
typedef void *HDC;
typedef void *HFONT;
typedef void *HBITMAP;
typedef void *HBRUSH;
typedef void *HCURSOR;
typedef void *HICON;
typedef void *HMENU;
typedef void *HPALETTE;
typedef void *HRGN;
typedef void *HKEY;

// DirectDraw / DirectSound / Winamp opaque pointers.
typedef void *LPDIRECTDRAW;
typedef void *LPDIRECTDRAW2;
typedef void *LPDIRECTDRAWSURFACE;
typedef void *LPDIRECTDRAWSURFACE7;
typedef void *LPDIRECTDRAWPALETTE;
typedef void *LPDIRECTSOUND;
typedef void *LPDIRECTSOUNDCAPTURE;
typedef void *LPDIRECTSOUNDCAPTUREBUFFER;
typedef void *LPDIRECTSOUNDBUFFER;
typedef void *LPGUID;

// Common Win32 structs the upstream code references in passing.
typedef struct _GUID {
    DWORD Data1;
    WORD  Data2;
    WORD  Data3;
    BYTE  Data4[8];
} GUID;

typedef struct _RECT {
    LONG left, top, right, bottom;
} RECT, *LPRECT;

typedef struct _POINT {
    LONG x, y;
} POINT, *LPPOINT;

typedef struct _SIZE {
    LONG cx, cy;
} SIZE, *LPSIZE;

typedef struct _PALETTEENTRY {
    BYTE peRed;
    BYTE peGreen;
    BYTE peBlue;
    BYTE peFlags;
} PALETTEENTRY, *LPPALETTEENTRY;

typedef struct _LARGE_INTEGER {
    int64_t QuadPart;
} LARGE_INTEGER;

typedef struct _WAVEFORMATEX {
    WORD  wFormatTag;
    WORD  nChannels;
    DWORD nSamplesPerSec;
    DWORD nAvgBytesPerSec;
    WORD  nBlockAlign;
    WORD  wBitsPerSample;
    WORD  cbSize;
} WAVEFORMATEX;

// Direct-sound capture buffer descriptor — only declared so the upstream
// global `dscbd` (gated SAVER) parses; never used at runtime.
typedef struct _DSCBUFFERDESC {
    DWORD dwSize;
    DWORD dwFlags;
    DWORD dwBufferBytes;
    DWORD dwReserved;
    WAVEFORMATEX *lpwfxFormat;
} DSCBUFFERDESC;

typedef struct _DEVMODE {
    DWORD dmSize;
    DWORD dmDriverExtra;
    DWORD dmBitsPerPel;
    DWORD dmPelsWidth;
    DWORD dmPelsHeight;
    DWORD dmDisplayFrequency;
} DEVMODE;

typedef struct _WINDOWPLACEMENT {
    UINT  length;
    UINT  flags;
    UINT  showCmd;
    POINT ptMinPosition;
    POINT ptMaxPosition;
    RECT  rcNormalPosition;
} WINDOWPLACEMENT;

#ifdef __cplusplus
} // extern "C"
#endif

// ---------------------------------------------------------------------------
// Calling-convention / declaration-attribute macros
// ---------------------------------------------------------------------------

#ifndef WINAPI
#define WINAPI
#endif
#ifndef CALLBACK
#define CALLBACK
#endif
#ifndef APIENTRY
#define APIENTRY
#endif
#ifndef FAR
#define FAR
#endif
#ifndef NEAR
#define NEAR
#endif
#ifndef PASCAL
#define PASCAL
#endif

#ifndef __cdecl
#define __cdecl
#endif
#ifndef __fastcall
#define __fastcall
#endif
#ifndef __stdcall
#define __stdcall
#endif

#ifndef __forceinline
#define __forceinline inline
#endif

// `__declspec(x)` is purely compiler metadata on MSVC; on clang we discard it.
// `__declspec(naked)` was used by proc_map.cpp's asm dispatcher — that file is
// gated behind `#if 0` (phase 4b), so it does not matter here.
#ifndef __declspec
#define __declspec(x)
#endif

// ---------------------------------------------------------------------------
// Boolean constants and small macros
// ---------------------------------------------------------------------------

#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

#ifndef BST_CHECKED
#define BST_CHECKED 1
#endif
#ifndef BST_UNCHECKED
#define BST_UNCHECKED 0
#endif

// `RGB(r,g,b)` packs 3 bytes into a Win32 COLORREF (0x00BBGGRR). Geiss uses it
// for the title-text colour, which we do not render — but the macro must
// expand to a valid integer expression so the file parses.
#ifndef RGB
#define RGB(r, g, b) ((DWORD)( ((BYTE)(r)) | (((BYTE)(g)) << 8) | (((BYTE)(b)) << 16) ))
#endif

// `TEXT()` / `_T()` are MSVC's TCHAR-quoting macros; in our 8-bit world they
// pass strings through unchanged.
#ifndef TEXT
#define TEXT(x) x
#endif
#ifndef _T
#define _T(x) x
#endif

// `MAKEINTRESOURCE` is used to pass numeric IDs where strings are expected
// (dialog resources, etc.). Geiss only uses it inside dialog code, which the
// port gates out — but the macro must still expand to *something*.
#ifndef MAKEINTRESOURCE
#define MAKEINTRESOURCE(i) ((LPCSTR)(uintptr_t)(WORD)(i))
#endif

// `min` / `max` are MSVC built-ins; clang doesn't ship them as macros. The
// upstream Geiss source uses them extensively. C++ STL provides templated
// versions in <algorithm>, but the upstream code expects the macros, so
// define them. Use parenthesisation per the standard MSVC pattern.
#ifndef max
#define max(a, b) (((a) > (b)) ? (a) : (b))
#endif
#ifndef min
#define min(a, b) (((a) < (b)) ? (a) : (b))
#endif

// Microsoft extensions occasionally seen in the source.
#ifndef _MAX_PATH
#define _MAX_PATH 260
#endif
#ifndef MAX_PATH
#define MAX_PATH 260
#endif

// Some Win32 message constants surface in upstream declarations even when
// gated out; provide sentinel values so the file parses.
#define WM_CLOSE       0x0010
#define WM_SETCURSOR   0x0020

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Stubs for Win32 functions kept in the port subset
// ---------------------------------------------------------------------------
//
// All of these are declared `static inline` so they get inlined-out and never
// actually emit anything. They are *only* used from the Geiss port's
// non-rendering paths (registry config, debug output, mouse/cursor management,
// dialog plumbing) — we keep the call sites compiling but make them no-ops.
// ---------------------------------------------------------------------------

static inline HCURSOR SetCursor(HCURSOR /*c*/)               { return NULL; }
static inline BOOL    GetCursorPos(LPPOINT pt)               { if (pt) { pt->x = 0; pt->y = 0; } return TRUE; }
static inline void    OutputDebugStringA(LPCSTR /*s*/)       { }
static inline void    OutputDebugString(LPCSTR /*s*/)        { }
static inline int     MessageBoxA(HWND, LPCSTR, LPCSTR, UINT){ return 0; }
static inline int     MessageBox(HWND, LPCSTR, LPCSTR, UINT) { return 0; }

static inline BOOL    GetWindowText(HWND, LPSTR buf, int n)
{
    if (buf && n > 0) buf[0] = '\0';
    return TRUE;
}

static inline DWORD GetPrivateProfileStringA(LPCSTR /*sec*/, LPCSTR /*key*/,
                                             LPCSTR def, LPSTR ret, DWORD nSize,
                                             LPCSTR /*ini*/)
{
    if (!ret || nSize == 0) return 0;
    const char *src = def ? def : "";
    DWORD i = 0;
    while (src[i] && i + 1 < nSize) { ret[i] = src[i]; ++i; }
    ret[i] = '\0';
    return i;
}

static inline DWORD GetPrivateProfileString(LPCSTR sec, LPCSTR key, LPCSTR def,
                                            LPSTR ret, DWORD nSize, LPCSTR ini)
{
    return GetPrivateProfileStringA(sec, key, def, ret, nSize, ini);
}

static inline BOOL WritePrivateProfileStringA(LPCSTR /*sec*/, LPCSTR /*key*/,
                                              LPCSTR /*val*/, LPCSTR /*ini*/) { return TRUE; }
static inline BOOL WritePrivateProfileString(LPCSTR /*sec*/, LPCSTR /*key*/,
                                             LPCSTR /*val*/, LPCSTR /*ini*/)  { return TRUE; }

static inline UINT GetPrivateProfileIntA(LPCSTR /*sec*/, LPCSTR /*key*/,
                                         INT def, LPCSTR /*ini*/) { return (UINT)def; }
static inline UINT GetPrivateProfileInt(LPCSTR sec, LPCSTR key, INT def, LPCSTR ini)
{
    return GetPrivateProfileIntA(sec, key, def, ini);
}

static inline DWORD GetTickCount_compat(void) { return 0; }

#ifdef __cplusplus
} // extern "C"
#endif

#endif // GEISS_WIN_COMPAT_H
