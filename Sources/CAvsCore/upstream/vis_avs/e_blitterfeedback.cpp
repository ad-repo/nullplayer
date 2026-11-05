/*
  LICENSE
  -------
Copyright 2005 Nullsoft, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.

  * Neither the name of Nullsoft nor the names of its contributors may be used to
    endorse or promote products derived from this software without specific prior
    written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/
// alphachannel safe 11/21/99
// highly optimized on 10/10/00 JF. MMX.

#include "e_blitterfeedback.h"

#include "blend.h"

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter BlitterFeedback_Info::parameters[];

void BlitterFeedback_Info::on_zoom_change(Effect* component,
                                          const Parameter* parameter,
                                          const std::vector<int64_t>&) {
    auto blitter = (E_BlitterFeedback*)component;
    blitter->set_current_zoom((int32_t)blitter->get_int(parameter->handle));
}

// {0x1000100,0x1000100}; <<- this is actually more correct, but we're going for
// consistency vs. the non-mmx ver
// -jf
static const uint64_t revn = 0x00ff00ff00ff00ff;
static const int zero = 0;

E_BlitterFeedback::E_BlitterFeedback(AVS_Instance* avs)
    : Configurable_Effect(avs), current_zoom(this->config.zoom) {}

void E_BlitterFeedback::set_current_zoom(int32_t zoom) { this->current_zoom = zoom; }

int E_BlitterFeedback::blitter_out(uint32_t* framebuffer,
                                   uint32_t* fbout,
                                   int w,
                                   int h,
                                   int32_t zoom) {
    const int32_t adj = 7;
    int32_t ds_x = ((zoom + (1 << adj) - 32) << (16 - adj));
    int32_t x_len = ((w << 16) / ds_x) & ~3;
    int32_t y_len = (h << 16) / ds_x;

    if (x_len >= w || y_len >= h) {
        return 0;
    }

    int32_t start_x = (w - x_len) / 2;
    int32_t start_y = (h - y_len) / 2;
    int32_t s_y = 32768;

    int32_t* dest = (int32_t*)framebuffer + start_y * w + start_x;
    int32_t* src = (int32_t*)fbout + start_y * w + start_x;
    int32_t y;

    fbout += start_y * w;
    for (y = 0; y < y_len; y++) {
        int32_t s_x = 32768;
        uint32_t* src = framebuffer + (s_y >> 16) * w;
        uint32_t* old_dest = fbout + start_x;
        s_y += ds_x;
        if (this->config.blend_mode == BLITTER_BLEND_REPLACE) {
            int32_t x = x_len / 4;
            while (x--) {
                old_dest[0] = src[s_x >> 16];
                s_x += ds_x;
                old_dest[1] = src[s_x >> 16];
                s_x += ds_x;
                old_dest[2] = src[s_x >> 16];
                s_x += ds_x;
                old_dest[3] = src[s_x >> 16];
                s_x += ds_x;
                old_dest += 4;
            }
        } else {  // BLITTER_BLEND_5050
            uint32_t* s2 = (uint32_t*)framebuffer + ((y + start_y) * w) + start_x;
            int32_t x = x_len / 4;
            while (x--) {
                blend_5050_1px(&src[s_x >> 16], &s2[0], &old_dest[0]);
                s_x += ds_x;
                blend_5050_1px(&src[s_x >> 16], &s2[1], &old_dest[1]);
                s_x += ds_x;
                blend_5050_1px(&src[s_x >> 16], &s2[2], &old_dest[2]);
                s_x += ds_x;
                blend_5050_1px(&src[s_x >> 16], &s2[3], &old_dest[3]);
                s2 += 4;
                old_dest += 4;
                s_x += ds_x;
            }
        }
        fbout += w;
    }
    for (y = 0; y < y_len; y++) {
        memcpy(dest, src, x_len * sizeof(int32_t));
        dest += w;
        src += w;
    }

    return 0;
}

int E_BlitterFeedback::blitter_normal(uint32_t* framebuffer,
                                      uint32_t* fbout,
                                      int w,
                                      int h,
                                      int32_t zoom) {
    int32_t ds_x = ((zoom + 32) << 16) / 64;
    int32_t isx = (((w << 16) - ((ds_x * w))) / 2);
    int32_t s_y = (((h << 16) - ((ds_x * h))) / 2);

    if (this->config.bilinear) {
        int32_t y;
        for (y = 0; y < h; y++) {
            int32_t s_x = isx;
            uint32_t* src = ((uint32_t*)framebuffer) + (s_y >> 16) * w;
            int32_t ypart = (s_y >> 8) & 0xff;
            s_y += ds_x;
#ifdef NO_MMX
            // NullPlayer: BLEND4 was renamed blend_bilinear_2x2 upstream; this path wasn't.
            {
                ypart = (ypart * 255) >> 8;
                int32_t x = w / 4;
                while (x--) {
                    fbout[0] = blend_bilinear_2x2(src + (s_x >> 16), w, (s_x >> 8) & 0xff, ypart);
                    s_x += ds_x;
                    fbout[1] = blend_bilinear_2x2(src + (s_x >> 16), w, (s_x >> 8) & 0xff, ypart);
                    s_x += ds_x;
                    fbout[2] = blend_bilinear_2x2(src + (s_x >> 16), w, (s_x >> 8) & 0xff, ypart);
                    s_x += ds_x;
                    fbout[3] = blend_bilinear_2x2(src + (s_x >> 16), w, (s_x >> 8) & 0xff, ypart);
                    s_x += ds_x;
                    fbout += 4;
                }
            }
#else
            {
                int64_t mem5 = 0;
                int64_t mem7 = 0;
#ifdef _MSC_VER  // MSVC asm
                __asm {
            mov edi, fbout
            mov esi, w

            movd mm7, ypart
            punpcklwd mm7,mm7

            movq mm5, revn
            punpckldq mm7,mm7

            psubw mm5, mm7
            mov ecx, esi

            movq mem5,mm5
            movq mem7,mm7

            shr ecx, 1
            mov edx, s_x

            align 16
      mmx_scale_loop1:

            mov ebx, edx
            mov eax, edx

            shr eax, 14
            add edx, ds_x

            shr ebx, 8
            and eax, ~3

            add eax, src
            and ebx, 0xff

            movd mm6, ebx

            movq mm4, revn
            punpcklwd mm6,mm6

            movd mm0, [eax]
            punpckldq mm6,mm6

            movd mm1, [eax+4]
            psubw mm4, mm6

            movd mm2, [eax+esi*4]
            punpcklbw mm0, [zero]

            movd mm3, [eax+esi*4+4]
            pmullw mm0, mm4  // mm0 used in divide for 3 cycles

            punpcklbw mm1, [zero]
            mov eax, edx

            pmullw mm1, mm6  // mm1 used in divide for 3 cycles
            punpcklbw mm2, [zero]

            pmullw mm2, mm4  // mm2 used in divide for 3 cycles
            punpcklbw mm3, [zero]

            pmullw mm3, mm6  // mm3 used in divide for 3 cycles
            shr eax, 14

            mov ebx, edx
            and eax, ~3

            paddw mm0, mm1
            shr ebx, 8

            psrlw mm0, 8
            add eax, src

            paddw mm2, mm3
            and ebx, 0xff

            pmullw mm0, mem5
            psrlw mm2, 8

            pmullw mm2, mem7
            add edx, ds_x


            movd mm6, ebx

            movq mm4, revn
            punpcklwd mm6,mm6


            movd mm1, [eax+4]

            movd mm7, [eax+esi*4]
            paddw mm0, mm2

            movd mm5, [eax]
            psrlw mm0, 8

            movd mm3, [eax+esi*4+4]
            packuswb mm0, mm0

            movd [edi], mm0
            punpckldq mm6,mm6

                        // poop

            punpcklbw mm5, [zero]
            psubw mm4, mm6

            punpcklbw mm1, [zero]
            pmullw mm5, mm4

            punpcklbw mm7, [zero]
            pmullw mm1, mm6

            punpcklbw mm3, [zero]
            pmullw mm7, mm4

                        // cycle

            paddw mm5, mm1

            pmullw mm3, mm6
            psrlw mm5, 8

            pmullw mm5, mem5
            add edi, 8

                    // cycle

            paddw mm7, mm3

            psrlw mm7, 8

            pmullw mm7, mem7
            dec ecx

                        // cycle

            paddw mm5, mm7

            psrlw mm5, 8

            packuswb mm5, mm5

            movd [edi-4], mm5

            jnz mmx_scale_loop1
            mov fbout, edi
            emms
                }
#else            // _MSC_VER, GCC asm
                __asm__ __volatile__(
                    "push      %%edi\n\t"
                    "mov       %%edi, %[fbout]\n\t"
                    "mov       %%esi, %[w]\n\t"
                    "movd      %%mm7, %[ypart]\n\t"
                    "punpcklwd %%mm7, %%mm7\n\t"
                    "movq      %%mm5, [%[revn]]\n\t"
                    "punpckldq %%mm7, %%mm7\n\t"
                    "psubw     %%mm5, %%mm7\n\t"
                    "mov       %%ecx, %%esi\n\t"
                    "movq      [%[mem5]], %%mm5\n\t"
                    "movq      [%[mem7]], %%mm7\n\t"
                    "shr       %%ecx, 1\n\t"
                    "mov       %%edx, %[s_x]\n\t"
                    ".align    16\n"
                    "mmx_scale_loop1:\n\t"
                    "mov       %%ebx, %%edx\n\t"
                    "mov       %%eax, %%edx\n\t"
                    "shr       %%eax, 14\n\t"
                    "add       %%edx, %[ds_x]\n\t"
                    "shr       %%ebx, 8\n\t"
                    "and       %%eax, ~3\n\t"
                    "add       %%eax, %[src]\n\t"
                    "and       %%ebx, 0xff\n\t"
                    "movd      %%mm6, %%ebx\n\t"
                    "movq      %%mm4, [%[revn]]\n\t"
                    "punpcklwd %%mm6, %%mm6\n\t"
                    "movd      %%mm0, [%%eax]\n\t"
                    "punpckldq %%mm6, %%mm6\n\t"
                    "movd      %%mm1, [%%eax+4]\n\t"
                    "psubw     %%mm4, %%mm6\n\t"
                    "movd      %%mm2, [%%eax + %%esi * 4]\n\t"
                    "punpcklbw %%mm0, %[zero]\n\t"
                    "movd      %%mm3, [%%eax + %%esi * 4 + 4]\n\t"
                    "pmullw    %%mm0, %%mm4\n\t"
                    "punpcklbw %%mm1, %[zero]\n\t"
                    "mov       %%eax, %%edx\n\t"
                    "pmullw    %%mm1, %%mm6\n\t"
                    "punpcklbw %%mm2, %[zero]\n\t"
                    "pmullw    %%mm2, %%mm4\n\t"
                    "punpcklbw %%mm3, %[zero]\n\t"
                    "pmullw    %%mm3, %%mm6\n\t"
                    "shr       %%eax, 14\n\t"
                    "mov       %%ebx, %%edx\n\t"
                    "and       %%eax, ~3\n\t"
                    "paddw     %%mm0, %%mm1\n\t"
                    "shr       %%ebx, 8\n\t"
                    "psrlw     %%mm0, 8\n\t"
                    "add       %%eax, %[src]\n\t"
                    "paddw     %%mm2, %%mm3\n\t"
                    "and       %%ebx, 0xff\n\t"
                    "pmullw    %%mm0, %[mem5]\n\t"
                    "psrlw     %%mm2, 8\n\t"
                    "pmullw    %%mm2, %[mem7]\n\t"
                    "add       %%edx, %[ds_x]\n\t"
                    "movd      %%mm6, %%ebx\n\t"
                    "movq      %%mm4, [%[revn]]\n\t"
                    "punpcklwd %%mm6, %%mm6\n\t"
                    "movd      %%mm1, [%%eax+4]\n\t"
                    "movd      %%mm7, [%%eax + %%esi * 4]\n\t"
                    "paddw     %%mm0, %%mm2\n\t"
                    "movd      %%mm5, [%%eax]\n\t"
                    "psrlw     %%mm0, 8\n\t"
                    "movd      %%mm3, [%%eax + %%esi * 4 + 4]\n\t"
                    "packuswb  %%mm0, %%mm0\n\t"
                    "movd      [%%edi], %%mm0\n\t"
                    "punpckldq %%mm6, %%mm6\n\t"
                    "punpcklbw %%mm5, %[zero]\n\t"
                    "psubw     %%mm4, %%mm6\n\t"
                    "punpcklbw %%mm1, %[zero]\n\t"
                    "pmullw    %%mm5, %%mm4\n\t"
                    "punpcklbw %%mm7, %[zero]\n\t"
                    "pmullw    %%mm1, %%mm6\n\t"
                    "punpcklbw %%mm3, %[zero]\n\t"
                    "pmullw    %%mm7, %%mm4\n\t"
                    "paddw     %%mm5, %%mm1\n\t"
                    "pmullw    %%mm3, %%mm6\n\t"
                    "psrlw     %%mm5, 8\n\t"
                    "pmullw    %%mm5, %[mem5]\n\t"
                    "add       %%edi, 8\n\t"
                    "paddw     %%mm7, %%mm3\n\t"
                    "psrlw     %%mm7, 8\n\t"
                    "pmullw    %%mm7, %[mem7]\n\t"
                    "dec       %%ecx\n\t"
                    "paddw     %%mm5, %%mm7\n\t"
                    "psrlw     %%mm5, 8\n\t"
                    "packuswb  %%mm5, %%mm5\n\t"
                    "movd      [%%edi - 4], %%mm5\n\t"
                    "jnz       mmx_scale_loop1\n\t"
                    "mov       %[fbout], %%edi\n\t"
                    "pop       %%edi\n\t"
                    "emms\n\t"
                    : [fbout] "+m"(fbout), [mem5] "+m"(mem5), [mem7] "+m"(mem7)
                    : [w] "m"(w),
                      [ypart] "rm"(ypart),
                      [revn] "m"(revn),
                      [s_x] "rm"(s_x),
                      [ds_x] "rm"(ds_x),
                      [src] "m"(src),
                      [zero] "m"(zero)
                    : "eax", "ebx", "ecx", "edx", "esi");  //, "edi");
#endif           // _MSC_VER
            }  // end mmx
#endif
            if (this->config.blend_mode == BLITTER_BLEND_5050) {
                // reblend this scanline with the original
                fbout -= w;
                int32_t x = w / 4;
                uint32_t* s2 = (uint32_t*)framebuffer + y * w;
                while (x--) {
                    blend_5050_1px(&s2[0], &fbout[0], &fbout[0]);
                    blend_5050_1px(&s2[1], &fbout[1], &fbout[1]);
                    blend_5050_1px(&s2[2], &fbout[2], &fbout[2]);
                    blend_5050_1px(&s2[3], &fbout[3], &fbout[3]);
                    fbout += 4;
                    s2 += 4;
                }
            }
        }  // end subpixel y loop
    } else {  // !this->config.bilinear
        int32_t y;
        for (y = 0; y < h; y++) {
            int32_t s_x = isx;
            uint32_t* src = ((uint32_t*)framebuffer) + (s_y >> 16) * w;
            s_y += ds_x;
            if (this->config.blend_mode == BLITTER_BLEND_REPLACE) {
                int32_t x = w / 4;
                while (x--) {
                    fbout[0] = src[s_x >> 16];
                    s_x += ds_x;
                    fbout[1] = src[s_x >> 16];
                    s_x += ds_x;
                    fbout[2] = src[s_x >> 16];
                    s_x += ds_x;
                    fbout[3] = src[s_x >> 16];
                    s_x += ds_x;
                    fbout += 4;
                }
            } else {
                uint32_t* s2 = (uint32_t*)framebuffer + (y * w);
                int32_t x = w / 4;
                while (x--) {
                    blend_5050_1px(&src[s_x >> 16], &s2[0], &fbout[0]);
                    s_x += ds_x;
                    blend_5050_1px(&src[s_x >> 16], &s2[1], &fbout[1]);
                    s_x += ds_x;
                    blend_5050_1px(&src[s_x >> 16], &s2[2], &fbout[2]);
                    s_x += ds_x;
                    blend_5050_1px(&src[s_x >> 16], &s2[3], &fbout[3]);
                    s2 += 4;
                    fbout += 4;
                    s_x += ds_x;
                }
            }
        }
    }
    return 1;
}

int E_BlitterFeedback::render(char[2][2][576],
                              int is_beat,
                              int* framebuffer,
                              int* fbout,
                              int w,
                              int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }

    if (is_beat && this->config.on_beat) {
        this->current_zoom = this->config.on_beat_zoom;
    }

    int32_t target_zoom;
    if (this->config.zoom < this->config.on_beat_zoom) {
        target_zoom = max(this->current_zoom, (int32_t)this->config.zoom);
        this->current_zoom -= 3;
    } else {
        target_zoom = min(this->current_zoom, (int32_t)this->config.zoom);
        this->current_zoom += 3;
    }

    if (target_zoom < 0) {
        target_zoom = 0;
    }

    if (target_zoom < 32) {
        return blitter_normal(
            (uint32_t*)framebuffer, (uint32_t*)fbout, w, h, target_zoom);
    }
    if (target_zoom > 32) {
        return blitter_out((uint32_t*)framebuffer, (uint32_t*)fbout, w, h, target_zoom);
    }
    return 0;
}

void E_BlitterFeedback::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->config.zoom = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_zoom = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.blend_mode = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_zoom = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.bilinear = GET_INT();
        pos += 4;
    }

    this->current_zoom = (int32_t)this->config.zoom;
}

int E_BlitterFeedback::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->config.zoom);
    pos += 4;
    PUT_INT(this->config.on_beat_zoom);
    pos += 4;
    PUT_INT(this->config.blend_mode);
    pos += 4;
    PUT_INT(this->config.on_beat_zoom);
    pos += 4;
    PUT_INT(this->config.bilinear);
    pos += 4;
    return pos;
}

Effect_Info* create_BlitterFeedback_Info() { return new BlitterFeedback_Info(); }
Effect* create_BlitterFeedback(AVS_Instance* avs) { return new E_BlitterFeedback(avs); }
void set_BlitterFeedback_desc(char* desc) { E_BlitterFeedback::set_desc(desc); }
