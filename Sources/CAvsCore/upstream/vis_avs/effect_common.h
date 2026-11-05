#pragma once

#include <stdint.h>

enum Blend_Modes {
    BLEND_REPLACE = 0,
    BLEND_ADDITIVE = 1,
    BLEND_MAXIMUM = 2,
    BLEND_5050 = 3,
    BLEND_SUB1 = 4,
    BLEND_SUB2 = 5,
    BLEND_MULTIPLY = 6,
    BLEND_ADJUSTABLE = 7,
    BLEND_XOR = 8,
    BLEND_MINIMUM = 9,
};

enum Blend_Modes_Simple {
    BLEND_SIMPLE_REPLACE = 0,
    BLEND_SIMPLE_5050 = 1,
    BLEND_SIMPLE_ADDITIVE = 2,
};

enum Audio_Sources { AUDIO_WAVEFORM = 0, AUDIO_SPECTRUM = 1 };
enum Audio_Channels { AUDIO_LEFT = 0, AUDIO_RIGHT = 1, AUDIO_CENTER = 2 };
enum Draw_Modes { DRAW_DOTS = 0, DRAW_LINES = 1, DRAW_SOLID = 2 };
enum Horizontal_Positions { HPOS_LEFT = 0, HPOS_RIGHT = 1, HPOS_CENTER = 2 };
enum Vertical_Positions { VPOS_TOP = 0, VPOS_BOTTOM = 1, VPOS_CENTER = 2 };
enum Coordinates { COORDS_POLAR = 0, COORDS_CARTESIAN = 1 };

const char* const* audio_sources(int64_t* length_out);
const char* const* draw_modes(int64_t* length_out);
const char* const* audio_channels(int64_t* length_out);
const char* const* h_positions(int64_t* length_out);
const char* const* v_positions(int64_t* length_out);
const char* const* blend_modes(int64_t* length_out);
const char* const* blend_modes_simple(int64_t* length_out);
