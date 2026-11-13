// NullPlayer: a C port of the code E_Convolution::create_draw_func() emits, read off the
// emitted instructions, quirks kept so output matches the original plugin:
//  - 16-bit lanes per channel; a side sums with wrapping adds while its absolute total
//    (bias included) is under 256, saturating adds otherwise; the bias always saturates.
//  - Rows clamp to [0, h-2] and the last three columns to w-2: the last row and column are
//    never read.
//  - The second pass rotates each tap 90 degrees but multiplies a weight that is not a
//    power of two by the kernel value at the rotated position.
//  - The two passes are summed (paddusw, though the original comment says psubusw).
//  - "Absolute" is a saturating signed subtract with the sign bit cleared.
//  - A non-power-of-two scale is a 16.16 reciprocal multiply on R, G and B only.
//  - With no non-zero weight before the centre the frame is filtered in place.

#include "convolution_portable.h"

#include "vis_avs/e_convolution.h"

#include <algorithm>

namespace {
inline bool is_pow2(uint32_t v) { return v != 0 && (v & (v - 1)) == 0; }

inline uint16_t add16(uint16_t a, uint32_t b, bool saturate) {
    uint32_t r = a + b;
    return saturate ? (uint16_t)std::min(r, 0xFFFFu) : (uint16_t)r;
}
}  // namespace

void Convolution_Portable::plan(const Convolution_Config& config) {
    uint16_t weight[CONVO_KERNEL_SIZE];
    uint32_t possum = 0, negsum = 0;
    int zerostringl = 0;
    bool zerostring = true;
    for (int i = 0; i < CONVO_KERNEL_SIZE; i++) {
        auto v = (int32_t)config.kernel[i].value;
        weight[i] = (uint16_t)(v < 0 ? -v : v);
        if (v < 0) {
            negsum -= v;
        } else if (v > 0) {
            possum += v;
        }
        if (v != 0) {
            zerostring = false;
        } else if (zerostring) {
            zerostringl++;
        }
    }
    auto bias = (int32_t)config.bias;
    if (bias < 0) {
        negsum -= bias;
    } else {
        possum += bias;
    }
    this->divisor = (int32_t)config.scale;
    bool swap = this->divisor < 0;  // a negative scale swaps the sides and divides by -scale
    if (swap) {
        this->divisor = -this->divisor;
    }
    for (auto& pass : this->taps) {
        for (auto& side : pass) {
            side.clear();
        }
    }
    for (int i = 0; i < CONVO_KERNEL_SIZE; i++) {
        auto v = (int32_t)config.kernel[i].value;
        if (v == 0) {
            continue;
        }
        int side = ((v > 0) != swap) ? 0 : 1;
        int x = i % CONVO_KERNEL_DIM, y = i / CONVO_KERNEL_DIM;
        int rx = 6 - y, ry = x;
        this->taps[0][side].push_back({x - 3, y - 3, weight[i]});
        uint16_t rotated_mul =
            is_pow2(weight[i]) ? weight[i] : weight[CONVO_KERNEL_DIM * ry + rx];
        this->taps[1][side].push_back({rx - 3, ry - 3, rotated_mul});
    }
    this->bias_side = bias == 0 ? -1 : (((bias > 0) != swap) ? 0 : 1);
    this->bias_word = (uint16_t)(256 * (bias < 0 ? -bias : bias));
    this->has_neg = !this->taps[0][1].empty() || this->bias_side == 1;
    this->saturate[0] = possum >= 256;
    this->saturate[1] = negsum >= 256;
    this->shift = is_pow2((uint32_t)this->divisor) ? __builtin_ctz((uint32_t)this->divisor) : -1;
    this->reciprocal = 65536 / this->divisor;
    this->passes = config.two_pass ? 2 : 1;
    this->absolute = config.absolute;
    this->wrap = config.wrap;
    this->use_fbout = zerostringl < (CONVO_KERNEL_SIZE / 2);
}

int Convolution_Portable::apply(int* framebuffer, int* fbout, int w, int h) const {
    if (w < 8 || h < 8) {
        return 0;
    }
    int* out = this->use_fbout ? fbout : framebuffer;
    for (int j = 0; j < h; j++) {
        const int* rows[CONVO_KERNEL_DIM];
        for (int k = 0; k < CONVO_KERNEL_DIM; k++) {
            rows[k] = framebuffer + w * std::min(std::max(j + k - 3, 0), h - 2);
        }
        for (int i = 0; i < w; i++) {
            uint16_t result[4] = {0, 0, 0, 0};
            for (int pass = 0; pass < this->passes; pass++) {
                uint16_t acc[2][4] = {};
                for (int side = 0; side < 2; side++) {
                    for (const auto& tap : this->taps[pass][side]) {
                        int col = i + tap.dx;
                        if (i < 3) {
                            col = std::max(col, 0);
                        } else if (i >= w - 3) {
                            col = std::min(col, w - 2);
                        }
                        auto px = (uint32_t)rows[tap.dy + 3][col];
                        for (int c = 0; c < 4; c++) {
                            auto term = (uint16_t)(((px >> (8 * c)) & 0xFF) * tap.mul);
                            acc[side][c] = add16(acc[side][c], term, this->saturate[side]);
                        }
                    }
                    if (this->bias_side == side) {
                        for (int c = 0; c < 4; c++) {
                            acc[side][c] = add16(acc[side][c], this->bias_word, true);
                        }
                    }
                }
                for (int c = 0; c < 4; c++) {
                    uint16_t a = acc[0][c], b = acc[1][c], r = a;
                    if (this->has_neg) {
                        if (this->absolute) {
                            int d = (int16_t)a - (int16_t)b;
                            r = (uint16_t)std::min(std::max(d, -32768), 32767) & 0x7FFF;
                        } else if (this->wrap) {
                            r = (uint16_t)(a - b);
                        } else {
                            r = a > b ? (uint16_t)(a - b) : 0;
                        }
                    }
                    result[c] = add16(result[c], r, true);
                }
            }
            uint32_t pixel = 0;
            for (int c = 0; c < 4; c++) {
                uint16_t v = result[c];
                if (this->divisor != 1) {
                    if (this->shift >= 0) {
                        v >>= this->shift;
                    } else if (c < 3) {
                        v = (uint16_t)((v * this->reciprocal) >> 16);
                    }
                }
                auto s = (int16_t)v;
                pixel |= (uint32_t)(s < 0 ? 0 : std::min((int)s, 255)) << (8 * c);
            }
            out[j * w + i] = (int)pixel;
        }
    }
    return this->use_fbout ? 1 : 0;
}
