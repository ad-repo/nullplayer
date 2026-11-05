#include "effect_common.h"

const char* const* audio_sources(int64_t* length_out) {
    if (length_out) {
        *length_out = 2;
    }
    static const char* const options[2] = {
        "Waveform",
        "Spectrum",
    };
    return options;
}

const char* const* draw_modes(int64_t* length_out) {
    if (length_out) {
        *length_out = 3;
    }
    static const char* const options[3] = {
        "Dots",
        "Lines",
        "Solid",
    };
    return options;
}

const char* const* audio_channels(int64_t* length_out) {
    if (length_out) {
        *length_out = 3;
    }
    static const char* const options[3] = {
        "Left",
        "Right",
        "Center",
    };
    return options;
}

const char* const* h_positions(int64_t* length_out) {
    if (length_out) {
        *length_out = 3;
    }
    static const char* const options[3] = {
        "Left",
        "Right",
        "Center",
    };
    return options;
}

const char* const* v_positions(int64_t* length_out) {
    if (length_out) {
        *length_out = 3;
    }
    static const char* const options[3] = {
        "Top",
        "Bottom",
        "Center",
    };
    return options;
}

const char* const* blend_modes(int64_t* length_out) {
    if (length_out) {
        *length_out = 10;
    }
    static const char* const options[10] = {
        "Replace",
        "Additive",
        "Maximum",
        "50/50",
        "Subtractive 1",
        "Subtractive 2",
        "Multiply",
        "Adjustable",
        "XOR",
        "Minimum",
    };
    return options;
}

const char* const* blend_modes_simple(int64_t* length_out) {
    if (length_out) {
        *length_out = 3;
    }
    static const char* const options[3] = {
        "Replace",
        "50/50",
        "Additive",
    };
    return options;
}
