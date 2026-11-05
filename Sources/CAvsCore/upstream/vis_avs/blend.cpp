#include "blend.h"

#include "pixel_format.h"

#include "../platform.h"

#include <cstdint>
#include <immintrin.h>
#include <stdio.h>
#include <string.h>

#include <sys/types.h>

uint8_t lut_u8_multiply[256][256];
static uint8_t lut_u8_screen[256][256];
static uint8_t lut_u8_linear_burn[256][256];
static uint8_t lut_u8_color_dodge[256][256];
static uint8_t lut_u8_color_burn[256][256];

/**
 * Generate lookup tables (LUTs) for u8.
 * The resulting multiply table looks like this (for a hypothetical 16x16 table):
 *
 *     00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
 *     00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 01
 *     00 00 00 00 00 00 00 00 01 01 01 01 01 01 01 02
 *     00 00 00 00 00 01 01 01 01 01 02 02 02 02 02 03
 *     00 00 00 00 01 01 01 01 02 02 02 02 03 03 03 04
 *     00 00 00 01 01 01 02 02 02 03 03 03 04 04 04 05
 *     00 00 00 01 01 02 02 02 03 03 04 04 04 05 05 06
 *     00 00 00 01 01 02 02 03 03 04 04 05 05 06 06 07
 *     00 00 01 01 02 02 03 03 04 04 05 05 06 06 07 08
 *     00 00 01 01 02 03 03 04 04 05 06 06 07 07 08 09
 *     00 00 01 02 02 03 04 04 05 06 06 07 08 08 09 10
 *     00 00 01 02 02 03 04 05 05 06 07 08 08 09 10 11
 *     00 00 01 02 03 04 04 05 06 07 08 08 09 10 11 12
 *     00 00 01 02 03 04 05 06 06 07 08 09 10 11 12 13
 *     00 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14
 *     00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15
 *
 */
void make_blend_LUTs() {
    for (int k = 0; k < 256; k++) {
        for (int i = 0; i < 256; i++) {
            lut_u8_multiply[i][k] = (uint8_t)((i * k) / 255);
            lut_u8_screen[i][k] = (uint8_t)(255 - ((255 - i) * (255 - k) / 255));
            lut_u8_color_dodge[i][k] = (uint8_t)((float)i / (255.0 - k));
            lut_u8_linear_burn[i][k] = (uint8_t)(i + k - 255);
            lut_u8_color_burn[i][k] = (uint8_t)(255 - ((255.0 - i) / (float)(k)));
        }
    }
}

// REPLACE BLEND

void blend_replace(const uint32_t* src, uint32_t* dest, uint32_t w, uint32_t h) {
    memcpy(dest, src, w * h * pixel_size(pixel_rgb0_8));
}

void blend_replace_fill(uint32_t src, uint32_t* dest, uint32_t w) {
    for (size_t i = 0; i < w; i++) {
        dest[i] = src;
    }
}

// ADDITIVE BLEND

static inline void blend_add_rgb0_8_c(const uint32_t* src1,
                                      const uint32_t* src2,
                                      uint32_t* dest) {
    uint32_t channel = (*src1 & 0xff) + (*src2 & 0xff);
    uint32_t out = min(channel, 0xff);
    channel = (*src1 & 0xff00) + (*src2 & 0xff00);
    out |= min(channel, 0xff00);
    channel = (*src1 & 0xff0000) + (*src2 & 0xff0000);
    *dest = out | min(channel, 0xff0000);
}

static inline void blend_add_rgb0_8_x86v128(const uint32_t* src1,
                                            const uint32_t* src2,
                                            uint32_t* dest) {
    __m128i src1_4px = _mm_loadu_si128((__m128i*)src1);
    __m128i src2_4px = _mm_loadu_si128((__m128i*)src2);
    _mm_storeu_si128((__m128i*)dest, _mm_adds_epu8(src1_4px, src2_4px));
}

void blend_add(const uint32_t* src1,
               const uint32_t* src2,
               uint32_t* dest,
               uint32_t w,
               uint32_t h) {
#ifdef SIMD_MODE_X86_SSE
    for (size_t i = 0; i < w * h; i += 4) {
        blend_add_rgb0_8_x86v128(&src1[i], &src2[i], &dest[i]);
    }
#else
    for (size_t i = 0; i < w * h; i++) {
        blend_add_rgb0_8_c(&src1[i], &src2[i], &dest[i]);
    }
#endif
}

// 50/50 BLEND

static inline void blend_5050_rgb0_8_c(const uint32_t* src1,
                                       const uint32_t* src2,
                                       uint32_t* dest) {
    static uint32_t strip_high_bit_mask = 0x007f7f7f;
    *dest = ((*src1 >> 1) & strip_high_bit_mask) + ((*src2 >> 1) & strip_high_bit_mask);
}

static inline void blend_5050_rgb0_8_x86v128(const uint32_t* src1,
                                             const uint32_t* src2,
                                             uint32_t* dest) {
    __m128i src1_4px = _mm_loadu_si128((__m128i*)src1);
    __m128i src2_4px = _mm_loadu_si128((__m128i*)src2);
    // This should use _mm_avg_epu8(), but that does a correct average, i.e. it does
    // (a + b + 1) / 2, while avs does (a + b) / 2. We opt for consistency and backward
    // compatibility here.
    __m128i strip_high_bit_mask = _mm_set1_epi32(0x007f7f7f);
    __m128i src1_half = _mm_and_si128(_mm_srli_epi16(src1_4px, 1), strip_high_bit_mask);
    __m128i src2_half = _mm_and_si128(_mm_srli_epi16(src2_4px, 1), strip_high_bit_mask);
    _mm_storeu_si128((__m128i*)dest, _mm_adds_epu8(src1_half, src2_half));
}

void blend_5050(const uint32_t* src1,
                const uint32_t* src2,
                uint32_t* dest,
                uint32_t w,
                uint32_t h) {
#ifdef SIMD_MODE_X86_SSE
    for (size_t i = 0; i < w * h; i += 4) {
        blend_5050_rgb0_8_x86v128(&src1[i], &src2[i], &dest[i]);
    }
#else
    for (size_t i = 0; i < w * h; i++) {
        blend_5050_rgb0_8_c(&src1[i], &src2[i], &dest[i]);
    }
#endif
}

// MULTIPLY BLEND

static inline void blend_multiply_rgb0_8_c(const uint32_t* src1,
                                           const uint32_t* src2,
                                           uint32_t* dest) {
    uint8_t result = lut_u8_multiply[*src1 & 0xFF][*src2 & 0xFF];
    result |= lut_u8_multiply[(*src1 & 0xFF00) >> 8][(*src2 & 0xFF00) >> 8] << 8;
    result |= lut_u8_multiply[(*src1 & 0xFF0000) >> 16][(*src2 & 0xFF0000) >> 16] << 16;
    *dest = result;
}

static inline void blend_multiply_rgb0_8_x86v128(const uint32_t* src1,
                                                 const uint32_t* src2,
                                                 uint32_t* dest) {
    __m128i src1_4px = _mm_loadu_si128((__m128i*)src1);
    __m128i src2_4px = _mm_loadu_si128((__m128i*)src2);
    __m128i src1_lo_2px = _mm_unpacklo_epi8(src1_4px, _mm_setzero_si128());
    __m128i src1_hi_2px = _mm_unpackhi_epi8(src1_4px, _mm_setzero_si128());
    __m128i src2_lo_2px = _mm_unpacklo_epi8(src2_4px, _mm_setzero_si128());
    __m128i src2_hi_2px = _mm_unpackhi_epi8(src2_4px, _mm_setzero_si128());
    __m128i mul_lo = _mm_mullo_epi16(src1_lo_2px, src2_lo_2px);
    __m128i mul_hi = _mm_mullo_epi16(src1_hi_2px, src2_hi_2px);
    __m128i mul_lo_norm = _mm_srli_epi16(mul_lo, 8);
    __m128i mul_hi_norm = _mm_srli_epi16(mul_hi, 8);
    __m128i packed = _mm_packus_epi16(mul_lo_norm, mul_hi_norm);
    _mm_storeu_si128((__m128i*)dest, packed);
}

void blend_multiply(const uint32_t* src1,
                    const uint32_t* src2,
                    uint32_t* dest,
                    uint32_t w,
                    uint32_t h) {
#ifdef SIMD_MODE_X86_SSE
    for (size_t i = 0; i < w * h; i += 4) {
        blend_multiply_rgb0_8_x86v128(&src1[i], &src2[i], &dest[i]);
    }
#else
    for (size_t i = 0; i < w * h; i++) {
        blend_multiply_rgb0_8_c(&src1[i], &src2[i], &dest[i]);
    }
#endif
}

// SCREEN BLEND

static inline void blend_screen_rgb0_8_c(const uint32_t* src1,
                                         const uint32_t* src2,
                                         uint32_t* dest) {
    uint8_t result = lut_u8_screen[*src1 & 0xFF][*src2 & 0xFF];
    result |= lut_u8_screen[(*src1 & 0xFF00) >> 8][(*src2 & 0xFF00) >> 8] << 8;
    result |= lut_u8_screen[(*src1 & 0xFF0000) >> 16][(*src2 & 0xFF0000) >> 16] << 16;
    *dest = result;
}

static inline void blend_screen_rgb0_8_x86v128(const uint32_t* src1,
                                               const uint32_t* src2,
                                               uint32_t* dest) {
    __m128i src1_4px = _mm_loadu_si128((__m128i*)src1);
    __m128i src2_4px = _mm_loadu_si128((__m128i*)src2);
    src1_4px = _mm_xor_si128(src1_4px, _mm_set1_epi32(0x00ffffff));
    src2_4px = _mm_xor_si128(src2_4px, _mm_set1_epi32(0x00ffffff));
    __m128i src1_lo_2px = _mm_unpacklo_epi8(src1_4px, _mm_setzero_si128());
    __m128i src1_hi_2px = _mm_unpackhi_epi8(src1_4px, _mm_setzero_si128());
    __m128i src2_lo_2px = _mm_unpacklo_epi8(src2_4px, _mm_setzero_si128());
    __m128i src2_hi_2px = _mm_unpackhi_epi8(src2_4px, _mm_setzero_si128());
    __m128i mul_lo = _mm_mullo_epi16(src1_lo_2px, src2_lo_2px);
    __m128i mul_hi = _mm_mullo_epi16(src1_hi_2px, src2_hi_2px);
    __m128i mul_lo_norm = _mm_srli_epi16(mul_lo, 8);
    __m128i mul_hi_norm = _mm_srli_epi16(mul_hi, 8);
    __m128i packed = _mm_packus_epi16(mul_lo_norm, mul_hi_norm);
    packed = _mm_xor_si128(packed, _mm_set1_epi32(0x00ffffff));
    _mm_storeu_si128((__m128i*)dest, packed);
}

void blend_screen(const uint32_t* src1,
                  const uint32_t* src2,
                  uint32_t* dest,
                  uint32_t w,
                  uint32_t h) {
#ifdef SIMD_MODE_X86_SSE
    for (size_t i = 0; i < w * h; i += 4) {
        blend_screen_rgb0_8_x86v128(&src1[i], &src2[i], &dest[i]);
    }
#else
    for (size_t i = 0; i < w * h; i++) {
        blend_screen_rgb0_8_c(&src1[i], &src2[i], &dest[i]);
    }
#endif
}

// MAXIMUM BLEND

static inline void blend_maximum_rgb0_8_c(const uint32_t* src1,
                                          const uint32_t* src2,
                                          uint32_t* dest) {
    uint32_t channel = *src1 & 0xff;
    uint32_t out = max(channel, *src2 & 0xff);
    channel = *src1 & 0xff00;
    out |= max(channel, *src2 & 0xff00);
    channel = *src1 & 0xff0000;
    *dest = out | max(channel, *src2 & 0xff0000);
}

static inline void blend_maximum_rgb0_8_x86v128(const uint32_t* src1,
                                                const uint32_t* src2,
                                                uint32_t* dest) {
    __m128i src1_4px = _mm_loadu_si128((__m128i*)src1);
    __m128i src2_4px = _mm_loadu_si128((__m128i*)src2);
    _mm_storeu_si128((__m128i*)dest, _mm_max_epu8(src1_4px, src2_4px));
}

void blend_maximum(const uint32_t* src1,
                   const uint32_t* src2,
                   uint32_t* dest,
                   uint32_t w,
                   uint32_t h) {
#ifdef SIMD_MODE_X86_SSE
    for (size_t i = 0; i < w * h; i += 4) {
        blend_maximum_rgb0_8_x86v128(&src1[i], &src2[i], &dest[i]);
    }
#else
    for (size_t i = 0; i < w * h; i++) {
        blend_maximum_rgb0_8_c(&src1[i], &src2[i], &dest[i]);
    }
#endif
}

// MINIMUM BLEND

static inline void blend_minimum_rgb0_8_c(const uint32_t* src1,
                                          const uint32_t* src2,
                                          uint32_t* dest) {
    *dest = min(*src1 & 0xff, *src2 & 0xff) | min(*src1 & 0xff00, *src2 & 0xff00)
            | min(*src1 & 0xff0000, *src2 & 0xff0000);
}

static inline void blend_minimum_rgb0_8_x86v128(const uint32_t* src1,
                                                const uint32_t* src2,
                                                uint32_t* dest) {
    __m128i src1_4px = _mm_loadu_si128((__m128i*)src1);
    __m128i src2_4px = _mm_loadu_si128((__m128i*)src2);
    _mm_storeu_si128((__m128i*)dest, _mm_min_epu8(src1_4px, src2_4px));
}

void blend_minimum(const uint32_t* src1,
                   const uint32_t* src2,
                   uint32_t* dest,
                   uint32_t w,
                   uint32_t h) {
#ifdef SIMD_MODE_X86_SSE
    for (size_t i = 0; i < w * h; i += 4) {
        blend_minimum_rgb0_8_x86v128(&src1[i], &src2[i], &dest[i]);
    }
#else
    for (size_t i = 0; i < w * h; i++) {
        blend_minimum_rgb0_8_c(&src1[i], &src2[i], &dest[i]);
    }
#endif
}

// COLOR DODGE BLEND

static inline void blend_color_dodge_rgb0_8_c(const uint32_t* src1,
                                              const uint32_t* src2,
                                              uint32_t* dest) {
    uint8_t result = lut_u8_color_dodge[*src1 & 0xFF][*src2 & 0xFF];
    result |= lut_u8_color_dodge[(*src1 & 0xFF00) >> 8][(*src2 & 0xFF00) >> 8] << 8;
    result |= lut_u8_color_dodge[(*src1 & 0xFF0000) >> 16][(*src2 & 0xFF0000) >> 16]
              << 16;
    *dest = result;
}

void blend_color_dodge(const uint32_t* src1,
                       const uint32_t* src2,
                       uint32_t* dest,
                       uint32_t w,
                       uint32_t h) {
    for (size_t i = 0; i < w * h; i++) {
        blend_color_dodge_rgb0_8_c(&src1[i], &src2[i], &dest[i]);
    }
}

// COLOR BURN BLEND

static inline void blend_color_burn_rgb0_8_c(const uint32_t* src1,
                                             const uint32_t* src2,
                                             uint32_t* dest) {
    uint8_t result = lut_u8_color_burn[*src1 & 0xFF][*src2 & 0xFF];
    result |= lut_u8_color_burn[(*src1 & 0xFF00) >> 8][(*src2 & 0xFF00) >> 8] << 8;
    result |= lut_u8_color_burn[(*src1 & 0xFF0000) >> 16][(*src2 & 0xFF0000) >> 16]
              << 16;
    *dest = result;
}

void blend_color_burn(const uint32_t* src1,
                      const uint32_t* src2,
                      uint32_t* dest,
                      uint32_t w,
                      uint32_t h) {
    for (size_t i = 0; i < w * h; i++) {
        blend_color_burn_rgb0_8_c(&src1[i], &src2[i], &dest[i]);
    }
}

// LINEAR BURN BLEND

static inline void blend_linear_burn_rgb0_8_c(const uint32_t* src1,
                                              const uint32_t* src2,
                                              uint32_t* dest) {
    uint8_t result = lut_u8_linear_burn[*src1 & 0xFF][*src2 & 0xFF];
    result |= lut_u8_linear_burn[(*src1 & 0xFF00) >> 8][(*src2 & 0xFF00) >> 8] << 8;
    result |= lut_u8_linear_burn[(*src1 & 0xFF0000) >> 16][(*src2 & 0xFF0000) >> 16]
              << 16;
    *dest = result;
}

void blend_linear_burn(const uint32_t* src1,
                       const uint32_t* src2,
                       uint32_t* dest,
                       uint32_t w,
                       uint32_t h) {
    for (size_t i = 0; i < w * h; i++) {
        blend_linear_burn_rgb0_8_c(&src1[i], &src2[i], &dest[i]);
    }
}

// SUBTRACTIVE 1 BLEND (source 1 from source 2)

static inline void blend_sub_src1_from_src2_rgb0_8_c(const uint32_t* src1,
                                                     const uint32_t* src2,
                                                     uint32_t* dest) {
    int32_t channel = (*src2 & 0xff) - (*src1 & 0xff);
    uint32_t out = max(0, channel);
    channel = (*src2 & 0xff00) - (*src1 & 0xff00);
    out |= max(0, channel);
    channel = (*src2 & 0xff0000) - (*src1 & 0xff0000);
    *dest = out | max(0, channel);
}

static inline void blend_sub_src1_from_src2_rgb0_8_x86v128(const uint32_t* src1,
                                                           const uint32_t* src2,
                                                           uint32_t* dest) {
    __m128i src1_4px = _mm_loadu_si128((__m128i*)src1);
    __m128i src2_4px = _mm_loadu_si128((__m128i*)src2);
    _mm_storeu_si128((__m128i*)dest, _mm_subs_epu8(src2_4px, src1_4px));
}

void blend_sub_src1_from_src2(const uint32_t* src1,
                              const uint32_t* src2,
                              uint32_t* dest,
                              uint32_t w,
                              uint32_t h) {
#ifdef SIMD_MODE_X86_SSE
    for (size_t i = 0; i < w * h; i += 4) {
        blend_sub_src1_from_src2_rgb0_8_x86v128(&src1[i], &src2[i], &dest[i]);
    }
#else
    for (size_t i = 0; i < w * h; i++) {
        blend_sub_src1_from_src2_rgb0_8_c(&src1[i], &src2[i], &dest[i]);
    }
#endif
}

// SUBTRACTIVE 2 BLEND (source 2 from source 1)

static inline void blend_sub_src2_from_src1_rgb0_8_c(const uint32_t* src1,
                                                     const uint32_t* src2,
                                                     uint32_t* dest) {
    int32_t channel = (*src1 & 0xff) - (*src2 & 0xff);
    uint32_t out = max(0, channel);
    channel = (*src1 & 0xff00) - (*src2 & 0xff00);
    out |= max(0, channel);
    channel = (*src1 & 0xff0000) - (*src2 & 0xff0000);
    *dest = out | max(0, channel);
}

static inline void blend_sub_src2_from_src1_rgb0_8_x86v128(const uint32_t* src1,
                                                           const uint32_t* src2,
                                                           uint32_t* dest) {
    __m128i src1_4px = _mm_loadu_si128((__m128i*)src1);
    __m128i src2_4px = _mm_loadu_si128((__m128i*)src2);
    _mm_storeu_si128((__m128i*)dest, _mm_subs_epu8(src1_4px, src2_4px));
}

void blend_sub_src2_from_src1(const uint32_t* src1,
                              const uint32_t* src2,
                              uint32_t* dest,
                              uint32_t w,
                              uint32_t h) {
#ifdef SIMD_MODE_X86_SSE
    for (size_t i = 0; i < w * h; i += 4) {
        blend_sub_src2_from_src1_rgb0_8_x86v128(&src1[i], &src2[i], &dest[i]);
    }
#else
    for (size_t i = 0; i < w * h; i++) {
        blend_sub_src2_from_src1_rgb0_8_c(&src1[i], &src2[i], &dest[i]);
    }
#endif
}

// SUBTRACTIVE 1 ABS BLEND (absolute source from destination)

static inline int32_t abs_i32(int32_t x) { return x < 0 ? -x : x; }

static inline void blend_sub_src1_from_src2_abs_rgb0_8_c(const uint32_t* src1,
                                                         const uint32_t* src2,
                                                         uint32_t* dest) {
    *dest = abs_i32((int32_t)(*src2 & 0xff) - (*src1 & 0xff))
            | abs_i32((int32_t)(*src2 & 0xff00) - (*src1 & 0xff00))
            | abs_i32((int32_t)(*src2 & 0xff0000) - (*src1 & 0xff0000));
}

static inline void blend_sub_src1_from_src2_abs_rgb0_8_x86v128(const uint32_t* src1,
                                                               const uint32_t* src2,
                                                               uint32_t* dest) {
    __m128i src1_4px = _mm_loadu_si128((__m128i*)src1);
    __m128i src2_4px = _mm_loadu_si128((__m128i*)src2);
    // abs(x - y)  <=>  (x ⊢ y)  | (y ⊢ x) (where ⊢ is minus-with-saturation)
    _mm_storeu_si128((__m128i*)dest,
                     _mm_or_si128(_mm_subs_epu8(src2_4px, src1_4px),
                                  _mm_subs_epu8(src1_4px, src2_4px)));
    // alternatively: TODO[performance]: test if this is faster
    // abs(x - y)  <=>  max(x, y) - min(x, y)
    // _mm_storeu_si128((__m128i*)dest,
    //                 _mm_subs_epu8(_mm_max_epu8(src2_4px, src1_4px),
    //                               _mm_min_epu8(src2_4px, src1_4px)));
}

void blend_sub_src1_from_src2_abs(const uint32_t* src1,
                                  const uint32_t* src2,
                                  uint32_t* dest,
                                  uint32_t w,
                                  uint32_t h) {
#ifdef SIMD_MODE_X86_SSE
    for (size_t i = 0; i < w * h; i += 4) {
        blend_sub_src1_from_src2_abs_rgb0_8_x86v128(&src1[i], &src2[i], &dest[i]);
    }
#else
    for (size_t i = 0; i < w * h; i++) {
        blend_sub_src1_from_src2_abs_rgb0_8_c(&src1[i], &src2[i], &dest[i]);
    }
#endif
}

// XOR BLEND

static inline void blend_xor_rgb0_8_c(const uint32_t* src1,
                                      const uint32_t* src2,
                                      uint32_t* dest) {
    *dest = *src1 ^ *src2;
}

static inline void blend_xor_rgb0_8_x86v128(const uint32_t* src1,
                                            const uint32_t* src2,
                                            uint32_t* dest) {
    __m128i src1_4px = _mm_loadu_si128((__m128i*)src1);
    __m128i src2_4px = _mm_loadu_si128((__m128i*)src2);
    _mm_storeu_si128((__m128i*)dest, _mm_xor_si128(src1_4px, src2_4px));
}

void blend_xor(const uint32_t* src1,
               const uint32_t* src2,
               uint32_t* dest,
               uint32_t w,
               uint32_t h) {
#ifdef SIMD_MODE_X86_SSE
    for (size_t i = 0; i < w * h; i += 4) {
        blend_xor_rgb0_8_x86v128(&src1[i], &src2[i], &dest[i]);
    }
#else
    for (size_t i = 0; i < w * h; i++) {
        blend_xor_rgb0_8_c(&src1[i], &src2[i], &dest[i]);
    }
#endif
}

// EVERY OTHER PIXEL BLEND

void blend_every_other_pixel(const uint32_t* src,
                             uint32_t* dest,
                             uint32_t w,
                             uint32_t h) {
    // The top-left pixel is from src.
    for (size_t k = 0, odd = 0; k < h; k++, odd = !odd) {
        dest += odd;
        src += odd;
        for (size_t l = odd; l < w; l += 2) {
            *(dest += 2) = *(src += 2);
        }
    }
}

// EVERY OTHER LINE BLEND

void blend_every_other_line(const uint32_t* src,
                            uint32_t* dest,
                            uint32_t w,
                            uint32_t h) {
    // The top line is from src.
    for (size_t i = 0; i < w * h; i += w) {
        memcpy(&dest[i], &src[i], w * pixel_size(pixel_rgb0_8));
    }
}

#define BLEND_SRC_DEST_1PX(blend)                                                  \
    void blend##_1px(const uint32_t* src1, const uint32_t* src2, uint32_t* dest) { \
        blend##_rgb0_8_c(src1, src2, dest);                                        \
    }

#ifdef SIMD_MODE_X86_SSE
#define BLEND_SRC_DEST_FILL(blend)                                \
    void blend##_fill(uint32_t src, uint32_t* dest, uint32_t w) { \
        uint32_t src_4px[4] = {src, src, src, src};               \
        size_t i = 0;                                             \
        for (; (i + 4) <= w; i += 4) {                            \
            blend##_rgb0_8_x86v128(src_4px, &dest[i], &dest[i]);  \
        }                                                         \
        for (; i < w; i++) {                                      \
            blend##_rgb0_8_c(&src, &dest[i], &dest[i]);           \
        }                                                         \
    }
#else
#define BLEND_SRC_DEST_FILL(blend)                                \
    void blend##_fill(uint32_t src, uint32_t* dest, uint32_t w) { \
        for (size_t i = 0; i < w; i++) {                          \
            blend##_rgb0_8_c(&src, &dest[i], &dest[i]);           \
        }                                                         \
    }
#endif

BLEND_SRC_DEST_1PX(blend_add)
BLEND_SRC_DEST_FILL(blend_add)
BLEND_SRC_DEST_1PX(blend_5050)
BLEND_SRC_DEST_FILL(blend_5050)
BLEND_SRC_DEST_1PX(blend_multiply)
BLEND_SRC_DEST_FILL(blend_multiply)
BLEND_SRC_DEST_1PX(blend_screen)
BLEND_SRC_DEST_FILL(blend_screen)
BLEND_SRC_DEST_1PX(blend_color_dodge)
BLEND_SRC_DEST_1PX(blend_color_burn)
BLEND_SRC_DEST_1PX(blend_linear_burn)
BLEND_SRC_DEST_1PX(blend_maximum)
BLEND_SRC_DEST_FILL(blend_maximum)
BLEND_SRC_DEST_1PX(blend_minimum)
BLEND_SRC_DEST_FILL(blend_minimum)
BLEND_SRC_DEST_1PX(blend_sub_src1_from_src2)
BLEND_SRC_DEST_FILL(blend_sub_src1_from_src2)
BLEND_SRC_DEST_1PX(blend_sub_src2_from_src1)
BLEND_SRC_DEST_FILL(blend_sub_src2_from_src1)
BLEND_SRC_DEST_1PX(blend_sub_src1_from_src2_abs)
BLEND_SRC_DEST_FILL(blend_sub_src1_from_src2_abs)
BLEND_SRC_DEST_1PX(blend_xor)
BLEND_SRC_DEST_FILL(blend_xor)

// ADJUSTABLE BLEND

static inline void blend_adjustable_rgb0_8_c(const uint32_t* src1,
                                             const uint32_t* src2,
                                             uint32_t* dest,
                                             uint32_t param) {
    uint8_t v = param & 0xff;
    uint8_t iv = 0xff - v;
    int32_t output =
        lut_u8_multiply[*src1 & 0xFF][v] + lut_u8_multiply[*src2 & 0xFF][iv];
    output |= (lut_u8_multiply[(*src1 & 0xFF00) >> 8][v]
               + lut_u8_multiply[(*src2 & 0xFF00) >> 8][iv])
              << 8;
    output |= (lut_u8_multiply[(*src1 & 0xFF0000) >> 16][v]
               + lut_u8_multiply[(*src2 & 0xFF0000) >> 16][iv])
              << 16;
    *dest = output;
}

static inline void blend_adjustable_rgb0_8_x86v128(const uint32_t* src1,
                                                   const uint32_t* src2,
                                                   uint32_t* dest,
                                                   uint32_t param) {
    __m128i src1_4px = _mm_loadu_si128((__m128i*)src1);
    __m128i src2_4px = _mm_loadu_si128((__m128i*)src2);
    __m128i zero = _mm_setzero_si128();
    __m128i src1_lo_2px = _mm_unpacklo_epi8(src1_4px, zero);
    __m128i src1_hi_2px = _mm_unpackhi_epi8(src1_4px, zero);
    __m128i src2_lo_2px = _mm_unpacklo_epi8(src2_4px, zero);
    __m128i src2_hi_2px = _mm_unpackhi_epi8(src2_4px, zero);
    __m128i v = _mm_set1_epi16(param);
    __m128i iv = _mm_xor_si128(v, _mm_set1_epi16(0x00ff));
    __m128i mul_src1_lo = _mm_mullo_epi16(src1_lo_2px, v);
    __m128i mul_src1_hi = _mm_mullo_epi16(src1_hi_2px, v);
    __m128i mul_src2_lo = _mm_mullo_epi16(src2_lo_2px, iv);
    __m128i mul_src2_hi = _mm_mullo_epi16(src2_hi_2px, iv);
    __m128i lo = _mm_adds_epu16(mul_src1_lo, mul_src2_lo);
    __m128i hi = _mm_adds_epu16(mul_src1_hi, mul_src2_hi);
    __m128i lo_norm = _mm_srli_epi16(lo, 8);
    __m128i hi_norm = _mm_srli_epi16(hi, 8);
    __m128i packed = _mm_packus_epi16(lo_norm, hi_norm);
    _mm_storeu_si128((__m128i*)dest, packed);
}

void blend_adjustable(const uint32_t* src1,
                      const uint32_t* src2,
                      uint32_t* dest,
                      uint32_t param,
                      uint32_t w,
                      uint32_t h) {
#ifdef SIMD_MODE_X86_SSE
    for (size_t i = 0; i < w * h; i += 4) {
        blend_adjustable_rgb0_8_x86v128(&src1[i], &src2[i], &dest[i], param);
    }
#else
    for (size_t i = 0; i < w * h; i++) {
        blend_adjustable_rgb0_8_c(&src1[i], &src2[i], &dest[i], param);
    }
#endif
}

void blend_adjustable_1px(const uint32_t* src1,
                          const uint32_t* src2,
                          uint32_t* dest,
                          uint32_t param) {
    blend_adjustable_rgb0_8_c(src1, src2, dest, param);
}

void blend_adjustable_fill(uint32_t src1,
                           uint32_t* src2,
                           uint32_t* dest,
                           uint32_t param,
                           uint32_t w) {
#ifdef SIMD_MODE_X86_SSE
    uint32_t src1_4px[4] = {src1, src1, src1, src1};
    size_t i = 0;
    for (; (i + 4) <= w; i += 4) {
        blend_adjustable_rgb0_8_x86v128(src1_4px, &src2[i], &dest[i], param);
    }
    for (; i < w; i++) {
        blend_adjustable_rgb0_8_c(&src1, &src2[i], &dest[i], param);
    }
#else
    for (size_t i = 0; i < w; i++) {
        blend_adjustable_rgb0_8_c(&src1, &src2[i], &dest[i], param);
    }
#endif
}

// BUFFER BLEND

static inline void blend_buffer_rgb0_8_c(const uint32_t* src1,
                                         const uint32_t* src2,
                                         uint32_t* dest,
                                         const uint32_t* buf,
                                         bool invert) {
    // find the maximum channel value and spread it to all channels
    uint8_t v = *buf >> 16 & 0xff;
    uint8_t buf_g = *buf >> 8 & 0xff;
    v = v >= buf_g ? v : buf_g;
    uint8_t buf_b = *buf & 0xff;
    v = v >= buf_b ? v : buf_b;
    uint8_t iv = 255 - v;
    if (invert) {
        iv = v;
        v = 255 - v;
    }

    // do an adjustable blend
    uint8_t src1_r = *src1 >> 16 & 0xff;
    uint8_t src1_g = *src1 >> 8 & 0xff;
    uint8_t src1_b = *src1 & 0xff;
    uint8_t src2_r = *src2 >> 16 & 0xff;
    uint8_t src2_g = *src2 >> 8 & 0xff;
    uint8_t src2_b = *src2 & 0xff;
    *dest = (lut_u8_multiply[src1_r][v] + lut_u8_multiply[src2_r][iv]) << 16
            | (lut_u8_multiply[src1_g][v] + lut_u8_multiply[src2_g][iv]) << 8
            | (lut_u8_multiply[src1_b][v] + lut_u8_multiply[src2_b][iv]);
}

static inline void blend_buffer_rgb0_8_x86v128(const uint32_t* src1,
                                               const uint32_t* src2,
                                               uint32_t* dest,
                                               const uint32_t* buf,
                                               bool invert) {
    __m128i zero = _mm_setzero_si128();
    __m128i buf_4px = _mm_loadu_si128((__m128i*)buf);
    // argb.argb.argb.argb -> [0a0r0g0b.0a0r0g0b, 0a0r0g0b.0a0r0g0b]
    __m128i buf_hi_2px = _mm_unpackhi_epi8(buf_4px, zero);
    __m128i buf_lo_2px = _mm_unpacklo_epi8(buf_4px, zero);
    // 0a0r0g0b.0a0r0g0b -> 00____0m.0____0m (where "m" is the maximum of the
    // channels)
    buf_hi_2px = _mm_max_epu16(buf_hi_2px, _mm_srli_si128(buf_hi_2px, 2 /*bytes*/));
    buf_lo_2px = _mm_max_epu16(buf_lo_2px, _mm_srli_si128(buf_lo_2px, 2 /*bytes*/));
    buf_hi_2px = _mm_max_epu16(buf_hi_2px, _mm_srli_si128(buf_hi_2px, 4 /*bytes*/));
    buf_lo_2px = _mm_max_epu16(buf_lo_2px, _mm_srli_si128(buf_lo_2px, 4 /*bytes*/));
    // alpha 0 & 3x 16bit values from hi:0 (0x80) + lo:index0 (0x00) = mask: 0x8000
    // alpha 0 & 3x 16bit values from hi:0 (0x80) + lo:index8 (0x08) = mask: 0x8008
    static uint64_t buf_shuffle_mask_values[2] = {
        0x8080800080008000,
        0x8080800880088008,
    };
    __m128i buf_shuffle_mask = _mm_loadu_si128((__m128i*)buf_shuffle_mask_values);
    // spread the maximum back to the channels:
    // ______0m.______0m -> 000m0m0m.000m0m0m
    buf_hi_2px = _mm_shuffle_epi8(buf_hi_2px, buf_shuffle_mask);
    buf_lo_2px = _mm_shuffle_epi8(buf_lo_2px, buf_shuffle_mask);
    // invert the buffer v values for lerp, either switched ("invert") or normal
    // xor is quick unsigned invert (here in 8bit): x ^ 0xff == 255 - x
    __m128i buf_hi_inv_2px;
    __m128i buf_lo_inv_2px;
    static __m128i invert255_mask = _mm_set1_epi16(0x00ff);
    if (invert) {
        buf_hi_inv_2px = buf_hi_2px;
        buf_lo_inv_2px = buf_lo_2px;
        buf_hi_2px = _mm_xor_si128(buf_hi_2px, invert255_mask);
        buf_lo_2px = _mm_xor_si128(buf_lo_2px, invert255_mask);
    } else {
        buf_hi_inv_2px = _mm_xor_si128(buf_hi_2px, invert255_mask);
        buf_lo_inv_2px = _mm_xor_si128(buf_lo_2px, invert255_mask);
    }

    __m128i src1_4px = _mm_loadu_si128((__m128i*)src1);
    __m128i src2_4px = _mm_loadu_si128((__m128i*)src2);
    __m128i src1_hi_2px = _mm_unpackhi_epi8(src1_4px, zero);
    __m128i src1_lo_2px = _mm_unpacklo_epi8(src1_4px, zero);
    __m128i src2_hi_2px = _mm_unpackhi_epi8(src2_4px, zero);
    __m128i src2_lo_2px = _mm_unpacklo_epi8(src2_4px, zero);
    // src1 * v
    __m128i src1_hi_v = _mm_mullo_epi16(src1_hi_2px, buf_hi_2px);
    __m128i src1_lo_v = _mm_mullo_epi16(src1_lo_2px, buf_lo_2px);
    // src2 * (255 - v)
    __m128i src2_hi_v = _mm_mullo_epi16(src2_hi_2px, buf_hi_inv_2px);
    __m128i src2_lo_v = _mm_mullo_epi16(src2_lo_2px, buf_lo_inv_2px);
    // src1 * v + src2 * (255 - v)
    __m128i hi = _mm_add_epi16(src1_hi_v, src2_hi_v);
    __m128i lo = _mm_add_epi16(src1_lo_v, src2_lo_v);
    __m128i his8 = _mm_srli_epi16(hi, 8);
    __m128i los8 = _mm_srli_epi16(lo, 8);
    __m128i packed = _mm_packus_epi16(los8, his8);
    _mm_storeu_si128((__m128i*)dest, packed);
}

void blend_buffer(const uint32_t* src1,
                  const uint32_t* src2,
                  uint32_t* dest,
                  const uint32_t* buf,
                  bool invert,
                  uint32_t w,
                  uint32_t h) {
#ifdef SIMD_MODE_X86_SSE
    for (size_t i = 0; i < w * h; i += 4) {
        blend_buffer_rgb0_8_x86v128(&src1[i], &src2[i], &dest[i], &buf[i], invert);
    }
#else
    for (size_t i = 0; i < w * h; i++) {
        blend_buffer_rgb0_8_c(&src1[i], &src2[i], &dest[i], &buf[i], invert);
    }
#endif
}

void blend_buffer_1px(const uint32_t* src1,
                      const uint32_t* src2,
                      uint32_t* dest,
                      const uint32_t* buf,
                      bool invert) {
#ifdef SIMD_MODE_X86_SSE
    blend_buffer_rgb0_8_x86v128(src1, src2, dest, buf, invert);
#else
    blend_buffer_rgb0_8_c(src1, src2, dest, buf, invert);
#endif
}

static inline uint32_t blend_bilinear_2x2_rgb0_8_c(const uint32_t* src,
                                                   uint32_t w,
                                                   uint8_t lerp_x,
                                                   uint8_t lerp_y) {
    uint8_t lerp_1 = lut_u8_multiply[255 - lerp_x][255 - lerp_y];
    uint8_t lerp_2 = lut_u8_multiply[lerp_x][255 - lerp_y];
    uint8_t lerp_3 = lut_u8_multiply[255 - lerp_x][lerp_y];
    uint8_t lerp_4 = lut_u8_multiply[lerp_x][lerp_y];
    return (lut_u8_multiply[src[0] & 0xff][lerp_1]
            + lut_u8_multiply[src[1] & 0xff][lerp_2]
            + lut_u8_multiply[src[w] & 0xff][lerp_3]
            + lut_u8_multiply[src[w + 1] & 0xff][lerp_4])
           | (lut_u8_multiply[src[0] >> 8 & 0xff][lerp_1]
              + lut_u8_multiply[src[1] >> 8 & 0xff][lerp_2]
              + lut_u8_multiply[src[w] >> 8 & 0xff][lerp_3]
              + lut_u8_multiply[src[w + 1] >> 8 & 0xff][lerp_4])
                 << 8
           | (lut_u8_multiply[src[0] >> 16 & 0xff][lerp_1]
              + lut_u8_multiply[src[1] >> 16 & 0xff][lerp_2]
              + lut_u8_multiply[src[w] >> 16 & 0xff][lerp_3]
              + lut_u8_multiply[src[w + 1] >> 16 & 0xff][lerp_4])
                 << 16;
}

static inline void print_m128i(__m128i a) {
    uint32_t debug[] = {0, 0, 0, 0};
    _mm_storeu_si128((__m128i*)debug, a);
    printf(":: %08x %08x %08x %08x\n", debug[3], debug[2], debug[1], debug[0]);
}

// Some older compilers don't implement the `_mm_storeu_si32()` instrinsic. They do
// implement the `_mm_store_ss()` intrinsic which stores the same, just expects floats.
#ifndef _mm_storeu_si32
#define _mm_storeu_si32(dest, a) \
    _mm_store_ss(reinterpret_cast<float*>(dest), _mm_castsi128_ps(a));
#endif

static inline uint32_t blend_bilinear_2x2_rgb0_8_x86v128(const uint32_t* src,
                                                         uint32_t w,
                                                         uint8_t lerp_x,
                                                         uint8_t lerp_y) {
    // Algorithm, per channel:
    //   dest = src[0](1-x)(1-y) + src[1](1-x)y + src[w]x(1-y) + src[w+1]xy
    // assuming src, lerp_x and lerp_y are ranged 0-1. In reality they are ranged 0-255,
    // and every intermediate multiplication result is normalized through a division by
    // 256, i.e. a right-shift by 8.

    // Spread & invert the lerp values in specific patterns for x and y:
    //    src         +0                +1
    //         _A___R___G___B__  _A___R___G___B__
    //    +0  | 0  1-x 1-x 1-x    0   x   x   x   ─┬─▶ lerp_2px_x
    //    +w  | 0  1-x 1-x 1-x    0   x   x   x   ─┘
    //
    //         _A___R___G___B__  _A___R___G___B__
    //    +0  | 0  1-y 1-y 1-y    0  1-y 1-y 1-y  ───▶ lerp_2px_y0
    //    +w  | 0   y   y   y     0   y   y   y   ───▶ lerp_2px_y1
    static uint64_t inv_values[] = {0x000000ff00ff00ff, 0};
    static __m128i inv_x = _mm_loadu_si128((__m128i*)inv_values);
    static __m128i inv_y0 = _mm_set1_epi64x(inv_values[0]);
    static __m128i zero = _mm_setzero_si128();
    __m128i lerp_2px_x = _mm_xor_si128(_mm_set1_epi16(lerp_x), inv_x);
    __m128i lerp_2px_y1 = _mm_set1_epi16(lerp_y);
    __m128i lerp_2px_y0 = _mm_xor_si128(lerp_2px_y1, inv_y0);

    __m128i src_2corners_y0 = _mm_loadl_epi64((__m128i*)src);
    __m128i src_2corners_y1 = _mm_loadl_epi64((__m128i*)(&src[w]));
    // Unpack src into the _high_ byte. This allows us to skip the intermediate
    // normalize shift. Normally one would multiply-and-normalize two times. But by
    // putting the second multiplication's operand into the high bytes it has the same
    // scale as the result of the first multiplication and we can multiply a second time
    // right away. With the help of PMULHUW (which returns the high 16 bits of the 32bit
    // intermediate) instead of PMULLW we get a uint16 result for free and only need to
    // shift 8 bits once after addition (because the lerp values cancel each other out
    // and the addtion cannot overflow/saturate) for a uint8-ranged result.
    src_2corners_y0 = _mm_unpacklo_epi8(zero, src_2corners_y0);
    src_2corners_y1 = _mm_unpacklo_epi8(zero, src_2corners_y1);
    src_2corners_y0 =
        _mm_mulhi_epu16(src_2corners_y0, _mm_mullo_epi16(lerp_2px_x, lerp_2px_y0));
    src_2corners_y1 =
        _mm_mulhi_epu16(src_2corners_y1, _mm_mullo_epi16(lerp_2px_x, lerp_2px_y1));
    __m128i result = _mm_add_epi16(src_2corners_y0, src_2corners_y1);
    result = _mm_srli_epi16(result, 8 /*bits*/);
    result = _mm_add_epi16(result, _mm_srli_si128(result, 8 /*bytes*/));
    result = _mm_packus_epi16(result, zero);
    uint32_t iresult;
    _mm_storeu_si32(&iresult, result);
    return iresult;
}

uint32_t blend_bilinear_2x2(const uint32_t* src,
                            uint32_t w,
                            uint8_t lerp_x,
                            uint8_t lerp_y) {
#ifdef SIMD_MODE_X86_SSE
    return blend_bilinear_2x2_rgb0_8_x86v128(src, w, lerp_x, lerp_y);
#else
    return blend_bilinear_2x2_rgb0_8_c(src, w, lerp_x, lerp_y);
#endif
}
