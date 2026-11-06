#ifndef _GOOM_FX_H
#define _GOOM_FX_H

#include "goom_visual_fx.h"
#include "goom_plugin_info.h"

VisualFX convolve_create ();
VisualFX flying_star_create (void);

void zoom_filter_c(int sizeX, int sizeY, Pixel *src, Pixel *dest, int *brutS, int *brutD, int buffratio, int precalCoef[16][16], const ZoomBlend *blend);

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
void zoom_filter_neon(int prevX, int prevY, Pixel *expix1, Pixel *expix2, int *lbruS, int *lbruD, int buffratio, int precalCoef[16][16], const ZoomBlend *blend);
#endif

#endif
