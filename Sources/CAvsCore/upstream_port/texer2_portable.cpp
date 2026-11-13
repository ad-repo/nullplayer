// NullPlayer: a C port of E_Texer2::DrawParticle's MMX loops, byte for byte. Each channel is
// a 16-bit lane as in the asm; where the scaling and non-scaling loops differ (adjustable
// blend, min/max operand order, masked multiply) the port follows each. One deliberate
// difference: the asm's scaling loop read one texel past the image for the last column and
// row's neighbours; the port clamps that read to the last texel instead of reading memory
// that is not the image.

#include "texer2_portable.h"

#include "vis_avs/blend.h"
#include "vis_avs/effect_common.h"

#include <algorithm>

namespace {
// Which asm loop a blend stands in for: they order min/max operands and weight the
// adjustable blend differently.
enum class Loop { scaling, non_scaling };

inline uint32_t byte_of(uint32_t v, int c) { return (v >> (8 * c)) & 0xFF; }

template <typename F>
inline uint32_t bytewise(uint32_t dst, uint32_t src, F f) {
    uint32_t out = 0;
    for (int c = 0; c < 4; c++) {
        out |= (std::min(f(byte_of(dst, c), byte_of(src, c)), 255u) & 0xFF) << (8 * c);
    }
    return out;
}

// The colour filter: each byte times the colour's byte, >> 8.
inline uint32_t filter(uint32_t v, uint32_t color) {
    return bytewise(v, color, [](uint32_t a, uint32_t b) { return (a * b) >> 8; });
}

// The asm's pcmpgtb select: gt = y > x per byte, unsigned on R, G, B (sign mask 0x808080)
// and signed on the fourth byte, whose mask is not inverted (0xFFFFFF).
inline uint32_t minmax(uint32_t x, uint32_t y, bool take_greater) {
    uint32_t gt = 0;
    for (int c = 0; c < 3; c++) {
        if (byte_of(y, c) > byte_of(x, c)) {
            gt |= 0xFFu << (8 * c);
        }
    }
    if ((int8_t)byte_of(y, 3) > (int8_t)byte_of(x, 3)) {
        gt |= 0xFF000000u;
    }
    uint32_t other = gt ^ 0x00FFFFFFu;
    return take_greater ? (x & other) | (y & gt) : (x & gt) | (y & other);
}

// Blends a source pixel onto dst in g_line_blend_mode. An unknown mode draws nothing, as the
// asm switch has no default.
inline uint32_t blend(uint32_t dst, uint32_t src, Loop loop) {
    uint32_t t = (g_line_blend_mode >> 8) & 0xFF;
    // The scaling loop compares (src, dst), the non-scaling one (dst, src).
    uint32_t x = loop == Loop::scaling ? src : dst;
    uint32_t y = loop == Loop::scaling ? dst : src;
    switch (g_line_blend_mode & 0xFF) {
        case BLEND_REPLACE: return src;
        case BLEND_ADDITIVE:
            return bytewise(dst, src, [](uint32_t d, uint32_t s) { return d + s; });
        case BLEND_MAXIMUM: return minmax(x, y, true);
        case BLEND_5050:
            return bytewise(dst, src, [](uint32_t d, uint32_t s) { return (d + s) >> 1; });
        case BLEND_SUB1:
            return bytewise(dst, src, [](uint32_t d, uint32_t s) { return d > s ? d - s : 0; });
        case BLEND_SUB2:
            return bytewise(dst, src, [](uint32_t d, uint32_t s) { return s > d ? s - d : 0; });
        case BLEND_MULTIPLY:
            return bytewise(dst, src, [](uint32_t d, uint32_t s) { return (d * s) >> 8; });
        case BLEND_ADJUSTABLE:
            if (loop == Loop::scaling) {  // dst * (255 - t) + src * t
                return bytewise(dst, src, [t](uint32_t d, uint32_t s) {
                    return ((d * (255 - t)) >> 8) + ((s * t) >> 8);
                });
            }
            // dst * t + src * (256 - t): the reverse weighting, as upstream
            return bytewise(dst, src, [t](uint32_t d, uint32_t s) {
                return std::min(d * t + s * (256 - t), 0xFFFFu) >> 8;
            });
        case BLEND_XOR: return dst ^ src;
        case BLEND_MINIMUM: return minmax(x, y, false);
        default: return dst;
    }
}
}  // namespace

void texer2_draw_scaled(int* framebuffer,
                        const pixel_rgb0_8* texture,
                        int tex_size,
                        int tex_stride,
                        int fb_stride,
                        int left,
                        int top,
                        int right,
                        int bottom,
                        int cx0,
                        int cy0,
                        int sdx,
                        int sdy,
                        uint32_t color) {
    auto texel = [&](uint32_t index) {
        return texture[std::min(index, (uint32_t)tex_size - 1)];
    };
    for (int y = top; y <= bottom; ++y, cy0 += sdy) {
        auto* outp = (uint32_t*)&framebuffer[y * fb_stride + left];
        uint32_t dy = ((uint32_t)cy0 & 0xFFFF) >> 8;
        uint32_t row = ((uint32_t)cy0 >> 16) * tex_stride;
        uint32_t cx = cx0;
        for (int k = 0; k <= right - left; ++k, cx += sdx) {
            uint32_t dx = (cx & 0xFFFF) >> 8;
            uint32_t at = row + (cx >> 16);
            uint32_t a = texel(at), b = texel(at + 1);
            uint32_t c = texel(at + tex_stride), d = texel(at + tex_stride + 1);
            uint32_t src = 0;
            for (int ch = 0; ch < 4; ch++) {
                uint32_t upper = ((byte_of(b, ch) * dx) >> 8)
                                 + ((byte_of(a, ch) * (dx ^ 0xFF)) >> 8);
                uint32_t lower = ((byte_of(c, ch) * (dx ^ 0xFF)) >> 8)
                                 + ((byte_of(d, ch) * dx) >> 8);
                uint32_t v = ((lower * dy) >> 8) + ((upper * (dy ^ 0xFF)) >> 8);
                src |= std::min((v * byte_of(color, ch)) >> 8, 255u) << (8 * ch);
            }
            outp[k] = blend(outp[k], src, Loop::scaling);
        }
    }
}

// Masked multiply filters the product, not the texel.
void texer2_draw_unscaled(int* framebuffer,
                          const pixel_rgb0_8* texture,
                          int tex_stride,
                          int fb_stride,
                          int left,
                          int top,
                          int right,
                          int bottom,
                          int cx0,
                          int ty,
                          bool colorize,
                          uint32_t color) {
    bool multiply = (g_line_blend_mode & 0xFF) == BLEND_MULTIPLY;
    for (int y = top; y <= bottom; ++y, ++ty) {
        auto* outp = (uint32_t*)&framebuffer[y * fb_stride + left];
        const pixel_rgb0_8* inp = &texture[ty * tex_stride + cx0];
        for (int k = 0; k <= right - left; ++k) {
            if (!colorize) {
                outp[k] = blend(outp[k], inp[k], Loop::non_scaling);
            } else if (multiply) {
                outp[k] = filter(blend(outp[k], inp[k], Loop::non_scaling), color);
            } else {
                outp[k] = blend(outp[k], filter(inp[k], color), Loop::non_scaling);
            }
        }
    }
}
