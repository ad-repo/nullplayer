#ifndef _SURF3D_H
#define _SURF3D_H

#include "v3d.h"
#include "goom_graphic.h"
#include "goom_typedefs.h"

typedef struct {
	v3d *vertex;
	v3d *svertex;
	int nbvertex;

	v3d center;
} surf3d;

typedef struct {
	surf3d surf;
	
	int defx;
	int sizex;
	int defz;
	int sizez;
	int mode;
	int shape;
	float phase; /* temps propre de la forme, avance a chaque update */
	float twist;      /* torsion du tunnel : cible de l'anneau profond (rad) */
	float twistCur;   /* valeur relaxee, suit twist avec un retard elastique */
	int drawMode;     /* GRID3D_DRAW_* : comment buf (source du zoom) est trace */
	int drawCnt;      /* compteur de frames pour le mode strobe */
	v2d *proj; /* persistent projection buffer, sized surf.nbvertex */
} grid3d;

/* forme du deplacement : quelle loi anime les sommets dans grid3d_update */
enum {
	GRID3D_SHAPE_TENTACLE = 0, /* rideau spectral avec propagation amortie */
	GRID3D_SHAPE_RIPPLE,       /* onde radiale stationnaire sur la feuille */
	GRID3D_SHAPE_TUNNEL,       /* feuille enroulee en tube rotatif */
	GRID3D_SHAPE_COUNT
};

/* mode de trace vers buf (la source du zoom, pas l'ecran) :
 * legacy  : colorlow a chaque frame (piste continue qui decroit)
 * strobe  : silence total, puis une rafale de quelques frames avec
 *           la couleur vive - le zoom reprend un snapshot net a
 *           chaque periode au lieu d'une piste continue
 * on-goom : l'effet n'est trace que juste apres un goom (cale sur
 *           l'effet lignes : timeSinceLastGoom < 5 frames) */
enum {
	GRID3D_DRAW_LEGACY = 0,
	GRID3D_DRAW_STROBE,
	GRID3D_DRAW_ON_GOOM
};
#define GRID3D_STROBE_PERIOD 10 /* frames entre deux rafales vers buf */
#define GRID3D_STROBE_BURST 2   /* longueur de la rafale, en frames */
#define GRID3D_ONGOOM_FRAMES 5  /* fenetre apres un goom, calee sur lines.c */

/* hi-level */

/* works on grid3d */
grid3d *grid3d_new (int sizex, int defx, int sizez, int defz, v3d center);
void grid3d_update (grid3d *g, float angle, float *vals, float *vals2, float dist);

/* low level */
void surf3d_draw (surf3d *s, int color, int dist, int *buf, int *back, int W,int H);
void grid3d_draw (PluginInfo *plug, grid3d *g, int color, int colorlow, int dist, float flow, Pixel *buf, Pixel *back, int W,int H);
void surf3d_rotate (surf3d *s, float angle);
void surf3d_translate (surf3d *s);

#endif
