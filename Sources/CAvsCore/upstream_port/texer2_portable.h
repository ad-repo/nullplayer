#pragma once

// NullPlayer: Texer II's particle rasteriser on anything but i386. Upstream's
// E_Texer2::DrawParticle draws with 32-bit MMX inline asm; these are C ports of its two loop
// families, called where the asm starts, after DrawParticle's shared clipping and mapping.

#include "vis_avs/pixel_format.h"

#include <cstdint>

// Scaling renderer: bilinear sampling over 16.16 texture coordinates, then the colour filter.
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
                        uint32_t color);

// Non-scaling renderer: texels copied 1:1, filtered by the colour when colorizing.
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
                          uint32_t color);
