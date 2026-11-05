#pragma once

#include "e_texer2.h"

#include <math.h>  // NullPlayer: lrint

#ifdef _MSC_VER
#define INLINE inline __forceinline
#else
#define INLINE inline __attribute__((always_inline))
#endif

// TODO [cleanup]: This should not be ASM
INLINE int RoundToInt(double x) {
    int t;
#ifdef _MSC_VER
    __asm fld x __asm fistp t
#else
    // NullPlayer: lrint rounds to nearest like cvtsd2si/fistp; the GCC branch was
    // Intel-syntax x86 asm (-masm=intel), which neither arm64 nor our x86_64 build uses.
    t = (int)lrint(x);
#endif
        return t;
}

INLINE int FloorToInt(double f) { return (int)f; }

INLINE double Fractional(double f) { return f - (int)f; }

/* asm shorthands */
#ifdef _MSC_VER

// clang-format off
#define T2_PREP_MASK_COLOR \
    __asm pxor mm5, mm5    \
    __asm movd mm7, color  \
    __asm punpcklbw mm7, mm5

#define T2_SCALE_MINMAX_SIGNMASK \
    __asm movd mm6, signmask

#define T2_SCALE_BLEND_AND_STORE_ALPHA             \
    /* duplicate blend factor into all channels */ \
    __asm mov eax, t                               \
    __asm mov edx, eax                             \
    __asm shl eax, 16                              \
    __asm or eax, edx                              \
    __asm mov[alpha], eax                          \
    __asm mov[alpha + 4], eax                      \
    /* store alpha and (256 - alpha) */            \
    __asm movq mm6, qword ptr mmxxor               \
    __asm psubusw mm6, qword ptr alpha

#define T2_SCALE_BLEND_ASM_ENTER(LOOP_LABEL)                               \
    __asm push esi                                                         \
    __asm push edi                                                         \
    __asm push edx                                                         \
    /* esi = texture width */                                              \
    __asm mov esi, iw                                                      \
    __asm inc esi                                                          \
    __asm pxor mm5, mm5                                                    \
                                                                           \
    /* calculate dy coefficient for this scanline */                       \
    /* store in mm4 = dy cloned into all bytes */                          \
    __asm movd mm4, cy0                                                    \
    __asm psrlw mm4, 8                                                     \
    __asm punpcklwd mm4, mm4                                               \
    __asm punpckldq mm4, mm4                                               \
                                                                           \
    /* loop counter */                                                     \
    __asm mov ecx, tot                                                     \
    __asm inc ecx                                                          \
                                                                           \
    /* set output pointer */                                               \
    __asm mov edi, outp                                                    \
                                                                           \
    /* beginning x tex coordinate */                                       \
    __asm mov ebx, cx0                                                     \
                                                                           \
    /* calculate y combined address for first point a for this scanline */ \
    /* store in ebp = texture start address for this scanline */           \
    __asm mov eax, cy0                                                     \
    __asm shr eax, 16                                                      \
    __asm imul eax, esi                                                    \
    __asm shl eax, 2                                                       \
    __asm mov edx, texture                                                 \
    __asm add edx, eax                                                     \
                                                                           \
    /* begin loop */                                                       \
    __asm LOOP_LABEL:                                                      \
                                                                           \
    /* calculate dx, fractional part of tex coord */                       \
    __asm movd mm3, ebx                                                    \
    __asm psrlw mm3, 8                                                     \
    __asm punpcklwd mm3, mm3                                               \
    __asm punpckldq mm3, mm3                                               \
                                                                           \
    /* convert fixed point into floor and load pixel address */            \
    __asm mov eax, ebx                                                     \
    __asm shr eax, 16                                                      \
    __asm lea eax, dword ptr[edx + eax * 4]                                \
                                                                           \
    /* mm0 = b*dx */                                                       \
    __asm movd mm0, dword ptr[eax + 4] /* b */                             \
    __asm punpcklbw mm0, mm5                                               \
    __asm pmullw mm0, mm3                                                  \
    __asm psrlw mm0, 8 /* mm1 = a*(1-dx) */                                \
    __asm movd mm1, dword ptr[eax] /* a */                                 \
    __asm pxor mm3, mmxxor                                                 \
    __asm punpcklbw mm1, mm5                                               \
    __asm pmullw mm1, mm3                                                  \
    __asm psrlw mm1, 8                                                     \
    __asm paddw mm0, mm1                                                   \
                                                                           \
    /* mm1 = c*(1-dx) */                                                   \
    __asm movd mm1, dword ptr[eax + esi * 4] /* c */                       \
    __asm punpcklbw mm1, mm5                                               \
    __asm pmullw mm1, mm3                                                  \
    __asm psrlw mm1, 8 /* mm2 = d*dx */                                    \
    __asm movd mm2, dword ptr[eax + esi * 4 + 4] /* d */                   \
    __asm pxor mm3, mmxxor                                                 \
    __asm punpcklbw mm2, mm5                                               \
    __asm pmullw mm2, mm3                                                  \
    __asm psrlw mm2, 8                                                     \
    __asm paddw mm1, mm2                                                   \
                                                                           \
    /* combine */                                                          \
    __asm pmullw mm1, mm4                                                  \
    __asm psrlw mm1, 8                                                     \
    __asm pxor mm4, mmxxor                                                 \
    __asm pmullw mm0, mm4                                                  \
    __asm psrlw mm0, 8                                                     \
    __asm paddw mm0, mm1                                                   \
    __asm pxor mm4, mmxxor                                                 \
                                                                           \
    /* filter color */ /* (already unpacked) punpcklbw mm0, mm5 */         \
    __asm pmullw mm0, mm7

/* blendmode-specific code in between here */

#define T2_SCALE_BLEND_ASM_LEAVE(LOOP_LABEL) \
    /* write pixel */                        \
    __asm movd dword ptr[edi], mm0           \
    __asm add edi, 4                         \
                                             \
    /* advance tex coords, cx += sdx */      \
    __asm add ebx, sdx                       \
                                             \
    __asm dec ecx                            \
    __asm jnz LOOP_LABEL                     \
                                             \
    __asm pop ebx                            \
    __asm pop edx                            \
    __asm pop edi                            \
    __asm pop esi

#define T2_NONSCALE_PUSH_ESI_EDI \
    __asm push esi               \
    __asm push edi

#define T2_NONSCALE_MINMAX_MASKS \
    __asm movd mm4, maxmask      \
    __asm movd mm6, signmask

#define T2_NONSCALE_BLEND_AND_STORE_ALPHA          \
    /* duplicate blend factor into all channels */ \
    __asm mov eax, t                               \
    __asm mov edx, eax                             \
    __asm shl eax, 16                              \
    __asm or eax, edx                              \
    __asm mov[alpha], eax                          \
    __asm mov[alpha + 4], eax                      \
                                                   \
    /* store alpha and (256 - alpha) */            \
    __asm movq mm2, alpha                          \
    __asm movq mm3, salpha                         \
    __asm psubusw mm3, alpha

#define T2_NONSCALE_BLEND_ASM_ENTER(LOOP_LABEL) \
    __asm mov ecx, tot                          \
    __asm inc ecx                               \
    __asm mov edi, outp                         \
    __asm mov esi, inp                          \
    __asm LOOP_LABEL:

/* blendmode-specific code in between here */

#define T2_NONSCALE_BLEND_ASM_LEAVE(LOOP_LABEL) \
    __asm add esi, 4                            \
    __asm add edi, 4                            \
    __asm dec ecx                               \
    __asm jnz LOOP_LABEL

#define T2_NONSCALE_POP_EDI_ESI \
    __asm pop edi               \
    __asm pop esi

#define T2_ZERO_MM5 __asm pxor mm5, mm5

#define EMMS __asm emms
// clang-format on

#else  // GCC

// some asm parts (i.e. register saves) are not necessary in GCC because the clobber
// list takes care of saving registers.
#define NO_OP

// to-literal-string macro util
#define _STRINGIFY(x) #x             // x -> "x"
#define STR(x)        _STRINGIFY(x)  // indirection needed to actually evaluate x argument

// GCC extended-asm argument spec (memory location constraint)
#define ASM_M_ARG(x)  [x] "m"(x)

#define T2_PREP_MASK_COLOR               \
    __asm__ __volatile__(                \
        "pxor       %%mm5, %%mm5\n\t"    \
        "movd       %%mm7, %[color]\n\t" \
        "punpcklbw  %%mm7, %%mm5\n\t"    \
        :                                \
        : [color] "m"(color)             \
        : "mm5");

#define T2_SCALE_MINMAX_SIGNMASK                             \
    __asm__ __volatile__("movd       %%mm6, %[signmask]\n\t" \
                         :                                   \
                         : [signmask] "r"(signmask)          \
                         :);

#define T2_SCALE_BLEND_AND_STORE_ALPHA                                          \
    __asm__ __volatile__(/* duplicate blend factor into all channels */         \
                         "mov      %%eax, %[t]\n\t"                             \
                         "mov      %%edx, %%eax\n\t"                            \
                         "shl      %%eax, 16\n\t"                               \
                         "or       %%eax, %%edx\n\t"                            \
                         "mov      [%[alpha]], %%eax\n\t"                       \
                         "mov      [%[alpha] + 4], %%eax\n\t"                   \
                                                                                \
                         /* store alpha and (256 - alpha) */                    \
                         "movq     %%mm6, qword ptr %[mmxxor]\n\t"              \
                         "psubusw  %%mm6, qword ptr %[alpha]\n\t"               \
                         :                                                      \
                         : [alpha] "m"(alpha), [mmxxor] "m"(mmxxor), [t] "r"(t) \
                         : "eax", "edx", "mm6");

#define T2_SCALE_BLEND_ASM_ENTER(LOOP_LABEL)                                   \
    __asm__ __volatile__(                                                      \
        /* esi = texture width */                                              \
        "mov        %%esi, %[iw]\n\t"                                          \
        "inc        %%esi\n\t"                                                 \
        "pxor       %%mm5, %%mm5\n\t"                                          \
                                                                               \
        /* calculate dy coefficient for this scanline */                       \
        /* store in mm4 = dy cloned into all bytes */                          \
        "movd       %%mm4, %[cy0]\n\t"                                         \
        "psrlw      %%mm4, 8\n\t"                                              \
        "punpcklwd  %%mm4, %%mm4\n\t"                                          \
        "punpckldq  %%mm4, %%mm4\n\t"                                          \
                                                                               \
        /* loop counter */                                                     \
        "mov        %%ecx, %[tot]\n\t"                                         \
        "inc        %%ecx\n\t"                                                 \
                                                                               \
        /* set output pointer */                                               \
        "mov        %%edi, %[outp]\n\t"                                        \
                                                                               \
        /* beginning x tex coordinate */                                       \
        "mov        %%ebx, %[cx0]\n\t"                                         \
                                                                               \
        /* calculate y combined address for first point a for this scanline */ \
        /* store in ebp = texture start address for this scanline */           \
        "mov        %%eax, %[cy0]\n\t"                                         \
        "shr        %%eax, 16\n\t"                                             \
        "imul       %%eax, %%esi\n\t"                                          \
        "shl        %%eax, 2\n\t"                                              \
        "mov        %%edx, %[texture]\n\t"                                     \
        "add        %%edx, %%eax\n\t"                                          \
                                                                               \
        /* begin loop */                                                       \
        STR(LOOP_LABEL) ":\n\t"                                                \
                                                                               \
        /* calculate dx, fractional part of tex coord */                       \
        "movd       %%mm3, %%ebx\n\t"                                          \
        "psrlw      %%mm3, 8\n\t"                                              \
        "punpcklwd  %%mm3, %%mm3\n\t"                                          \
        "punpckldq  %%mm3, %%mm3\n\t"                                          \
                                                                               \
        /* convert fixed point into floor and load pixel address */            \
        "mov        %%eax, %%ebx\n\t"                                          \
        "shr        %%eax, 16\n\t"                                             \
        "lea        %%eax, dword ptr [%%edx + %%eax * 4]\n\t"                  \
                                                                               \
        /* mm0 = b*dx */                                                       \
        "movd       %%mm0, dword ptr [%%eax + 4]\n\t" /* b */                  \
        "punpcklbw  %%mm0, %%mm5\n\t"                                          \
        "pmullw     %%mm0, %%mm3\n\t"                                          \
        "psrlw      %%mm0, 8\n\t"                                              \
        /* mm1 = a*(1-dx) */                                                   \
        "movd       %%mm1, dword ptr [%%eax]\n\t" /* a */                      \
        "pxor       %%mm3, %[mmxxor]\n\t"                                      \
        "punpcklbw  %%mm1, %%mm5\n\t"                                          \
        "pmullw     %%mm1, %%mm3\n\t"                                          \
        "psrlw      %%mm1, 8\n\t"                                              \
        "paddw      %%mm0, %%mm1\n\t"                                          \
        /* mm1 = c*(1-dx) */                                                   \
        "movd       %%mm1, dword ptr [%%eax + %%esi * 4]\n\t" /* c */          \
        "punpcklbw  %%mm1, %%mm5\n\t"                                          \
        "pmullw     %%mm1, %%mm3\n\t"                                          \
        "psrlw      %%mm1, 8\n\t"                                              \
        /* mm2 = d*dx */                                                       \
        "movd       %%mm2, dword ptr [%%eax + %%esi * 4 + 4]\n\t" /* d */      \
        "pxor       %%mm3, %[mmxxor]\n\t"                                      \
        "punpcklbw  %%mm2, %%mm5\n\t"                                          \
        "pmullw     %%mm2, %%mm3\n\t"                                          \
        "psrlw      %%mm2, 8\n\t"                                              \
        "paddw      %%mm1, %%mm2\n\t"                                          \
                                                                               \
        /* combine */                                                          \
        "pmullw     %%mm1, %%mm4\n\t"                                          \
        "psrlw      %%mm1, 8\n\t"                                              \
        "pxor       %%mm4, %[mmxxor]\n\t"                                      \
        "pmullw     %%mm0, %%mm4\n\t"                                          \
        "psrlw      %%mm0, 8\n\t"                                              \
        "paddw      %%mm0, %%mm1\n\t"                                          \
        "pxor       %%mm4, %[mmxxor]\n\t"                                      \
                                                                               \
        /* filter color */                                                     \
        /* (already unpacked) punpcklbw mm0, mm5 */                            \
        "pmullw     %%mm0, %%mm7\n\t"                                          \
        "\n\t"

/* blendmode-specific code in between here */

#define T2_SCALE_BLEND_ASM_LEAVE(LOOP_LABEL, EXTRA_ARGS...)         \
        "\n\t"                                                      \
        /* write pixel */                                           \
        "movd       dword ptr [%%edi], %%mm0\n\t"                   \
        "add        %%edi, 4\n\t"                                   \
                                                                    \
        /* advance tex coords, cx += sdx */                         \
        "add        %%ebx, %[sdx]\n\t"                              \
                                                                    \
        "dec        %%ecx\n\t"                                      \
        "jnz        " STR(LOOP_LABEL) "\n\t"                        \
        :                                                           \
        : [iw]"rm"(iw), [sdx]"rm"(sdx),                             \
          [cx0]"rm"(cx0), [cy0]"rm"(cy0), [mmxxor]"m"(mmxxor),      \
          [texture]"rm"(texture), [tot]"rm"(tot), [outp]"rm"(outp), \
          ##EXTRA_ARGS                                              \
        : "eax", "ebx", "ecx", "edx", "esi", "edi",                 \
          "mm0", "mm1", "mm2", "mm3", "mm4", "mm5",                 \
          "memory"                                                  \
    );

#define T2_NONSCALE_PUSH_ESI_EDI NO_OP

#define T2_NONSCALE_MINMAX_MASKS                           \
    __asm__ __volatile__(                                  \
        "movd  %%mm4, %[maxmask]\n\t"                      \
        "movd  %%mm6, %[signmask]\n\t"                     \
        :                                                  \
        : [maxmask] "r"(maxmask), [signmask] "r"(signmask) \
        : "mm4", "mm6");

#define T2_NONSCALE_BLEND_AND_STORE_ALPHA                                       \
    __asm__ __volatile__(/* duplicate blend factor into all channels */         \
                         "mov      %%eax, %[t]\n\t"                             \
                         "mov      %%edx, %%eax\n\t"                            \
                         "shl      %%eax, 16\n\t"                               \
                         "or       %%eax, %%edx\n\t"                            \
                         "mov      [%[alpha]], %%eax\n\t"                       \
                         "mov      [%[alpha] + 4], %%eax\n\t"                   \
                                                                                \
                         /* store alpha and (256 - alpha) */                    \
                         "movq     %%mm6, qword ptr %[alpha]\n\t"               \
                         "movq     %%mm3, %[salpha]\n\t"                        \
                         "psubusw  %%mm3, %%mm6\n\t"                            \
                         :                                                      \
                         : [alpha] "m"(alpha), [salpha] "m"(salpha), [t] "r"(t) \
                         : "eax", "edx", "mm3", "mm6");

#define T2_NONSCALE_BLEND_ASM_ENTER(LOOP_LABEL) \
    __asm__ __volatile__(                                 \
        "mov   %%ecx, %[tot]\n\t"                         \
        "inc   %%ecx\n\t"                                 \
        "mov   %%edi, %[outp]\n\t"                        \
        "mov   %%esi, %[inp]\n\t"                         \
        STR(LOOP_LABEL) ":\n\t"

/* blendmode-specific code in between here */

#define T2_NONSCALE_BLEND_ASM_LEAVE(LOOP_LABEL)            \
        "add   %%esi, 4\n\t"                               \
        "add   %%edi, 4\n\t"                               \
        "dec   %%ecx\n\t"                                  \
        "jnz   " STR(LOOP_LABEL) "\n\t"                    \
        :                                                  \
        : [tot]"rm"(tot), [inp]"rm"(inp), [outp]"rm"(outp) \
        : "ecx", "esi", "edi", "mm0", "mm1", "mm2", "mm3", \
          "memory"                                         \
    );

#define T2_NONSCALE_POP_EDI_ESI NO_OP

#define T2_ZERO_MM5 __asm__ __volatile__("pxor mm5, mm5");

#define EMMS __asm__ __volatile__("emms");

#endif
