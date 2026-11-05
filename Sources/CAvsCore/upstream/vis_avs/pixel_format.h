#pragma once

#include "avs.h"

#include <stdint.h>

typedef uint32_t pixel_rgb0_8;
// typedef uint32_t pixel_argb_8;
// typedef uint32_t pixel_rgb0_10;
// typedef uint64_t pixel_rgb016;
// typedef uint64_t pixel_argb_16;

#define pixel_size(_) sizeof(pixel_rgb0_8)
/* use this in the future:
inline size_t pixel_size(AVS_Pixel_Format pixel_format) {
    switch (pixel_format) {
        default:
        case AVS_PIXEL_RGB0_8:
            return sizeof(pixel_rgb0_8);
        case AVS_PIXEL_ARGB_8:
            return sizeof(pixel_argb_8);
        case AVS_PIXEL_RGB0_10:
            return sizeof(pixel_rgb0_10);
        case AVS_PIXEL_RGB0_16:
            return sizeof(pixel_rgb0_16);
        case AVS_PIXEL_ARGB_16:
            return sizeof(pixel_argb_16);
    }
}
*/

#define AVS_PIXEL_COLOR_MASK_RGB0_8 0x00ffffff
// #define AVS_PIXEL_COLOR_MASK_ARGB_8 0x00ffffff
// #define AVS_PIXEL_COLOR_MASK_RGB0_10 0x3fffffff
// #define AVS_PIXEL_COLOR_MASK_RGB0_16 0x0000ffffffffffff
// #define AVS_PIXEL_COLOR_MASK_ARGB_16 0x0000ffffffffffff
