#include <stdint.h>
#include <stdio.h>

void make_blend_LUTs();
extern uint8_t lut_u8_multiply[256][256];

// The following SIMD modes may be targeted by a build variable definition. If a SIMD
// implementation is not available, the C fallback (SIMD_MODE_NONE) version will be
// used.
//
//   SIMD_MODE_NONE
//   SIMD_MODE_X86_SSE

#define ARGS_1SRC_DEST_WH const uint32_t *src, uint32_t *dest, uint32_t w, uint32_t h
void blend_replace(ARGS_1SRC_DEST_WH);
#define blend_replace_1px(src, dest) (*(dest) = *(src))
void blend_replace_fill(uint32_t src, uint32_t* dest, uint32_t w);
void blend_every_other_pixel(ARGS_1SRC_DEST_WH);
void blend_every_other_line(ARGS_1SRC_DEST_WH);

#define ARGS_2SRC_DEST_WH  ARGS_2SRC_DEST, uint32_t w, uint32_t h
#define ARGS_2SRC_DEST     const uint32_t *src1, const uint32_t *src2, uint32_t *dest
#define ARGS_SRCVAL_DEST_W uint32_t src, uint32_t *dest, uint32_t w
void blend_add(ARGS_2SRC_DEST_WH);
void blend_add_1px(ARGS_2SRC_DEST);
void blend_add_fill(ARGS_SRCVAL_DEST_W);
void blend_5050(ARGS_2SRC_DEST_WH);
void blend_5050_1px(ARGS_2SRC_DEST);
void blend_5050_fill(ARGS_SRCVAL_DEST_W);
void blend_multiply(ARGS_2SRC_DEST_WH);
void blend_multiply_1px(ARGS_2SRC_DEST);
void blend_multiply_fill(ARGS_SRCVAL_DEST_W);
void blend_screen(ARGS_2SRC_DEST_WH);
void blend_screen_1px(ARGS_2SRC_DEST);
void blend_screen_fill(ARGS_SRCVAL_DEST_W);
void blend_color_dodge(ARGS_2SRC_DEST_WH);
void blend_color_dodge_1px(ARGS_2SRC_DEST);
void blend_color_dodge_fill(ARGS_SRCVAL_DEST_W);
void blend_color_burn(ARGS_2SRC_DEST_WH);
void blend_color_burn_1px(ARGS_2SRC_DEST);
void blend_color_burn_fill(ARGS_SRCVAL_DEST_W);
void blend_linear_burn(ARGS_2SRC_DEST_WH);
void blend_linear_burn_1px(ARGS_2SRC_DEST);
void blend_linear_burn_fill(ARGS_SRCVAL_DEST_W);
void blend_maximum(ARGS_2SRC_DEST_WH);
void blend_maximum_1px(ARGS_2SRC_DEST);
void blend_maximum_fill(ARGS_SRCVAL_DEST_W);
void blend_minimum(ARGS_2SRC_DEST_WH);
void blend_minimum_1px(ARGS_2SRC_DEST);
void blend_minimum_fill(ARGS_SRCVAL_DEST_W);
void blend_sub_src1_from_src2(ARGS_2SRC_DEST_WH);
void blend_sub_src1_from_src2_1px(ARGS_2SRC_DEST);
void blend_sub_src1_from_src2_fill(ARGS_SRCVAL_DEST_W);
void blend_sub_src2_from_src1(ARGS_2SRC_DEST_WH);
void blend_sub_src2_from_src1_1px(ARGS_2SRC_DEST);
void blend_sub_src2_from_src1_fill(ARGS_SRCVAL_DEST_W);
void blend_sub_src1_from_src2_abs(ARGS_2SRC_DEST_WH);
void blend_sub_src1_from_src2_abs_1px(ARGS_2SRC_DEST);
void blend_sub_src1_from_src2_abs_fill(ARGS_SRCVAL_DEST_W);
void blend_xor(ARGS_2SRC_DEST_WH);
void blend_xor_1px(ARGS_2SRC_DEST);
void blend_xor_fill(ARGS_SRCVAL_DEST_W);

#define ARGS_2SRC_DEST_PARAM \
    const uint32_t *src1, const uint32_t *src2, uint32_t *dest, uint32_t param
#define ARGS_2SRC_DEST_PARAM_WH ARGS_2SRC_DEST_PARAM, uint32_t w, uint32_t h
#define ARGS_SRCVAL_SRC2_DEST_PARAM_W \
    uint32_t src1, uint32_t *src2, uint32_t *dest, uint32_t param, uint32_t w
void blend_adjustable(ARGS_2SRC_DEST_PARAM_WH);
void blend_adjustable_1px(ARGS_2SRC_DEST_PARAM);
void blend_adjustable_fill(ARGS_SRCVAL_SRC2_DEST_PARAM_W);

#define ARGS_2SRC_DEST_BUF_INVERT                                                    \
    const uint32_t *src1, const uint32_t *src2, uint32_t *dest, const uint32_t *buf, \
        bool invert
#define ARGS_2SRC_DEST_BUF_INVERT_WH ARGS_2SRC_DEST_BUF_INVERT, uint32_t w, uint32_t h
void blend_buffer_1px(ARGS_2SRC_DEST_BUF_INVERT);
void blend_buffer(ARGS_2SRC_DEST_BUF_INVERT_WH);

extern int32_t g_line_blend_mode;
inline void blend_default_1px(ARGS_2SRC_DEST) {
    switch (g_line_blend_mode & 0xff) {
        default: blend_replace_1px(src1, dest); break;
        case 1: blend_add_1px(src1, src2, dest); break;
        case 2: blend_maximum_1px(src1, src2, dest); break;
        case 3: blend_5050_1px(src1, src2, dest); break;
        case 4: blend_sub_src1_from_src2_1px(src1, src2, dest); break;
        case 5: blend_sub_src2_from_src1_1px(src1, src2, dest); break;
        case 6: blend_multiply_1px(src1, src2, dest); break;
        case 7:
            blend_adjustable_1px(src1, src2, dest, g_line_blend_mode >> 8 & 0xff);
            break;
        case 8: blend_xor_1px(src1, src2, dest); break;
        case 9: blend_minimum_1px(src1, src2, dest); break;
    }
}
inline void blend_default_fill(ARGS_SRCVAL_DEST_W) {
    switch (g_line_blend_mode & 0xff) {
        default: blend_replace_fill(src, dest, w); break;
        case 1: blend_add_fill(src, dest, w); break;
        case 2: blend_maximum_fill(src, dest, w); break;
        case 3: blend_5050_fill(src, dest, w); break;
        case 4: blend_sub_src1_from_src2_fill(src, dest, w); break;
        case 5: blend_sub_src2_from_src1_fill(src, dest, w); break;
        case 6: blend_multiply_fill(src, dest, w); break;
        case 7:
            blend_adjustable_fill(src, dest, dest, g_line_blend_mode >> 8 & 0xff, w);
            break;
        case 8: blend_xor_fill(src, dest, w); break;
        case 9: blend_minimum_fill(src, dest, w); break;
    }
}

uint32_t blend_bilinear_2x2(const uint32_t* src,
                            uint32_t w,
                            uint8_t lerp_x,
                            uint8_t lerp_y);
