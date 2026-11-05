/*
 * WIN32 Events for POSIX
 * Author: Mahmoud Al-Qudsi <mqudsi@neosmart.net>
 * Copyright (C) 2011 - 2022 by NeoSmart Technologies
 * SPDX-License-Identifier: MIT
 */

#pragma once

#if defined(_WIN32) && !defined(CreateEvent)
#error Must include Windows.h prior to including pevents.h!
#endif
#ifndef WAIT_TIMEOUT
#include <errno.h>
#define WAIT_TIMEOUT ETIMEDOUT
#endif
#ifndef WAIT_FAILED
#include <errno.h>
#define WAIT_FAILED -EPERM
#endif

#include <stdbool.h>
#include <stdint.h>

// Type declarations
struct neosmart_event_t_;
typedef struct neosmart_event_t_ *neosmart_event_t;

// Constant declarations
const uint64_t NSPE_WAIT_INFINITE = ~((uint64_t)0);

// Function declarations
neosmart_event_t NspeCreateEvent(bool manualReset, bool initialState);
int NspeDestroyEvent(neosmart_event_t event);
int NspeWaitForEvent(neosmart_event_t event, uint64_t milliseconds);
int NspeSetEvent(neosmart_event_t event);
int NspeResetEvent(neosmart_event_t event);
#ifdef WFMO
    int NspeWaitForMultipleEvents(neosmart_event_t *events, int count, bool waitAll, uint64_t milliseconds);
    int NspeWaitForMultipleEventsWithIndex(neosmart_event_t *events, int count, bool waitAll, uint64_t milliseconds, int *index);
#endif
#ifdef PULSE
    int NspePulseEvent(neosmart_event_t event);
#endif
