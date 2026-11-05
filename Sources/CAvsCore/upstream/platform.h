#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void lock_t;
typedef void dlib_t;
typedef void signal_t;
typedef void thread_t;

/*
 * OS specifics
 */
#ifdef _WIN32

#elif defined __linux__ || defined __APPLE__  // NullPlayer: macOS needs the same stdlib.h (size_t)

#include <stdlib.h>

// typedef pthread_mutex_t lock_t;

#endif  // OS specifics

/*
 * Compiler specifics
 */
#ifdef __GNUC__

/*
GCCs -Wcast-function-type is a bit overzealous when casting dynamic library function
pointers (whose signatures _will_ be mismatched most of the time). The warning can be
suppressed by first casting the function pointer to the special case void(*)(). This
macro makes this a bit less cryptic and explicit, while still keeping the warning
enabled for the cases where it might actually catch something.
*/
#define FORCE_FUNCTION_CAST(x) (x)(void (*)())

#else

// A no-op here, see above.
#define FORCE_FUNCTION_CAST(x) (x)

#endif  // Compiler specifics

/* Including windows.h on MSVC (not GCC!) would define min/max, but we set NOMINMAX for
 * the project, so we can define them all the same for all platforms. */
int min(int a, int b);
int max(int a, int b);
unsigned int umin(unsigned int a, unsigned int b);
unsigned int umax(unsigned int a, unsigned int b);

/* The number of milliseconds since the system was booted. May return 0 on error. */
uint64_t timer_ms();
/* A high-precision microsecond resolution counter for performance measuring. */
uint64_t timer_us();
/**
 * The actual timer precision available from `timer_us()`, in microseconds.
 */
double timer_us_precision();

/**
 * Return a string pointer with the current date in the format "YYYY-MM-DD" (11 bytes).
 * The data is stored in a static buffer, so the return pointer is always the same, but
 * its contents are not guaranteed to stay the same between calls to this function.
 */
const char* current_date_str();

/**
 * Create a new lock object.
 */
lock_t* lock_init();
/**
 * Lock the lock.
 */
void lock_lock(lock_t* lock_obj);
/**
 * Check if the lock is free. Take it if possible and return `true`, else return
 * `false`.
 */
bool lock_try(lock_t* lock_obj);
/**
 * Take the lock if possible, else wait for it to become available.
 */
void lock_unlock(lock_t* lock_obj);
/**
 * Destroy the given lock object.
 */
void lock_destroy(lock_t* lock_obj);

/**
 * Load a dynamic library (.dll, .so) by file path.
 * Returns NULL on error.
 */
dlib_t* library_load(const char* path);

typedef void (*func_t)();
/**
 * Get a pointer to a named function in the library.
 * Use `FORCE_FUNCTION_CAST()` to cast the function type to the correct one.
 * Returns NULL on error.
 */
func_t library_get(dlib_t* library, const char* func_name);
/**
 * Unmap the given library from memory and destroy the library object.
 */
void library_unload(dlib_t* library);
/**
 * Get the last error message from the library loader.
 */
const char* library_error();

#define WAIT_INFINITE (-1)
/**
 * Create a signal which, when fired, will be received by _one_ (random) thread waiting
 * for it.
 */
signal_t* signal_create_single();
/**
 * Create a signal which, when fired, will be received by _all_ threads waiting for it.
 */
signal_t* signal_create_broadcast();
/**
 * Fire the signal. Depending on the type one or all threads will receive it. */
void signal_set(signal_t* signal);
/**
 * Reset a signal to non-fired state.
 */
void signal_unset(signal_t* signal);
/**
 * Wait for a signal to be received, at most `wait_ms`.
 * Pass `WAIT_INFINITE` to `wait_ms` to wait forever.
 * Returns NULL if timeout was hit or other error occurred.
 */
signal_t* signal_wait(signal_t* signal, int32_t wait_ms);
/**
 * Wait for any of the given signals to be received, at most `wait_ms`.
 * Pass `WAIT_INFINITE` to `wait_ms` to wait forever.
 * Returns NULL if timeout was hit or other error occurred.
 */
signal_t* signal_wait_any(signal_t** signals, uint32_t num_signals, int32_t wait_ms);
/**
 * Wait for all of the given signals to be received, at most `wait_ms`.
 * Pass `WAIT_INFINITE` to `wait_ms` to wait forever.
 * Returns NULL if timeout was hit or other error occurred.
 */
signal_t* signal_wait_all(signal_t** signals, uint32_t num_signals, int32_t wait_ms);
/**
 * Destroy the given signal object.
 */
void signal_destroy(signal_t* signal);

/**
 * Create a thread object.
 */
thread_t* thread_create(uint32_t (*func)(void* data), void* data);
/**
 * Get the current thread.
 */
thread_t* thread_current();
/**
 * Wait for a thread to finish, at most `wait_ms`.
 * Pass `WAIT_INFINITE` to `wait_ms` to wait forever.
 * Returns false if timeout was hit or other error occurred.
 */
bool thread_join(thread_t* thread, int32_t wait_ms);
/**
 * Wait for all of the given threads to finish, at most `wait_ms`.
 * Pass `WAIT_INFINITE` to `wait_ms` to wait forever.
 * Returns false if timeout was hit or other error occurred.
 */
bool thread_join_all(thread_t** threads, uint32_t num_threads, int32_t wait_ms);
/**
 * Decrease the priority of the thread. Return true when successful. Possible reasons
 * for error are:
 * - `thread` is NULL,
 * - the thread is already running at the lowest priority,
 * - failure to get the thread's current priority
 * - failure to set the thread's new priority (permissions, etc.)
 *
 * Note: Only superusers can raise a thread's priority after it has been lowered (on
 * both Windows and Linux). So there's only this method, and no "increase priority"
 * method.
 */
bool thread_decrease_priority(thread_t* thread);
/**
 * Destroy the given thread object.
 */
void thread_destroy(thread_t* thread);

int create_directory(const char* path);

/**
 * The available logging levels from most- to least verbose.
 */
enum LogLevel { LOG_DEBUG, LOG_INFO, LOG_WARN, LOG_ERR, LOG_NONE };
/**
 * The current log level.
 */
extern enum LogLevel g_log_level;
/**
 * Set the current log level.
 */
void log_set_level(enum LogLevel level);
/**
 * Log a message at DEBUG level, i.e. the most verbose.
 * If not compiled with DEBUG compile flag, this is a no-op regardless of log level.
 */
#ifdef DEBUG
void log_debug(const char* fmt, ...);
#else
#define log_debug(fmt, ...)
#endif
/**
 * Log a message at INFO level, i.e. the lowest importance.
 */
void log_info(const char* fmt, ...);
/**
 * Log a message at WARN level, i.e. recoverable errors that should be looked into.
 */
void log_warn(const char* fmt, ...);
/**
 * Log a message at ERR level, i.e. unrecoverable errors.
 */
void log_err(const char* fmt, ...);

/* memory read-write-exec */

void mem_mark_rwx(void* block, size_t length);

/**
 * Print the last OS API error message.
 */
void print_last_system_error();

#ifdef __cplusplus
}
#endif
