#ifndef FILTERS_H
#define FILTERS_H

#include "goom_config.h"
#include "goom_typedefs.h"
#include "goom_visual_fx.h"
#include "goom_graphic.h"

VisualFX zoomFilterVisualFXWrapper_create(void);

struct _ZOOM_FILTER_DATA
{
	int     vitesse;           /* 128 = vitesse nule... * * 256 = en arriere 
	                            * hyper vite.. * * 0 = en avant hype vite. */
	unsigned char pertedec;
	unsigned char sqrtperte;
	int     middleX, middleY;  /* milieu de l'effet */
	char    reverse;           /* inverse la vitesse */
	char    mode;              /* type d'effet à appliquer (cf les #define) */
	/** @since June 2001 */
	int     hPlaneEffect;      /* deviation horitontale */
	int     vPlaneEffect;      /* deviation verticale */
	/** @since April 2002 */
	int     waveEffect;        /* applique une "surcouche" de wave effect */
	int     hypercosEffect;    /* applique une "surcouche de hypercos effect */

	/** kaleidoscope addon (s'applique a tous les modes) */
	int     kaleidoEffect;      /* 1 = plier l'espace source en mandala */
	int     foldCount;          /* nombre de secteurs N (0 = defaut) */
	float   foldAngle;          /* rotation du eventail de miroirs (radians) */

	char    noisify;           /* ajoute un bruit a la transformation */
};

#define NORMAL_MODE 0
#define WAVE_MODE 1
#define CRYSTAL_BALL_MODE 2
#define SCRUNCH_MODE 3
#define AMULETTE_MODE 4
#define WATER_MODE 5
#define HYPERCOS1_MODE 6
#define HYPERCOS2_MODE 7
#define YONLY_MODE 8
#define SPEEDWAY_MODE 9
/* NullPlayer port additions (centered: goom_core.c keeps them on the middle, no plane/noise). */
#define SPIRAL_MODE 10
#define VORTEX_MODE 11
#define FLOWER_MODE 12
#define HEART_MODE 13
#define PENTAGRAM_MODE 14
#define NB_ZOOM_MODES 15

void pointFilter (PluginInfo *goomInfo, Pixel * pix1, Color c,
                  float t1, float t2, float t3, float t4, guint32 cycle);

/* filtre de zoom :
 * le contenu de pix1 est copie dans pix2.
 * zf : si non NULL, configure l'effet.
 * resx,resy : taille des buffers.
 */
void zoomFilterFastRGB (PluginInfo *goomInfo, Pixel * pix1, Pixel * pix2, ZoomFilterData * zf, guint32 resx,
                        guint32 resy, int *switchIncr, float *switchMult);
/* Velocity (in px/frame) of the image content at position (x, y), as applied
 * this frame by the transformation buffer. Returns (0, 0) when the zoom
 * filter is disabled or its buffers are not ready yet.
 * (x, y) is clamped to the screen, so offscreen positions get the nearest
 * edge velocity.
 * When the kaleidoscope addon folds the transformation space, the raw
 * transform vector is not the motion the content makes (it carries the
 * fold's own displacement): this returns the flow the mirrored content
 * really travels - bounded like the base mode, mirror-consistent from one
 * sector to the next, though flipped across the seams. */
void zoomFilterGetVelocity (PluginInfo *goomInfo, float x, float y, float *vx, float *vy);

#endif
