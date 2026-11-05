#pragma once

#include "avs_editor.h"  // AVS_Parameter_Handle

#include <map>
#include <vector>

class Handles {
   private:
    uint32_t state;

   public:
    Handles() { this->state = 1000; }
    AVS_Handle get() { return this->state++; }

    /**
     * Generate a handle at compile time. Needs an input string that it will hash into a
     * 32bit unsigned integer. Use __LINE__, __FILE__ or other variable compile-time
     * information as input to generate a random handle.
     *
     * Reference:
     * https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function
     *
     * Thanks to https://notes.underscorediscovery.com/constexpr-fnv1a/ for the idea.
     */
    static inline constexpr AVS_Handle comptime_get(const char* const input) {
        return Handles::_fnv1a(input) % 0xfffffffe + 1;
    }

   private:
    static constexpr uint32_t FNV1A_OFFSET = 0x811c9dc5;
    static constexpr uint32_t FNV1A_PRIME = (1 << 24) + (1 << 8) + 0x93;
    static inline constexpr uint32_t _fnv1a(const char* const input,
                                            uint32_t value = FNV1A_OFFSET) {
        return (input[0] == '\0')
                   ? value
                   : Handles::_fnv1a(&input[1], (value ^ input[0]) * FNV1A_PRIME);
    }
};

// The stringification of __LINE__ would normally make it evaluate early, i.e. to the
// line of the macro. With the double indirect below, __LINE__ is expanded at the
// location where COMPTIME_HANDLE is used.
#define HANDLE_MACRO_INDIRECT_2(f, l, ...) f #l __VA_ARGS__
#define HANDLE_MACRO_INDIRECT_1(f, l, ...) HANDLE_MACRO_INDIRECT_2(f, l, __VA_ARGS__)
/** Create a handle at compile time based on the filename and the linenumber. */
#define COMPTIME_HANDLE \
    Handles::comptime_get(HANDLE_MACRO_INDIRECT_1(__FILE__, __LINE__))
#define COMPTIME_HANDLE_FROM(x) \
    Handles::comptime_get(HANDLE_MACRO_INDIRECT_1(__FILE__, __LINE__, x))

extern Handles h_instances;
extern Handles h_components;
extern std::map<AVS_Parameter_Handle, std::vector<AVS_Parameter_Handle>>
    h_parameter_children;
