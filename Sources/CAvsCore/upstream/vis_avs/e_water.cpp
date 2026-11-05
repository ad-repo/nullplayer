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
#include "e_water.h"

#include "pixel_format.h"

#include <immintrin.h>

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255
#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

#define _R(x)         ((x) & 0xff)
#define _G(x)         (((x)) & 0xff00)
#define _B(x)         (((x)) & 0xff0000)
#define _RGB(r, g, b) ((r) | ((g) & 0xff00) | ((b) & 0xff0000))

E_Water::E_Water(AVS_Instance* avs)
    : Configurable_Effect(avs), lastframe(NULL), lastframe_size(0) {}
E_Water::~E_Water() { free(this->lastframe); }

static const int zero = 0;

int E_Water::render(char visdata[2][2][576],
                    int is_beat,
                    int* framebuffer,
                    int* fbout,
                    int w,
                    int h) {
    smp_begin(1, visdata, is_beat, framebuffer, fbout, w, h);
    if (is_beat & 0x80000000) {
        return 0;
    }

    smp_render(0, 1, visdata, is_beat, framebuffer, fbout, w, h);
    return smp_finish(visdata, is_beat, framebuffer, fbout, w, h);
}

int E_Water::smp_begin(int max_threads,
                       char[2][2][576],
                       int,
                       int*,
                       int*,
                       int w,
                       int h) {
    if (!this->lastframe || w * h != this->lastframe_size) {
        if (this->lastframe) {
            free(this->lastframe);
        }
        this->lastframe_size = w * h;
        this->lastframe = (unsigned int*)calloc(w * h, pixel_size(AVS_PIXEL_RGB0_8));
    }

    return max_threads;
}

int E_Water::smp_finish(char[2][2][576], int, int*, int*, int, int) {
    return this->enabled;
}

void E_Water::smp_render(int this_thread,
                         int max_threads,
                         char[2][2][576],
                         int,
                         int* framebuffer,
                         int* fbout,
                         int w,
                         int h) {
    unsigned int* f = (unsigned int*)framebuffer;
    unsigned int* of = (unsigned int*)fbout;
    unsigned int* last = (unsigned int*)this->lastframe;

    int start_l = (this_thread * h) / max_threads;
    int end_l;

    if (this_thread >= max_threads - 1) {
        end_l = h;
    } else {
        end_l = ((this_thread + 1) * h) / max_threads;
    }

    int outh = end_l - start_l;
    if (outh < 1) {
        return;
    }

    int skip_pix = start_l * w;

    f += skip_pix;
    of += skip_pix;
    last += skip_pix;

    int at_top = 0, at_bottom = 0;

    if (!this_thread) {
        at_top = 1;
    }
    if (this_thread >= max_threads - 1) {
        at_bottom = 1;
    }

    /*
    Convolution filters (where p is the previous frame's value):

    top-left pixel        top row        top-right pixel
      -p  1          . . . ½  -p  ½ . . .    1 -p
       1  0                0   ½  0          0  1

       .                      .                 .
       .                      .                 .
     left column         middle block     right column
       ½  0                0  ½  0           0  ½
      -p  ½          . . . ½ -p  ½ . . .     ½ -p
       ½  0                0  ½  0           0  ½
       .                      .                 .
       .                      .                 .

    bottom-left pixel     bottom row     bottom-right pixel
       1  0                0  ½  0           0  1
      -p  1          . . . ½ -p  ½ . . .     1 -p
    */
    {
        // top line
        if (at_top) {
            int x;

            // left edge
            {
                int r = _R(f[1]);
                int g = _G(f[1]);
                int b = _B(f[1]);
                r += _R(f[w]);
                g += _G(f[w]);
                b += _B(f[w]);
                f++;

                r -= _R(last[0]);
                g -= _G(last[0]);
                b -= _B(last[0]);
                last++;

                if (r < 0) {
                    r = 0;
                } else if (r > 255) {
                    r = 255;
                }
                if (g < 0) {
                    g = 0;
                } else if (g > 255 * 256) {
                    g = 255 * 256;
                }
                if (b < 0) {
                    b = 0;
                } else if (b > 255 * 65536) {
                    b = 255 * 65536;
                }
                *of++ = _RGB(r, g, b);
            }

            // middle of line
            x = (w - 2);
            while (x--) {
                int r = _R(f[1]);
                int g = _G(f[1]);
                int b = _B(f[1]);
                r += _R(f[-1]);
                g += _G(f[-1]);
                b += _B(f[-1]);
                r += _R(f[w]);
                g += _G(f[w]);
                b += _B(f[w]);
                f++;

                r /= 2;
                g /= 2;
                b /= 2;

                r -= _R(last[0]);
                g -= _G(last[0]);
                b -= _B(last[0]);
                last++;

                if (r < 0) {
                    r = 0;
                } else if (r > 255) {
                    r = 255;
                }
                if (g < 0) {
                    g = 0;
                } else if (g > 255 * 256) {
                    g = 255 * 256;
                }
                if (b < 0) {
                    b = 0;
                } else if (b > 255 * 65536) {
                    b = 255 * 65536;
                }
                *of++ = _RGB(r, g, b);
            }

            // right block
            {
                int r = _R(f[-1]);
                int g = _G(f[-1]);
                int b = _B(f[-1]);
                r += _R(f[w]);
                g += _G(f[w]);
                b += _B(f[w]);
                f++;

                r -= _R(last[0]);
                g -= _G(last[0]);
                b -= _B(last[0]);
                last++;

                if (r < 0) {
                    r = 0;
                } else if (r > 255) {
                    r = 255;
                }
                if (g < 0) {
                    g = 0;
                } else if (g > 255 * 256) {
                    g = 255 * 256;
                }
                if (b < 0) {
                    b = 0;
                } else if (b > 255 * 65536) {
                    b = 255 * 65536;
                }
                *of++ = _RGB(r, g, b);
            }
        }

        // middle block
        {
            int y = outh - at_top - at_bottom;
            while (y--) {
                int x;

                // left edge
                {
                    int r = _R(f[1]);
                    int g = _G(f[1]);
                    int b = _B(f[1]);
                    r += _R(f[w]);
                    g += _G(f[w]);
                    b += _B(f[w]);
                    r += _R(f[-w]);
                    g += _G(f[-w]);
                    b += _B(f[-w]);
                    f++;

                    r /= 2;
                    g /= 2;
                    b /= 2;

                    r -= _R(last[0]);
                    g -= _G(last[0]);
                    b -= _B(last[0]);
                    last++;

                    if (r < 0) {
                        r = 0;
                    } else if (r > 255) {
                        r = 255;
                    }
                    if (g < 0) {
                        g = 0;
                    } else if (g > 255 * 256) {
                        g = 255 * 256;
                    }
                    if (b < 0) {
                        b = 0;
                    } else if (b > 255 * 65536) {
                        b = 255 * 65536;
                    }
                    *of++ = _RGB(r, g, b);
                }

                // middle of line
                x = (w - 2);
#ifdef SIMD_MODE_X86_SSE
                __m128i zero = _mm_setzero_si128();
                while (x >= 4) {
                    __m128i right = _mm_loadu_si128((__m128i*)&f[1]);
                    __m128i left = _mm_loadu_si128((__m128i*)&f[-1]);
                    __m128i down = _mm_loadu_si128((__m128i*)&f[w]);
                    __m128i up = _mm_loadu_si128((__m128i*)&f[-w]);
                    __m128i prev = _mm_loadu_si128((__m128i*)last);
                    __m128i f_2px_lo = _mm_adds_epu16(_mm_unpacklo_epi8(right, zero),
                                                      _mm_unpacklo_epi8(left, zero));
                    __m128i f_2px_hi = _mm_adds_epu16(_mm_unpackhi_epi8(right, zero),
                                                      _mm_unpackhi_epi8(left, zero));
                    f_2px_lo = _mm_adds_epu16(f_2px_lo, _mm_unpacklo_epi8(down, zero));
                    f_2px_hi = _mm_adds_epu16(f_2px_hi, _mm_unpackhi_epi8(down, zero));
                    f_2px_lo = _mm_adds_epu16(f_2px_lo, _mm_unpacklo_epi8(up, zero));
                    f_2px_hi = _mm_adds_epu16(f_2px_hi, _mm_unpackhi_epi8(up, zero));
                    f_2px_lo = _mm_srli_epi16(f_2px_lo, 1);
                    f_2px_hi = _mm_srli_epi16(f_2px_hi, 1);
                    f_2px_lo = _mm_subs_epu16(f_2px_lo, _mm_unpacklo_epi8(prev, zero));
                    f_2px_hi = _mm_subs_epu16(f_2px_hi, _mm_unpackhi_epi8(prev, zero));
                    __m128i f_4x = _mm_packus_epi16(f_2px_lo, f_2px_hi);
                    _mm_storeu_si128((__m128i*)of, f_4x);
                    f += 4;
                    last += 4;
                    of += 4;
                    x -= 4;
                }
#endif
                // Non-SIMD version, but also fill remaining 2 pixels at the end of each
                // row in SIMD mode (because 4*n width - 2 border pixels = 2 remaining).
                while (x--) {
                    int r = _R(f[1]);
                    int g = _G(f[1]);
                    int b = _B(f[1]);
                    r += _R(f[-1]);
                    g += _G(f[-1]);
                    b += _B(f[-1]);
                    r += _R(f[w]);
                    g += _G(f[w]);
                    b += _B(f[w]);
                    r += _R(f[-w]);
                    g += _G(f[-w]);
                    b += _B(f[-w]);
                    f++;

                    r /= 2;
                    g /= 2;
                    b /= 2;

                    r -= _R(last[0]);
                    g -= _G(last[0]);
                    b -= _B(last[0]);
                    last++;

                    if (r < 0) {
                        r = 0;
                    } else if (r > 255) {
                        r = 255;
                    }
                    if (g < 0) {
                        g = 0;
                    } else if (g > 255 * 256) {
                        g = 255 * 256;
                    }
                    if (b < 0) {
                        b = 0;
                    } else if (b > 255 * 65536) {
                        b = 255 * 65536;
                    }
                    *of++ = _RGB(r, g, b);
                }

                // right block
                {
                    int r = _R(f[-1]);
                    int g = _G(f[-1]);
                    int b = _B(f[-1]);
                    r += _R(f[w]);
                    g += _G(f[w]);
                    b += _B(f[w]);
                    r += _R(f[-w]);
                    g += _G(f[-w]);
                    b += _B(f[-w]);
                    f++;

                    r /= 2;
                    g /= 2;
                    b /= 2;

                    r -= _R(last[0]);
                    g -= _G(last[0]);
                    b -= _B(last[0]);
                    last++;

                    if (r < 0) {
                        r = 0;
                    } else if (r > 255) {
                        r = 255;
                    }
                    if (g < 0) {
                        g = 0;
                    } else if (g > 255 * 256) {
                        g = 255 * 256;
                    }
                    if (b < 0) {
                        b = 0;
                    } else if (b > 255 * 65536) {
                        b = 255 * 65536;
                    }
                    *of++ = _RGB(r, g, b);
                }
            }
        }
        // bottom line
        if (at_bottom) {
            int x;

            // left edge
            {
                int r = _R(f[1]);
                int g = _G(f[1]);
                int b = _B(f[1]);
                r += _R(f[-w]);
                g += _G(f[-w]);
                b += _B(f[-w]);
                f++;

                r -= _R(last[0]);
                g -= _G(last[0]);
                b -= _B(last[0]);
                last++;

                if (r < 0) {
                    r = 0;
                } else if (r > 255) {
                    r = 255;
                }
                if (g < 0) {
                    g = 0;
                } else if (g > 255 * 256) {
                    g = 255 * 256;
                }
                if (b < 0) {
                    b = 0;
                } else if (b > 255 * 65536) {
                    b = 255 * 65536;
                }
                *of++ = _RGB(r, g, b);
            }

            // middle of line
            x = (w - 2);
            while (x--) {
                int r = _R(f[1]);
                int g = _G(f[1]);
                int b = _B(f[1]);
                r += _R(f[-1]);
                g += _G(f[-1]);
                b += _B(f[-1]);
                r += _R(f[-w]);
                g += _G(f[-w]);
                b += _B(f[-w]);
                f++;

                r /= 2;
                g /= 2;
                b /= 2;

                r -= _R(last[0]);
                g -= _G(last[0]);
                b -= _B(last[0]);
                last++;

                if (r < 0) {
                    r = 0;
                } else if (r > 255) {
                    r = 255;
                }
                if (g < 0) {
                    g = 0;
                } else if (g > 255 * 256) {
                    g = 255 * 256;
                }
                if (b < 0) {
                    b = 0;
                } else if (b > 255 * 65536) {
                    b = 255 * 65536;
                }
                *of++ = _RGB(r, g, b);
            }

            // right block
            {
                int r = _R(f[-1]);
                int g = _G(f[-1]);
                int b = _B(f[-1]);
                r += _R(f[-w]);
                g += _G(f[-w]);
                b += _B(f[-w]);
                f++;

                r -= _R(last[0]);
                g -= _G(last[0]);
                b -= _B(last[0]);
                last++;

                if (r < 0) {
                    r = 0;
                } else if (r > 255) {
                    r = 255;
                }
                if (g < 0) {
                    g = 0;
                } else if (g > 255 * 256) {
                    g = 255 * 256;
                }
                if (b < 0) {
                    b = 0;
                } else if (b > 255 * 65536) {
                    b = 255 * 65536;
                }
                *of++ = _RGB(r, g, b);
            }
        }
    }

    memcpy(this->lastframe + skip_pix, framebuffer + skip_pix, w * outh * sizeof(int));
}

void E_Water::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = GET_INT() != 0;
        pos += 4;
    }
}

int E_Water::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->enabled);
    pos += 4;
    return pos;
}

Effect_Info* create_Water_Info() { return new Water_Info(); }
Effect* create_Water(AVS_Instance* avs) { return new E_Water(avs); }
void set_Water_desc(char* desc) { E_Water::set_desc(desc); }
