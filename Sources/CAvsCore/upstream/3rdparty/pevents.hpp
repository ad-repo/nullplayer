/*
 * WIN32 Events for POSIX
 * Author: Mahmoud Al-Qudsi <mqudsi@neosmart.net>
 * Copyright (C) 2011 - 2022 by NeoSmart Technologies
 * SPDX-License-Identifier: MIT
 */

#pragma once

extern "C" {
    #include "pevents.h"
}

namespace neosmart {
    // Constant declarations
    const uint64_t WAIT_INFINITE = NSPE_WAIT_INFINITE;

    // Function declarations
    neosmart_event_t CreateEvent(bool manualReset = false, bool initialState = false);
    int DestroyEvent(neosmart_event_t event);
    int WaitForEvent(neosmart_event_t event, uint64_t milliseconds = WAIT_INFINITE);
    int SetEvent(neosmart_event_t event);
    int ResetEvent(neosmart_event_t event);
#ifdef WFMO
    int WaitForMultipleEvents(neosmart_event_t *events, int count, bool waitAll, uint64_t milliseconds);
    int WaitForMultipleEvents(neosmart_event_t* events, int count, bool waitAll, uint64_t milliseconds, int &index);
#endif
#ifdef PULSE
    int PulseEvent(neosmart_event_t event);
#endif
} // namespace neosmart
