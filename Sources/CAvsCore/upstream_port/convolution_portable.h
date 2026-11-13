#pragma once

// NullPlayer: Convolution Filter on anything but i386. Upstream's E_Convolution JITs 32-bit
// x86 code (create_draw_func); this computes what that code computes. `plan` does the work
// create_draw_func does once per kernel change, `apply` the per-frame pixel loop.

#include <cstdint>
#include <vector>

struct Convolution_Config;

class Convolution_Portable {
   public:
    void plan(const Convolution_Config& config);
    // Returns 1 when the result is in fbout, 0 when the frame was filtered in place or too
    // small to filter, as E_Convolution::render does.
    int apply(int* framebuffer, int* fbout, int w, int h) const;

   private:
    struct Tap {
        int dx, dy;
        uint16_t mul;
    };
    std::vector<Tap> taps[2][2];  // [pass][side]: side 0 is added, side 1 subtracted
    int bias_side = -1;
    uint16_t bias_word = 0;
    bool has_neg = false;
    bool saturate[2] = {false, false};
    int divisor = 1;
    int shift = 0;  // log2(divisor) when it is a power of two, else -1
    uint32_t reciprocal = 65536;
    int passes = 1;
    bool absolute = false;
    bool wrap = false;
    bool use_fbout = true;
};
