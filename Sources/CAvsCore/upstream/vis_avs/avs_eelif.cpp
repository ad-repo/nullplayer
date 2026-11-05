/*
  LICENSE
  -------
Copyright 2005 Nullsoft, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.

  * Neither the name of Nullsoft nor the names of its contributors may be used to
    endorse or promote products derived from this software without specific prior
    written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/

/**
 * EEL has a single global init/quit state, and multiple "VM contexts" which in turn may
 * have multiple "compile contexts". In AVS an EEL VM is reused within one effect. An
 * effect may have one or more code sections. Each code section is a compile context.
 * A VM shares local variable state among all code sections/compile contexts. On top of
 * that EEL has global state (`regXX` vars and the `gmegabuf`/`gmem` array), which is
 * shared between all VMs.
 *
 * To really separate AVS instances, we need to make use of an optional EEL feature,
 * global RAM separation, by manually providing a global RAM section on every compile
 * call, depending on which AVS instance its effect belongs to. Each AVS_Instance keeps
 * an EelState member, which contain the global RAM sections, along with other
 * configuration.
 */

#include "avs_eelif.h"

#include "instance.h"

#include "../3rdparty/WDL-EEL2/eel2/ns-eel-addfuncs.h"
#include "../platform.h"

#include <stdlib.h>
#include <string.h>

#ifdef CAN_TALK_TO_WINAMP
#include <windows.h>
#endif

/////////////////////// begin AVS specific script functions

static double getvis(unsigned char* visdata, int bc, int bw, int ch, int xorv) {
    int x;
    int accum = 0;
    if (ch && ch != 1 && ch != 2) {
        return 0.0;
    }

    if (bw < 1) {
        bw = 1;
    }
    bc -= bw / 2;
    if (bc < 0) {
        bw += bc;
        bc = 0;
    }
    if (bc > (AUDIO_BUFFER_LEN - 1)) {
        bc = AUDIO_BUFFER_LEN - 1;
    }
    if (bc + bw > AUDIO_BUFFER_LEN) {
        bw = AUDIO_BUFFER_LEN - bc;
    }

    if (ch == 0) {  // Center
        for (x = 0; x < bw; x++) {
            accum += (visdata[bc] ^ xorv) - xorv;
            accum += (visdata[bc + AUDIO_BUFFER_LEN] ^ xorv) - xorv;
            bc++;
        }
        return (double)accum / ((double)bw * 255.0);
    } else {
        if (ch == 2) {
            visdata += AUDIO_BUFFER_LEN;
        }
        for (x = 0; x < bw; x++) {
            accum += (visdata[bc++] ^ xorv) - xorv;
        }
        return (double)accum / ((double)bw * 127.5);
    }
}

static double getspec(AVS_Instance* avs, double* band, double* bandw, double* chan) {
    return getvis((unsigned char*)avs->eel_state.visdata,
                  (int)(*band * AUDIO_BUFFER_LEN),
                  (int)(*bandw * AUDIO_BUFFER_LEN),
                  (int)(*chan + 0.5),
                  0)
           * 0.5;
}

static double getosc(AVS_Instance* avs, double* band, double* bandw, double* chan) {
    return getvis((unsigned char*)&avs->eel_state.visdata[AUDIO_BUFFER_LEN * 2],
                  (int)(*band * AUDIO_BUFFER_LEN),
                  (int)(*bandw * AUDIO_BUFFER_LEN),
                  (int)(*chan + 0.5),
                  128);
}

static double gettime(AVS_Instance* avs, double* sc) {
#ifdef CAN_TALK_TO_WINAMP
    int ispos;
    if ((ispos = (*sc > -1.001 && *sc < -0.999)) || (*sc > -2.001 && *sc < -1.999)) {
        int pos = 0;

        extern HWND hwnd_WinampParent;
        if (IsWindow(hwnd_WinampParent)) {
            if (!SendMessageTimeout(hwnd_WinampParent,
                                    WM_USER,
                                    (WPARAM)!ispos,
                                    (LPARAM)105,
                                    SMTO_BLOCK,
                                    50,
                                    (LPDWORD)&pos)) {
                pos = 0;
            }
        }
        if (!ispos) {
            return (double)pos;
        }
        return pos / 1000.0;
    }
#endif  // CAN_TALK_TO_WINAMP
    return avs->get_current_time_in_ms() / 1000.0 - *sc;
}

static double getmouse(AVS_Instance* avs, double* which) {
    int w = (int)(*which + 0.5);

#ifdef CAN_TALK_TO_WINAMP
    if (w > 5) {
        return (GetAsyncKeyState(w) & 0x8000) ? 1.0 : 0.0;
    }

    if (w == 1 || w == 2) {
        POINT p;
        GetCursorPos(&p);
        extern double DDraw_translatePoint(POINT p, int isY);
        return DDraw_translatePoint(p, w == 2);
    }
    if (w == 3) {
        return (GetAsyncKeyState(MK_LBUTTON) & 0x8000) ? 1.0 : 0.0;
    }
    if (w == 4) {
        return (GetAsyncKeyState(MK_RBUTTON) & 0x8000) ? 1.0 : 0.0;
    }
    if (w == 5) {
        return (GetAsyncKeyState(MK_MBUTTON) & 0x8000) ? 1.0 : 0.0;
    }
#else
    switch (w) {
        case 1: return avs->get_mouse_pos(/*get_y*/ false) * 2.0 - 1.0;
        case 2: return avs->get_mouse_pos(/*get_y*/ true) * 2.0 - 1.0;
        case 3: [[fallthrough]];
        case 4: [[fallthrough]];
        case 5: return avs->get_mouse_button_state(w) ? 1.0 : 0.0;
        default: return avs->get_key_state(w) ? 1.0 : 0.0;
    }
    return 0.0;
#endif  // CAN_TALK_TO_WINAMP
}

/////////////////////// end AVS specific script functions

void AVS_EEL_IF_init(AVS_Instance* avs) {
    NSEEL_init();
    NSEEL_addfunc_retval("getosc", 3, NSEEL_PProc_THIS, (void*)getosc);
    NSEEL_addfunc_retval("getspec", 3, NSEEL_PProc_THIS, (void*)getspec);
    NSEEL_addfunc_retval("gettime", 1, NSEEL_PProc_THIS, (void*)gettime);
    NSEEL_addfunc_retval("getkbmouse", 1, NSEEL_PProc_THIS, (void*)getmouse);
}
void AVS_EEL_IF_quit(AVS_Instance* avs) { NSEEL_quit(); }

NSEEL_CODEHANDLE AVS_EEL_IF_Compile(AVS_Instance* avs,
                                    NSEEL_VMCTX context,
                                    char* code) {
    NSEEL_VM_SetGRAM(context, &avs->eel_state.global_ram);
    NSEEL_VM_SetCompileHooks(
        context, avs->eel_state.pre_compile_hook, avs->eel_state.post_compile_hook);
    NSEEL_VM_SetCustomFuncThis(context, avs);
    NSEEL_CODEHANDLE handle = NSEEL_code_compile((NSEEL_VMCTX)context, code, 0);
    if (!handle && avs->eel_state.log_errors) {
        char* err = NSEEL_code_getcodeerror((NSEEL_VMCTX)context);
        if (err) {
            log_warn("EEL compile error: %s", err);
            avs->eel_state.error(err);
        } else if (code && code[0]) {
            log_warn("EEL unknown compile error on '%s'", code);
            avs->eel_state.error("EEL unknown compile error");
        }
    }
    return handle;
}

void AVS_EEL_IF_Execute(AVS_Instance* avs,
                        NSEEL_CODEHANDLE handle,
                        char visdata[2][2][AUDIO_BUFFER_LEN]) {
    if (handle) {
        avs->audio.to_legacy_visdata(avs->eel_state.visdata);
        NSEEL_code_execute(handle);
    }
}

void AVS_EEL_IF_resetvars(NSEEL_VMCTX ctx) { NSEEL_VM_remove_all_nonreg_vars(ctx); }

void NSEEL_HOSTSTUB_EnterMutex() {}
void NSEEL_HOSTSTUB_LeaveMutex() {}
