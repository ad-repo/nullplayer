#include "platform.h"

int min(int a, int b) { return a > b ? b : a; }
int max(int a, int b) { return a < b ? b : a; }

// Yes, these includes should come _after_ min/max are defined.
// Otherwise MSVC will complain: "error C2059: syntax error: '<parameter-list>'"
// TODO [clean][bug]: Fix cleanly or ensure that min/max still works as intended on
//                    Windows.
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

unsigned int umin(unsigned int a, unsigned int b) { return a > b ? b : a; }
unsigned int umax(unsigned int a, unsigned int b) { return a < b ? b : a; }

enum LogLevel g_log_level = LOG_WARN;
void log_set_level(enum LogLevel level) { g_log_level = level; }
#define LOG(level)                                                              \
    if (g_log_level <= LOG_##level) {                                           \
        const char* prefix = #level;                                            \
        uint64_t time = timer_ms();                                             \
        char time_str[32];                                                      \
        snprintf(time_str, 32, "%llu.%03llu", time / 1000, time % 1000);        \
        size_t fmt_str_len = strlen(time_str) + strlen(" ") + strlen(prefix)    \
                             + strlen(": ") + strnlen(fmt, 1024) + strlen("\n") \
                             + sizeof('\0');                                    \
        char* log_fmt_str = (char*)calloc(fmt_str_len, sizeof(char));           \
        strcpy(log_fmt_str, time_str);                                          \
        strcat(log_fmt_str, " ");                                               \
        strcat(log_fmt_str, prefix);                                            \
        strcat(log_fmt_str, ": ");                                              \
        strncat(log_fmt_str, fmt, 1024);                                        \
        strcat(log_fmt_str, "\n");                                              \
        va_list args;                                                           \
        va_start(args, fmt);                                                    \
        vfprintf(stderr, log_fmt_str, args);                                    \
    }
#ifdef DEBUG
void log_debug(const char* fmt, ...) { LOG(DEBUG); }
#endif
void log_info(const char* fmt, ...) { LOG(INFO); }
void log_warn(const char* fmt, ...) { LOG(WARN); }
void log_err(const char* fmt, ...) { LOG(ERR); }
