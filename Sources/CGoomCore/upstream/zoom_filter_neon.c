/*
 * zoom_filter_neon.c
 *
 * ARM NEON (armv8) version of the goom zoom filter, same role as
 * zoom_filter_xmmx (x86 MMX) and ppc_zoom_G4 (AltiVec).
 *
 * Reference semantics: c_zoom() in filters.c. One deliberate divergence
 * (same spirit as the MMX STRICT_COMPAT trade-offs):
 *  - alpha channel is blended (MMX-style) instead of left untouched.
 * The blend arithmetic itself is bit-exact: the "if (sum > 5) sum -= 5" step
 * is a saturating vqsub (it differs from C only for sum <= 5, where both
 * shift to 0) and the >> 8 narrow is a truncating vshrn, i.e. the cast C
 * does.
 */

#if defined(__aarch64__)

#include <arm_neon.h>
#include <string.h>
#include <math.h>

#include "goom_graphic.h"
#include "goom_plugin_info.h"

#define BUFFPOINTNB 16

/* faire : a % sqrtperte <=> a & pertemask */
#define PERTEMASK 0xf
/* faire : a / sqrtperte <=> a >> PERTEDEC */
#define PERTEDEC 4

/* scalar per-lane beta for the tail loop (same math as the vector path) */
static float wipeBetaLane (int mode, const ZoomBlend *blend, float x, float y,
                           float halfDiagonal, int idx, int seamCount,
                           const float *seamU, const float *seamV)
{
    float d, W, j, cp, ring;

    if (blend->progress <= 0.0f) return 0.0f;
    if (blend->progress >= 1.0f) return 1.0f;

    /* per-pixel wobble: j = 1 + wobble*(l*2/255 - 1), cp = progress*j
     * (cp may exceed 1: intended self-completion; only the global
     * overrides above are exact endpoints). */
    if (blend->luma != NULL && blend->wobble > 0.0f) {
        float l = (float) blend->luma[idx];          /* idx = output pixel index, row-major */
        /* fmaf: single rounding, bit-identical to the NEON vfmaq forms */
        j = fmaf (blend->wobble, fmaf (l, 2.0f / 255.0f, -1.0f), 1.0f);
    } else {
        j = 1.0f;
    }
    cp = blend->progress * j;
    W = cp * halfDiagonal;
    ring = blend->ring;
    if (mode == 2) {
        float s = 1e30f;
        int m;
        for (m = 0; m < seamCount; m++) {
            float sm = (x - blend->cx) * seamU[m] + (y - blend->cy) * seamV[m];
            if (sm < 0.0f) sm = -sm;
            if (sm < s) s = sm;
        }
        if (ring <= 0.0f)
            return (s <= W) ? 1.0f : 0.0f;
        d = s;
    } else {
        float dx = x - blend->cx;
        float dy = y - blend->cy;
        float d2 = fmaf (dy, dy, dx * dx);   /* matches the NEON fma(dfy,dfy,dfx*dfx) */
        if (ring <= 0.0f)
            return (d2 <= W * W) ? 1.0f : 0.0f;
        d = sqrtf (d2);
    }
    {
        float b = (W + ring * 0.5f - d) / ring;
        if (b < 0.0f) b = 0.0f;
        else if (b > 1.0f) b = 1.0f;
        return b;
    }
}

void zoom_filter_neon (int prevX, int prevY,
                       Pixel *__restrict expix1, Pixel *__restrict expix2,
                       int *__restrict lbruS, int *__restrict lbruD, int buffratio,
                       int precalCoef[16][16], const ZoomBlend *blend)
{
    const unsigned int ax = (prevX - 1) << PERTEDEC;
    const unsigned int ay = (prevY - 1) << PERTEDEC;
    const int bufsize = prevX * prevY;

    int loop = 0;

    const int32x4_t vratio = vdupq_n_s32 (buffratio);
    /* geometric wipe blend: per-lane beta (0..65535) replaces buffratio.
     * NULL blend = LINEAR, bit-identical to the historical path. */
    const int wipeMode = blend ? blend->mode : 0;
    const float wipeHalfDiag = wipeMode
        ? 0.5f * sqrtf ((float) (prevX * prevX + prevY * prevY)) : 0.0f;
    const float wipeCx = blend ? blend->cx : 0.0f;
    const float wipeCy = blend ? blend->cy : 0.0f;
    const float wipeRing = (blend && wipeMode) ? blend->ring : 0.0f;
    const int wipeHard = (blend && wipeMode && blend->ring <= 0.0f);
    /* per-pixel wobble: j = 1 + wobble*(luma*2/255 - 1) per lane. The
     * caller loads the 4 lane bytes of blend->luma[loop+lane] into
     * vlumaBytes before ZG_BETA; a NULL luma or wobble <= 0 keeps
     * wipeWobbleF at 0, then j = 1 and cp = progress per lane. */
    const float wipeWobbleF = (blend && blend->luma != NULL && blend->wobble > 0.0f)
        ? blend->wobble : 0.0f;
    const float32x4_t vhalfring = vdupq_n_f32 (wipeRing * 0.5f);
    /* WIPE_SEAMS: rotated seam normals (N reaches 25 with the auto fold set) */
    float seamU[32], seamV[32];
    int seamCount = 0;
    if (wipeMode == 2 && blend && blend->foldCount > 0) {
        int m;
        float a = 0.0f;
        float da = (float) M_PI / (float) blend->foldCount;
        for (m = 0; m < blend->foldCount && m < 32; m++) {
            seamU[m] = blend->n1x * cosf (a) - blend->n1y * sinf (a);
            seamV[m] = blend->n1x * sinf (a) + blend->n1y * cosf (a);
            a += da;
        }
        seamCount = (blend->foldCount < 32) ? blend->foldCount : 32;
    }
    const float32x4_t vcx = vdupq_n_f32 (wipeCx);
    const float32x4_t vcy = vdupq_n_f32 (wipeCy);
    const float32x4_t vring = vdupq_n_f32 (wipeRing);
    const float32x4_t vhalf = vdupq_n_f32 (0.5f);
    const int32x4_t v65535 = vdupq_n_s32 (65535);
    const int32x4_t vzeroi = vdupq_n_s32 (0);
    const float32x4_t vzerof = vdupq_n_f32 (0.0f);
    const float32x4_t vonef = vdupq_n_f32 (1.0f);
    const uint32x4_t vax = vdupq_n_u32 (ax);
    const uint32x4_t vay = vdupq_n_u32 (ay);
    const uint32x4_t vprevX = vdupq_n_u32 ((unsigned int) prevX);
    const uint32x4_t vmask15 = vdupq_n_u32 (PERTEMASK);
    const uint32x4_t vzero256 = vdupq_n_u32 (256);

    const uint16x8_t vfive = vdupq_n_u16 (5);

    /* precalCoef viewed flat: idx = ((px&15)<<4)|(py&15) indexes it as
     * precalCoef[px&15][py&15] (row stride 16, 4 bytes each). */
    const int *precal = (const int *) precalCoef;

    /* Pre-expand the coefficient table into the exact byte layout the blend
     * needs, [c1,c1,c1,c1, c2,c2,c2,c2, c3,c3,c3,c3, c4,c4,c4,c4] per
     * coefficient (what the old vdup+vqtbl1q produced). spreadtab[idx+256]
     * is all-zero so a clipped pixel (clip&256 folded into the index) loads a
     * zero spread directly — no scalar masking, no dup, no tbl. This is the
     * one-per-frame setup; measured ~0.4% of frame cost. */
    uint8_t spreadtab[512][16];
    {
        unsigned i, j;
        memset (spreadtab, 0, sizeof spreadtab);
        for (i = 0; i < 256; ++i) {
            uint32_t c = (uint32_t) precal[i];
            uint8_t c1 = (uint8_t) c, c2 = (uint8_t) (c >> 8),
                    c3 = (uint8_t) (c >> 16), c4 = (uint8_t) (c >> 24);
            for (j = 0; j < 4; ++j) spreadtab[i][j] = c1;
            for (j = 0; j < 4; ++j) spreadtab[i][4 + j] = c2;
            for (j = 0; j < 4; ++j) spreadtab[i][8 + j] = c3;
            for (j = 0; j < 4; ++j) spreadtab[i][12 + j] = c4;
        }
    }

    expix1[0].val = expix1[prevX-1].val = expix1[prevX*prevY-1].val = expix1[prevX*prevY-prevX].val = 0;

/* per-lane wipe beta: 16.16 fixed beta_fix in [0..65535] replacing
 * buffratio. Per-pixel wobble: j = 1 + wobble*(luma*2/255 - 1) per lane,
 * cp = progress*j, W = cp*halfDiagonal (vlumaBytes = the 4 lane bytes,
 * loaded by the caller from blend->luma[loop+lane]; wipeWobbleF == 0
 * when luma is NULL or wobble <= 0, then j = 1 and cp = progress).
 * Hard step: exact 0 / 65535 select, no sqrt (compare the SQUARED
 * distance). Ring: beta = (W + ring/2 - d) / ring. Endpoint overrides
 * (c <= 0 -> 0, c >= 1 -> 1) produce the exact 0 / 65535 lanes too; the
 * position math below routes a full select DIRECTLY to brutS / brutD
 * (never through the 65535 lerp residue). */
#define ZG_BETA(XF, YF, OUT)                                                                       \
    {                                                                                              \
        if (blend->progress <= 0.0f) {                                                             \
            OUT = vzeroi;                                                                          \
        } else if (blend->progress >= 1.0f) {                                                      \
            OUT = v65535;                                                                          \
        } else {                                                                                   \
        float32x4_t cp, Wlane;                                                                     \
        {                                                                                          \
            /* wobble: j = 1 + wobble*(l*2/255 - 1) per lane */                                    \
            float32x4_t vluma = vcvtq_f32_s32 (vreinterpretq_s32_u32 (vmovl_u16 (vlumaBytes)));    \
            float32x4_t n = vfmaq_n_f32 (vnegq_f32 (vonef), vluma, 2.0f / 255.0f);                 \
            float32x4_t jv = vfmaq_n_f32 (vonef, n, wipeWobbleF);                                  \
            cp = vmulq_n_f32 (jv, blend->progress);                                                \
            Wlane = vmulq_n_f32 (cp, wipeHalfDiag);                                                \
        }                                                                                          \
        float32x4_t dfx = vsubq_f32 (XF, vcx);                                                     \
        float32x4_t dfy = vsubq_f32 (YF, vcy);                                                     \
        if (wipeMode == 1) {                                                                       \
            float32x4_t d2 = vfmaq_f32 (vmulq_f32 (dfx, dfx), dfy, dfy);                           \
            /* hard: no sqrt, compare d2 against Wlane^2 */                                       \
            if (wipeHard) {                                                                       \
                uint32x4_t inside = vcleq_f32 (d2, vmulq_f32 (Wlane, Wlane));                      \
                OUT = (int32x4_t) vbslq_u32 (inside, (uint32x4_t) v65535, (uint32x4_t) vzeroi);    \
            } else {                                                                              \
                float32x4_t d = vsqrtq_f32 (d2);                                                  \
                /* b = (W + ring/2 - d) / ring, same op order as the C form */                   \
                float32x4_t b = vdivq_f32 (vsubq_f32 (vaddq_f32 (Wlane, vhalfring), d), vring);    \
                b = vminnmq_f32 (vmaxnmq_f32 (b, vzerof), vonef);                                 \
                OUT = vcvtmq_s32_f32 (vaddq_f32 (vmulq_n_f32 (b, 65535.0f), vhalf));               \
            }                                                                                     \
        } else {                                                                                  \
            /* WIPE_SEAMS: min |dot| over the N seam normals */                                   \
            float32x4_t smin = vdupq_n_f32 (1e30f);                                               \
            int m;                                                                                \
            for (m = 0; m < seamCount; m++) {                                                     \
                float32x4_t sm = vaddq_f32 (vmulq_n_f32 (dfx, seamU[m]),                          \
                                            vmulq_n_f32 (dfy, seamV[m]));                         \
                sm = vabsq_f32 (sm);                                                              \
                smin = vminnmq_f32 (smin, sm);                                                    \
            }                                                                                     \
            if (wipeHard) {                                                                       \
                uint32x4_t inside = vcleq_f32 (smin, Wlane);                                       \
                OUT = (int32x4_t) vbslq_u32 (inside, (uint32x4_t) v65535, (uint32x4_t) vzeroi);    \
            } else {                                                                              \
                float32x4_t b = vdivq_f32 (vsubq_f32 (vaddq_f32 (Wlane, vhalfring), smin), vring); \
                b = vminnmq_f32 (vmaxnmq_f32 (b, vzerof), vonef);                                 \
                OUT = vcvtmq_s32_f32 (vaddq_f32 (vmulq_n_f32 (b, 65535.0f), vhalf));               \
            }                                                                                     \
        }                                                                                         \
        }                                                                                         \
    }

    /* 8 pixels/iteration: doubles in-flight gather MLP (16 expix1 gathers +
     * 8 coefficient loads overlap ~14-cycle L2 latency) and amortizes the
     * vector prologue over twice the work. Two independent 4px halves let
     * the compiler overlap one half's source gathers with the other's math. */
    for (; loop + 8 <= bufsize; loop += 8) {
        int32x4x2_t s0, d0, s1, d1;
        int32x4_t px0, py0, px1, py1;
        uint32x4_t clip0, clip1, vpos0, vpos1, vidx0, vidx1, vtotal0, vtotal1;
        int pos[8], vt[8];
        int b;

        s0 = vld2q_s32 (lbruS + 2 * loop);
        s1 = vld2q_s32 (lbruS + 2 * loop + 8);
        d0 = vld2q_s32 (lbruD + 2 * loop);
        d1 = vld2q_s32 (lbruD + 2 * loop + 8);

        if (wipeMode) {
            /* output pixel coords of the 8 lanes, exact for any prevX: the
             * group can cross a row boundary, so recompute x = i % prevX,
             * y = i / prevX per lane. */
            float fxv[8], fyv[8];
            uint16x4_t vlumaBytes, vlumaHi;
            int lane;
            int32x4_t br0, br1;
            float32x4_t fx0, fy0, fx1, fy1;
            for (lane = 0; lane < 8; ++lane) {
                int i = loop + lane;
                fxv[lane] = (float) (i % prevX);
                fyv[lane] = (float) (i / prevX);
            }
            fx0 = vld1q_f32 (fxv);
            fy0 = vld1q_f32 (fyv);
            fx1 = vld1q_f32 (fxv + 4);
            fy1 = vld1q_f32 (fyv + 4);
            if (blend->luma) {
                vlumaBytes = vget_low_u16 (vmovl_u8 (vld1_u8 (blend->luma + loop)));
                vlumaHi = vget_low_u16 (vmovl_u8 (vld1_u8 (blend->luma + loop + 4)));
            } else {
                vlumaBytes = vdup_n_u16 (0);
                vlumaHi = vdup_n_u16 (0);
            }
            ZG_BETA (fx0, fy0, br0);
            /* second half reads luma bytes loop+4..loop+7 */
            vlumaBytes = vlumaHi;
            ZG_BETA (fx1, fy1, br1);
            /* exact endpoints: full select reads brutS/brutD directly */
            {
                uint32x4_t all0 = vceqq_s32 (br0, v65535);
                uint32x4_t none0 = vceqq_s32 (br0, vzeroi);
                uint32x4_t all1 = vceqq_s32 (br1, v65535);
                uint32x4_t none1 = vceqq_s32 (br1, vzeroi);
                int32x4_t lerp0 = vaddq_s32 (s0.val[0], vshrq_n_s32 (vmulq_s32 (vsubq_s32 (d0.val[0], s0.val[0]), br0), BUFFPOINTNB));
                int32x4_t lerp1 = vaddq_s32 (s0.val[1], vshrq_n_s32 (vmulq_s32 (vsubq_s32 (d0.val[1], s0.val[1]), br0), BUFFPOINTNB));
                int32x4_t lerp2 = vaddq_s32 (s1.val[0], vshrq_n_s32 (vmulq_s32 (vsubq_s32 (d1.val[0], s1.val[0]), br1), BUFFPOINTNB));
                int32x4_t lerp3 = vaddq_s32 (s1.val[1], vshrq_n_s32 (vmulq_s32 (vsubq_s32 (d1.val[1], s1.val[1]), br1), BUFFPOINTNB));
                px0 = (int32x4_t) vbslq_u32 (all0, (uint32x4_t) d0.val[0], (uint32x4_t) vbslq_u32 (none0, (uint32x4_t) s0.val[0], (uint32x4_t) lerp0));
                py0 = (int32x4_t) vbslq_u32 (all0, (uint32x4_t) d0.val[1], (uint32x4_t) vbslq_u32 (none0, (uint32x4_t) s0.val[1], (uint32x4_t) lerp1));
                px1 = (int32x4_t) vbslq_u32 (all1, (uint32x4_t) d1.val[0], (uint32x4_t) vbslq_u32 (none1, (uint32x4_t) s1.val[0], (uint32x4_t) lerp2));
                py1 = (int32x4_t) vbslq_u32 (all1, (uint32x4_t) d1.val[1], (uint32x4_t) vbslq_u32 (none1, (uint32x4_t) s1.val[1], (uint32x4_t) lerp3));
            }
        } else {
        px0 = vaddq_s32 (s0.val[0], vshrq_n_s32 (vmulq_s32 (vsubq_s32 (d0.val[0], s0.val[0]), vratio), BUFFPOINTNB));
        py0 = vaddq_s32 (s0.val[1], vshrq_n_s32 (vmulq_s32 (vsubq_s32 (d0.val[1], s0.val[1]), vratio), BUFFPOINTNB));
        px1 = vaddq_s32 (s1.val[0], vshrq_n_s32 (vmulq_s32 (vsubq_s32 (d1.val[0], s1.val[0]), vratio), BUFFPOINTNB));
        py1 = vaddq_s32 (s1.val[1], vshrq_n_s32 (vmulq_s32 (vsubq_s32 (d1.val[1], s1.val[1]), vratio), BUFFPOINTNB));
        }

        clip0 = vorrq_u32 (vcgeq_u32 ((uint32x4_t) px0, vax), vcgeq_u32 ((uint32x4_t) py0, vay));
        clip1 = vorrq_u32 (vcgeq_u32 ((uint32x4_t) px1, vax), vcgeq_u32 ((uint32x4_t) py1, vay));

        vpos0 = vandq_u32 (vaddq_u32 (vshrq_n_u32 ((uint32x4_t) px0, PERTEDEC),
                                      vmulq_u32 (vshrq_n_u32 ((uint32x4_t) py0, PERTEDEC), vprevX)),
                           vmvnq_u32 (clip0));
        vpos1 = vandq_u32 (vaddq_u32 (vshrq_n_u32 ((uint32x4_t) px1, PERTEDEC),
                                      vmulq_u32 (vshrq_n_u32 ((uint32x4_t) py1, PERTEDEC), vprevX)),
                           vmvnq_u32 (clip1));
        /* flat precalCoef index, always in [0,255]: vsli drops (px&15) in
         * above the low nibble of py, i.e. ((px&15)<<4)|(py&15) in one op.
         * vtotal = clip ? 256 : idx selects the all-zero spreadtab half for
         * clipped lanes, so no separate coeff masking is needed. */
        vidx0 = vsliq_n_u32 ((uint32x4_t) py0, vandq_u32 ((uint32x4_t) px0, vmask15), 4);
        vidx1 = vsliq_n_u32 ((uint32x4_t) py1, vandq_u32 ((uint32x4_t) px1, vmask15), 4);
        vtotal0 = vbslq_u32 (clip0, vzero256, vidx0);
        vtotal1 = vbslq_u32 (clip1, vzero256, vidx1);

        /* extract positions + spreadtab indices (unrolled constants). */
#define ZG2(n)                                                                                                     \
        {                                                                                                          \
            pos[n] = (int) vgetq_lane_u32 (n < 4 ? vpos0 : vpos1, n & 3);                                         \
            vt[n]  = (int) vgetq_lane_u32 (n < 4 ? vtotal0 : vtotal1, n & 3);                                     \
        }
        ZG2(0) ZG2(1) ZG2(2) ZG2(3) ZG2(4) ZG2(5) ZG2(6) ZG2(7)
#undef ZG2

        /* blend: two independent 4px groups, one 16-byte store each. */
        {
            uint8x16_t vP[4], vC[4];
            uint16x8_t a[4], acc_lo, acc_hi;
            int base, half;
            for (half = 0; half < 2; ++half) {
                base = half * 4;
                for (b = 0; b < 4; ++b) {
                    vP[b] = vcombine_u8 (vld1_u8 ((const uint8_t *) (expix1 + pos[base + b])),
                                         vld1_u8 ((const uint8_t *) (expix1 + pos[base + b] + prevX)));
                    vC[b] = vld1q_u8 ((const uint8_t *) spreadtab[vt[base + b]]);
                }
                for (b = 0; b < 4; ++b) {
                    a[b] = vmull_u8 (vget_low_u8 (vP[b]), vget_low_u8 (vC[b]));
                    a[b] = vmlal_high_u8 (a[b], vP[b], vC[b]);
                }
                acc_lo = vcombine_u16 (vadd_u16 (vget_low_u16 (a[0]), vget_high_u16 (a[0])),
                                       vadd_u16 (vget_low_u16 (a[1]), vget_high_u16 (a[1])));
                acc_hi = vcombine_u16 (vadd_u16 (vget_low_u16 (a[2]), vget_high_u16 (a[2])),
                                       vadd_u16 (vget_low_u16 (a[3]), vget_high_u16 (a[3])));
                /* if (sum > 5) sum -= 5; then sum >>= 8, narrowed to u8.
                 * vqsub saturates at 0, differing from C only for sum <= 5,
                 * where both shift to 0; vshrn is the truncating narrow C's
                 * cast performs. */
                vst1q_u8 ((uint8_t *) (expix2 + loop + base),
                          vshrn_high_n_u16 (vshrn_n_u16 (vqsubq_u16 (acc_lo, vfive), 8),
                                            vqsubq_u16 (acc_hi, vfive), 8));
            }
        }
    }

    for (; loop + 4 <= bufsize; loop += 4) {
        int32x4x2_t s, d;
        int32x4_t px, py;
        uint32x4_t clip, vpos, vidx, vtotal;
        int pos[4], vt[4];
        int k;

        /* coordinate interpolation: px = Sx + ((Dx-Sx)*ratio >> 16) */
        s = vld2q_s32 (lbruS + 2 * loop);
        d = vld2q_s32 (lbruD + 2 * loop);

        if (wipeMode) {
            float fxv[4], fyv[4];
            uint16x4_t vlumaBytes;
            int lane;
            int32x4_t br;
            float32x4_t fx, fy;
            for (lane = 0; lane < 4; ++lane) {
                int i = loop + lane;
                fxv[lane] = (float) (i % prevX);
                fyv[lane] = (float) (i / prevX);
            }
            fx = vld1q_f32 (fxv);
            fy = vld1q_f32 (fyv);
            vlumaBytes = blend->luma
                ? vget_low_u16 (vmovl_u8 (vld1_u8 (blend->luma + loop)))
                : vdup_n_u16 (0);
            ZG_BETA (fx, fy, br);
            /* exact endpoints: full select reads brutS/brutD directly */
            {
                uint32x4_t all = vceqq_s32 (br, v65535);
                uint32x4_t none = vceqq_s32 (br, vzeroi);
                int32x4_t lerp0 = vaddq_s32 (s.val[0], vshrq_n_s32 (vmulq_s32 (vsubq_s32 (d.val[0], s.val[0]), br), BUFFPOINTNB));
                int32x4_t lerp1 = vaddq_s32 (s.val[1], vshrq_n_s32 (vmulq_s32 (vsubq_s32 (d.val[1], s.val[1]), br), BUFFPOINTNB));
                px = (int32x4_t) vbslq_u32 (all, (uint32x4_t) d.val[0], (uint32x4_t) vbslq_u32 (none, (uint32x4_t) s.val[0], (uint32x4_t) lerp0));
                py = (int32x4_t) vbslq_u32 (all, (uint32x4_t) d.val[1], (uint32x4_t) vbslq_u32 (none, (uint32x4_t) s.val[1], (uint32x4_t) lerp1));
            }
        } else {
        px = vaddq_s32 (s.val[0], vshrq_n_s32 (vmulq_s32 (vsubq_s32 (d.val[0], s.val[0]), vratio), BUFFPOINTNB));
        py = vaddq_s32 (s.val[1], vshrq_n_s32 (vmulq_s32 (vsubq_s32 (d.val[1], s.val[1]), vratio), BUFFPOINTNB));
        }

        /* clip: unsigned compare, so negatives count as out of range;
         * either axis out => whole pixel clipped (stricter than MMX).
         * clip lanes are 0 (keep) or 0xFFFFFFFF (discard). */
        clip = vorrq_u32 (vcgeq_u32 ((uint32x4_t) px, vax),
                          vcgeq_u32 ((uint32x4_t) py, vay));

        /* pos = (px>>4 + prevX*(py>>4)) & ~clip. Masking the sum once is
         * bit-identical to masking px/py then shifting: for unclipped
         * (non-negative) lanes the shift+mask commute; clipped lanes give
         * pos 0 either way. */
        vpos = vandq_u32 (vaddq_u32 (vshrq_n_u32 ((uint32x4_t) px, PERTEDEC),
                                     vmulq_u32 (vshrq_n_u32 ((uint32x4_t) py, PERTEDEC), vprevX)),
                          vmvnq_u32 (clip));

        /* flat precalCoef index in [0,255] (vsli = ((px&15)<<4)|(py&15));
         * vtotal = clip ? 256 : idx selects the all-zero spreadtab half for
         * clipped lanes, so no separate coeff masking is needed. */
        vidx = vsliq_n_u32 ((uint32x4_t) py, vandq_u32 ((uint32x4_t) px, vmask15), 4);
        vtotal = vbslq_u32 (clip, vzero256, vidx);

        /* extract positions + spreadtab indices (unrolled constants). */
        pos[0] = (int) vgetq_lane_u32 (vpos, 0);
        pos[1] = (int) vgetq_lane_u32 (vpos, 1);
        pos[2] = (int) vgetq_lane_u32 (vpos, 2);
        pos[3] = (int) vgetq_lane_u32 (vpos, 3);
        vt[0]  = (int) vgetq_lane_u32 (vtotal, 0);
        vt[1]  = (int) vgetq_lane_u32 (vtotal, 1);
        vt[2]  = (int) vgetq_lane_u32 (vtotal, 2);
        vt[3]  = (int) vgetq_lane_u32 (vtotal, 3);

        /* blend: one accumulator per output pixel.
         * vP[k] = [A B C D] (pos, pos+1, pos+prevX, pos+prevX+1 channels)
         * vC[k] = [c1 x4, c2 x4, c3 x4, c4 x4]
         * a[k] lanes 0..3 = A*c1 + C*c3, lanes 4..7 = B*c2 + D*c4
         * => horizontal pair add gives the 4 output channels.
         * u16 lanes wrap mod 2^16 like C's unsigned short. */
        {
            uint8x16_t vP[4], vC[4];
            uint16x8_t a[4];
            uint16x8_t acc_lo, acc_hi;

            /* gather all 4 source neighborhoods first so the L1/L2 gather
             * latency overlaps the coefficient load and multiply. */
            for (k = 0; k < 4; ++k) {
                vP[k] = vcombine_u8 (vld1_u8 ((const uint8_t *) (expix1 + pos[k])),
                                     vld1_u8 ((const uint8_t *) (expix1 + pos[k] + prevX)));
                vC[k] = vld1q_u8 ((const uint8_t *) spreadtab[vt[k]]);
            }
            for (k = 0; k < 4; ++k) {
                a[k] = vmull_u8 (vget_low_u8 (vP[k]), vget_low_u8 (vC[k]));
                a[k] = vmlal_high_u8 (a[k], vP[k], vC[k]);
            }

            /* pairwise channel sums: pixels 0,1 in acc_lo; 2,3 in acc_hi. */
            acc_lo = vcombine_u16 (vadd_u16 (vget_low_u16 (a[0]), vget_high_u16 (a[0])),
                                   vadd_u16 (vget_low_u16 (a[1]), vget_high_u16 (a[1])));
            acc_hi = vcombine_u16 (vadd_u16 (vget_low_u16 (a[2]), vget_high_u16 (a[2])),
                                   vadd_u16 (vget_low_u16 (a[3]), vget_high_u16 (a[3])));

            /* if (sum > 5) sum -= 5;  then sum >>= 8  (see main loop) */
            vst1q_u8 ((uint8_t *) (expix2 + loop),
                      vshrn_high_n_u16 (vshrn_n_u16 (vqsubq_u16 (acc_lo, vfive), 8),
                                        vqsubq_u16 (acc_hi, vfive), 8));
        }
    }

    /* scalar tail, C semantics (odd buffer sizes) */
    for (; loop < bufsize; ++loop) {
        int c1, c2, c3, c4, px, py;
        int pos, coeffs;
        unsigned char *src;
        unsigned int acc[4];
        int myPos = 2 * loop;

        if (wipeMode) {
            float fx = (float) (loop % prevX);
            float fy = (float) (loop / prevX);
            int beta_fix;
            float b = wipeBetaLane (wipeMode, blend, fx, fy, wipeHalfDiag,
                                    loop, seamCount, seamU, seamV);
            beta_fix = (int) (b * 65535.0f + 0.5f);
            /* exact endpoints: full select reads brutS/brutD directly */
            if (beta_fix >= 65535) {
                px = lbruD[myPos];
                py = lbruD[myPos+1];
            } else if (beta_fix <= 0) {
                px = lbruS[myPos];
                py = lbruS[myPos+1];
            } else {
                px = lbruS[myPos] + (((lbruD[myPos] - lbruS[myPos]) * beta_fix) >> BUFFPOINTNB);
                py = lbruS[myPos+1] + (((lbruD[myPos+1] - lbruS[myPos+1]) * beta_fix) >> BUFFPOINTNB);
            }
        } else {
        px = lbruS[myPos] + (((lbruD[myPos] - lbruS[myPos]) * buffratio) >> BUFFPOINTNB);
        py = lbruS[myPos+1] + (((lbruD[myPos+1] - lbruS[myPos+1]) * buffratio) >> BUFFPOINTNB);
        }

        if (((unsigned int) py >= ay) || ((unsigned int) px >= ax)) {
            pos = coeffs = 0;
        } else {
            pos = ((px >> PERTEDEC) + prevX * (py >> PERTEDEC));
            coeffs = precalCoef[px & PERTEMASK][py & PERTEMASK];
        }

        c1 = coeffs & 0xff;
        c2 = (coeffs >> 8) & 0xff;
        c3 = (coeffs >> 16) & 0xff;
        c4 = (coeffs >> 24) & 0xff;

        src = (unsigned char *) (expix1 + pos);
        {
            const unsigned char *src2 = (const unsigned char *) (expix1 + pos + prevX);
            int ch;
            for (ch = 0; ch < 4; ++ch) {
                acc[ch] = src[ch] * c1 + src[4+ch] * c2 + src2[ch] * c3 + src2[4+ch] * c4;
                if (acc[ch] > 5)
                    acc[ch] -= 5;
                acc[ch] >>= 8;
                ((unsigned char *) (expix2 + loop))[ch] = (unsigned char) acc[ch];
            }
        }
    }
}

#endif /* __aarch64__ */
