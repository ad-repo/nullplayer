// NullPlayer: macOS port of upstream avs/platform_linux.c (vis_avs @ 1cee1f3, BSD-3, see
// upstream/LICENSE.TXT). Differences from the Linux file, each marked `NullPlayer:`:
// CLOCK_BOOTTIME -> CLOCK_UPTIME_RAW, pthread_setschedprio -> pthread_setschedparam,
// and mem_mark_rwx computes page bounds in uintptr_t instead of a 32-bit unsigned int.
// The disabled pthread-condvar signal implementation in the Linux file is not carried.
// It is C++ (platform.h keeps C linkage) because a C TU built with -fmodules sees Mach's
// own `thread_create` through the Darwin module and rejects upstream's.
#include "platform.h"

extern "C" {  // as upstream pevents.hpp does: pevents.cpp defines these with C linkage
#include "3rdparty/pevents.h"
}

#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>  // NullPlayer: platform.h only pulls this in under __linux__
#include <time.h>
#include <unistd.h>

#include <sys/mman.h>  // mprotect flags
#include <sys/stat.h>  // mkdir()

/* timers & time */

// NullPlayer: macOS has no CLOCK_BOOTTIME; CLOCK_UPTIME_RAW is the monotonic equivalent.
#define AVS_CLOCK CLOCK_UPTIME_RAW

uint64_t timer_ms() {
    struct timespec ts;
    if (clock_gettime(AVS_CLOCK, &ts) == -1) {
        return 0;
    }
    return ts.tv_sec * 1000 + ts.tv_nsec / (1000 * 1000);
}

uint64_t timer_us() {
    struct timespec ts;
    if (clock_gettime(AVS_CLOCK, &ts) == -1) {
        return 0;
    }
    return ts.tv_sec * 1000 * 1000 + ts.tv_nsec / 1000;
}

double timer_us_precision() {
    struct timespec ts;
    if (clock_getres(AVS_CLOCK, &ts) == -1) {
        return 0.0;
    }
    return ts.tv_sec * 1000.0 * 1000.0 + (double)ts.tv_nsec / 1000.0;
}

const char* current_date_str() {
    static char date_str[11];
    time_t t = time(NULL);
    struct tm date = *localtime(&t);
    snprintf(date_str,
             11,
             "%04d-%02d-%02d",
             date.tm_year + 1900,
             date.tm_mon + 1,
             date.tm_mday);
    return date_str;
}

/* locking */

#define PTHREAD_LOCK(lock) ((pthread_mutex_t*)(lock))
lock_t* lock_init() {
    pthread_mutex_t* lock_obj = (pthread_mutex_t*)malloc(sizeof(pthread_mutex_t));
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    // Make the mutex recursive because Win32's CRITICAL_SECTIONs are, and we want locks
    // to behave the same everywhere.
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init((pthread_mutex_t*)lock_obj, &attr);
    return (lock_t*)lock_obj;
}
void lock_lock(lock_t* lock_obj) { pthread_mutex_lock(PTHREAD_LOCK(lock_obj)); }
bool lock_try(lock_t* lock_obj) {
    return 0 != pthread_mutex_trylock(PTHREAD_LOCK(lock_obj));
}
void lock_unlock(lock_t* lock_obj) { pthread_mutex_unlock(PTHREAD_LOCK(lock_obj)); }
void lock_destroy(lock_t* lock_obj) {
    pthread_mutex_destroy(PTHREAD_LOCK(lock_obj));
    free(lock_obj);
}

/* signals */

signal_t* signal_create_single() {
    neosmart_event_t event = NspeCreateEvent(false, false);
    return event;
}
signal_t* signal_create_broadcast() {
    neosmart_event_t event = NspeCreateEvent(true, false);
    return event;
}
void signal_set(signal_t* signal) { NspeSetEvent((neosmart_event_t)signal); }
void signal_unset(signal_t* signal) { NspeResetEvent((neosmart_event_t)signal); }
signal_t* signal_wait(signal_t* signal, int32_t wait_ms) {
    if (wait_ms == WAIT_INFINITE) {
        NspeWaitForEvent((neosmart_event_t)signal, NSPE_WAIT_INFINITE);
        return signal;
    }
    int result = NspeWaitForEvent((neosmart_event_t)signal, wait_ms);
    if (result == WAIT_TIMEOUT) {
        return NULL;
    }
    return signal;
}
signal_t* signal_wait_any(signal_t** signals, uint32_t num_signals, int32_t wait_ms) {
    neosmart_event_t* darwin_signals = (neosmart_event_t*)signals;
    if (wait_ms == WAIT_INFINITE) {
        return signals[NspeWaitForMultipleEvents(
            darwin_signals, num_signals, false, NSPE_WAIT_INFINITE)];
    }
    int result = NspeWaitForMultipleEvents(darwin_signals, num_signals, false, wait_ms);
    if (result == WAIT_TIMEOUT) {
        return NULL;
    }
    return signals[result];
}
signal_t* signal_wait_all(signal_t** signals, uint32_t num_signals, int32_t wait_ms) {
    neosmart_event_t* darwin_signals = (neosmart_event_t*)signals;
    if (wait_ms == WAIT_INFINITE) {
        return signals[NspeWaitForMultipleEvents(
            darwin_signals, num_signals, true, NSPE_WAIT_INFINITE)];
    }
    int result = NspeWaitForMultipleEvents(darwin_signals, num_signals, true, wait_ms);
    if (result == WAIT_TIMEOUT) {
        return NULL;
    }
    return signals[result];
}
void signal_destroy(signal_t* signal) { NspeDestroyEvent((neosmart_event_t)signal); }

/* threading */

thread_t* thread_create(uint32_t (*func)(void* data), void* data) {
    pthread_t* thread = (pthread_t*)malloc(sizeof(pthread_t));
    pthread_create(thread, NULL, (void* (*)(void*))func, data);
    return (thread_t*)thread;
}
thread_t* thread_current() { return (thread_t*)pthread_self(); }
bool thread_join(thread_t* thread, int32_t wait_ms) {
    (void)wait_ms;  // Linux ignores the timeout too (no portable timed join).
    pthread_t* pthread = (pthread_t*)thread;
    pthread_join(*pthread, NULL);
    return true;
}
bool thread_join_all(thread_t** threads, uint32_t num_threads, int32_t wait_ms) {
    bool result = true;
    for (uint32_t i = 0; i < num_threads; i++) {
        result &= thread_join(threads[i], wait_ms);
    }
    return result;
}
bool thread_decrease_priority(thread_t* thread) {
    // NullPlayer: macOS has no pthread_setschedprio. Upstream's only caller passes
    // thread_current(), which is a bare pthread_t (not a pointer to one, as the Linux
    // file dereferences), so take the handle as the pthread_t itself.
    pthread_t pthread = (pthread_t)thread;
    struct sched_param param;
    int policy;
    if (pthread_getschedparam(pthread, &policy, &param) != 0) {
        return false;
    }
    param.sched_priority = sched_get_priority_min(policy);
    return pthread_setschedparam(pthread, policy, &param) == 0;
}
void thread_destroy(thread_t* thread) { free(thread); }

/* dynamic library loading */

dlib_t* library_load(const char* path) {
    return (dlib_t*)dlopen(path, RTLD_LAZY | RTLD_GLOBAL);
}
func_t library_get(dlib_t* library, const char* func_name) {
    dlerror();
    if (library == NULL) {
        return NULL;
    }
    void* function = dlsym(library, func_name);
    if (dlerror() != NULL) {
        return NULL;
    }
    return (func_t)function;
}
void library_unload(dlib_t* library) {
    if (library != NULL) {
        dlclose(library);
    }
}
const char* library_error() { return dlerror(); }

/* mkdir */

int create_directory(const char* path) { return mkdir(path, 0777) != 0; }

/* memory read-write-exec */

void mem_mark_rwx(void* block, size_t length) {
    // NullPlayer: page bounds in uintptr_t; the Linux file truncates pointers to 32 bits.
    // No libavs code calls this (EEL2 manages its own code pages); kept for the ABI.
    uintptr_t pagesize = (uintptr_t)sysconf(_SC_PAGESIZE);
    if (!pagesize) {
        pagesize = 4096;
    }
    uintptr_t start = (uintptr_t)block & ~(pagesize - 1);
    uintptr_t end = ((uintptr_t)block + length + pagesize - 1) & ~(pagesize - 1);
    mprotect((void*)start, end - start, PROT_WRITE | PROT_READ | PROT_EXEC);
}
