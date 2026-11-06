/*
 * Modified for NullPlayer, 2026-11-06 (LGPL-2.1 section 2(a)):
 * adds the GML_HEART and GML_PENTAGRAM scope shapes and the GML_ROSE and GML_CRIMSON
 * colours.
 * Upstream: https://github.com/j3k0/goom at e4fc3550457cf5a5b194fa9ec8219d3f1e78acc7.
 */
/*
 *  lines.c
 */

#include "lines.h"
#include <math.h>
#include <stdlib.h>
#include <stdio.h>
#include "goom_tools.h"
#include "drawmethods.h"
#include "goom_plugin_info.h"

static inline unsigned char lighten (unsigned char value, float power)
{
	int     val = value;
	float   t = (float) val * log10(power) / 2.0;

	if (t > 0) {
		val = (int) t; /* (32.0f * log (t)); */
		if (val > 255)
			val = 255;
		if (val < 0)
			val = 0;
		return val;
	}
	else {
		return 0;
	}
}

static void lightencolor (guint32 *col, float power)
{
	unsigned char *color;

	color = (unsigned char *) col;
	*color = lighten (*color, power);
	color++;
	*color = lighten (*color, power);
	color++;
	*color = lighten (*color, power);
	color++;
	*color = lighten (*color, power);
}



static void
genline (int id, float param, GMUnitPointer * l, int rx, int ry)
{
	int     i;

	switch (id) {
	case GML_HLINE:
		for (i = 0; i < 512; i++) {
			l[i].x = ((float) i * rx) / 512.0f;
			l[i].y = param;
			l[i].angle = M_PI / 2.0f;
		}
		return;
	case GML_VLINE:
		for (i = 0; i < 512; i++) {
			l[i].y = ((float) i * ry) / 512.0f;
			l[i].x = param;
			l[i].angle = 0.0f;
		}
		return;
	case GML_CIRCLE:
		for (i = 0; i < 512; i++) {
			float   cosa, sina;

			l[i].angle = 2.0f * M_PI * (float) i / 512.0f;
			cosa = param * cos (l[i].angle);
			sina = param * sin (l[i].angle);
			l[i].x = ((float) rx / 2.0f) + cosa;
			l[i].y = (float) ry / 2.0f + sina;
		}
		return;
	case GML_HEART:
		/* NullPlayer port: the classic heart curve, point i placed where the circle's
		   point i is (t = angle + pi/2), so the scope morphs cleanly between the two,
		   and pushed by the waveform along the circle's direction. */
		for (i = 0; i < 512; i++) {
			float   t, hx, hy, s = param / 16.0f;

			l[i].angle = 2.0f * M_PI * (float) i / 512.0f;
			t = l[i].angle + M_PI / 2.0f;
			hx = 16.0f * powf (sinf (t), 3.0f);
			hy = 13.0f * cosf (t) - 5.0f * cosf (2.0f * t) - 2.0f * cosf (3.0f * t) - cosf (4.0f * t);
			l[i].x = (float) rx / 2.0f + s * hx;
			l[i].y = (float) ry / 2.0f - s * (hy + 2.5f);
		}
		return;
	case GML_PENTAGRAM:
		/* NullPlayer port: a point-up five-pointed star drawn in one stroke, each
		   point jumping two corners on (144 degrees), the waveform pushing each
		   edge along its normal. */
		for (i = 0; i < 512; i++) {
			int     k = i * 5 / 512;
			float   t = (float) i * 5.0f / 512.0f - (float) k;
			float   a0 = -M_PI / 2.0f + k * 4.0f * M_PI / 5.0f;
			float   a1 = a0 + 4.0f * M_PI / 5.0f;
			float   x0 = param * cosf (a0), y0 = param * sinf (a0);
			float   x1 = param * cosf (a1), y1 = param * sinf (a1);

			l[i].x = (float) rx / 2.0f + x0 + t * (x1 - x0);
			l[i].y = (float) ry / 2.0f + y0 + t * (y1 - y0);
			l[i].angle = atan2f (y1 - y0, x1 - x0) + M_PI / 2.0f;
		}
		return;
	}
}

static guint32 getcouleur (int mode)
{
	switch (mode) {
	case GML_RED:
		return (230 << (ROUGE * 8)) | (120 << (VERT * 8)) | (18 << (BLEU * 8));
	case GML_ORANGE_J:
		return (120 << (VERT * 8)) | (252 << (ROUGE * 8)) | (18 << (BLEU * 8));
	case GML_ORANGE_V:
		return (160 << (VERT * 8)) | (236 << (ROUGE * 8)) | (40 << (BLEU * 8));
	case GML_BLEUBLANC:
		return (40 << (BLEU * 8)) | (220 << (ROUGE * 8)) | (140 << (VERT * 8));
	case GML_VERT:
		return (200 << (VERT * 8)) | (80 << (ROUGE * 8)) | (18 << (BLEU * 8));
	case GML_BLEU:
		return (250 << (BLEU * 8)) | (30 << (VERT * 8)) | (80 << (ROUGE * 8));
	case GML_ROSE:
		return (250 << (ROUGE * 8)) | (70 << (VERT * 8)) | (150 << (BLEU * 8));
	case GML_CRIMSON:
		return (235 << (ROUGE * 8)) | (25 << (VERT * 8)) | (30 << (BLEU * 8));
	case GML_BLACK:
		return (16 << (BLEU * 8)) | (16 << (VERT * 8)) |  (16 << (ROUGE * 8));
	}
	return 0;
}

void
goom_lines_set_res (GMLine * gml, int rx, int ry)
{
	if (gml != NULL) {
		gml->screenX = rx;
		gml->screenY = ry;

		genline (gml->IDdest, gml->param, gml->points2, rx, ry);
	}
}


static void
goom_lines_move (GMLine * l)
{
	int     i;
	unsigned char *c1, *c2;

	for (i = 0; i < 512; i++) {
		l->points[i].x = (l->points2[i].x + 39.0f * l->points[i].x) / 40.0f;
		l->points[i].y = (l->points2[i].y + 39.0f * l->points[i].y) / 40.0f;
		l->points[i].angle =
			(l->points2[i].angle + 39.0f * l->points[i].angle) / 40.0f;
	}

	c1 = (unsigned char *) &l->color;
	c2 = (unsigned char *) &l->color2;
	for (i = 0; i < 4; i++) {
		int     cc1, cc2;

		cc1 = *c1;
		cc2 = *c2;
		*c1 = (unsigned char) ((cc1 * 63 + cc2) >> 6);
		++c1;
		++c2;
	}

	l->power += l->powinc;
	if (l->power < 1.1f) {
		l->power = 1.1f;
		l->powinc = (float) (goom_irand(l->goomInfo->gRandom,20) + 10) / 300.0f;
	}
	if (l->power > 17.5f) {
		l->power = 17.5f;
		l->powinc = -(float) (goom_irand(l->goomInfo->gRandom,20) + 10) / 300.0f;
	}

	l->amplitude = (99.0f * l->amplitude + l->amplitudeF) / 100.0f;
}

void
goom_lines_switch_to (GMLine * gml, int IDdest,
											float param, float amplitude, int col)
{
	genline (IDdest, param, gml->points2, gml->screenX, gml->screenY);
	gml->IDdest = IDdest;
	gml->param = param;
	gml->amplitudeF = amplitude;
	gml->color2 = getcouleur (col);
}

GMLine *
goom_lines_init (PluginInfo *goomInfo, int rx, int ry,
		 int IDsrc, float paramS, int coulS,
		 int IDdest, float paramD, int coulD)
{
	GMLine *l = (GMLine *) malloc (sizeof (GMLine));

	l->goomInfo = goomInfo;
	
	l->points = (GMUnitPointer *) malloc (512 * sizeof (GMUnitPointer));
	l->points2 = (GMUnitPointer *) malloc (512 * sizeof (GMUnitPointer));
	l->nbPoints = 512;

	l->IDdest = IDdest;
	l->param = paramD;
	
	l->amplitude = l->amplitudeF = 1.0f;

	genline (IDsrc, paramS, l->points, rx, ry);
	genline (IDdest, paramD, l->points2, rx, ry);

	l->color = getcouleur (coulS);
	l->color2 = getcouleur (coulD);

	l->screenX = rx;
	l->screenY = ry;

	l->power = 0.0f;
	l->powinc = 0.01f;

	goom_lines_switch_to (l, IDdest, paramD, 1.0f, coulD);

	return l;
}

void
goom_lines_free (GMLine ** l)
{
	free ((*l)->points);
	free ((*l)->points2);
	free (*l);
	l = NULL;
}

void goom_lines_draw (PluginInfo *plug, GMLine * line, gint16 data[512], Pixel *p)
{
	if (line != NULL) {
		int     i, x1, y1;
		guint32 color = line->color;
		GMUnitPointer *pt = &(line->points[0]);

		float   cosa = cos (pt->angle) / 1000.0f;
		float   sina = sin (pt->angle) / 1000.0f;

		lightencolor (&color, line->power);

		x1 = (int) (pt->x + cosa * line->amplitude * data[0]);
		y1 = (int) (pt->y + sina * line->amplitude * data[0]);

		for (i = 1; i < 512; i++) {
			int     x2, y2;
			GMUnitPointer *pt = &(line->points[i]);

			float   cosa = cos (pt->angle) / 1000.0f;
			float   sina = sin (pt->angle) / 1000.0f;

			x2 = (int) (pt->x + cosa * line->amplitude * data[i]);
			y2 = (int) (pt->y + sina * line->amplitude * data[i]);

			plug->methods.draw_line (p, x1, y1, x2, y2, color, line->screenX, line->screenY);

			x1 = x2;
			y1 = y2;
		}
		goom_lines_move (line);
	}
}
