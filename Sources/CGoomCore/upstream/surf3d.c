#include "surf3d.h"
#include "goom_filters.h"
#include "goom_plugin_info.h"
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <string.h>

grid3d *grid3d_new (int sizex, int defx, int sizez, int defz, v3d center) {
	int x = defx;
	int y = defz;
	grid3d *g = malloc (sizeof(grid3d));
	surf3d *s = &(g->surf);
	g->proj = malloc (x*y*sizeof(v2d));
	s->nbvertex = x*y;
	s->vertex = malloc (x*y*sizeof(v3d));
	s->svertex = malloc (x*y*sizeof(v3d));
	s->center = center;

	g->defx=defx;
	g->sizex=sizex;
	g->defz=defz;
	g->sizez=sizez;
	g->shape=GRID3D_SHAPE_TENTACLE;
	g->phase=0.0f;
	g->twist=0.0f;
	g->twistCur=0.0f;
	g->drawMode=GRID3D_DRAW_LEGACY;
	g->drawCnt=0;

	while (y) {
		--y;
		x = defx;
		while (x) {
			--x;
			s->vertex[x+defx*y].x = (float)(x-defx/2)*sizex/defx;
			s->vertex[x+defx*y].y = 0;
			s->vertex[x+defx*y].z = (float)(y-defz/2)*sizez/defz;
		}
	}
	return g;
}

void grid3d_draw (PluginInfo *plug, grid3d *g, int color, int colorlow,
	int dist, float flow, Pixel *buf, Pixel *back, int W,int H) {

	int x;
	v2d v2,v2x;
	v2d *v2_array = g->proj;
	/* en mode strobe, buf (source du zoom) ne recoit rien la plupart
	 * du temps, puis une rafale de GRID3D_STROBE_BURST frames avec la
	 * couleur vive : le zoom reprend un snapshot net a chaque periode
	 * au lieu d'une piste continue qui decroit. back (l'ecran) reste
	 * trace a chaque frame, sinon la forme clignoterait a l'ecran */
	int bufColor;
	int drawBuf;
	int drawBack;
	if (g->drawMode == GRID3D_DRAW_STROBE) {
		if (g->drawCnt >= GRID3D_STROBE_PERIOD) {
			g->drawCnt = 0;        /* debut d'une nouvelle rafale */
		}
		if (g->drawCnt < GRID3D_STROBE_BURST) {
			bufColor = color;      /* rafale : couleur vive vers buf */
			drawBuf = 1;
		}
		else {
			bufColor = 0;          /* inutilise ce frame */
			drawBuf = 0;           /* silence : rien vers buf */
		}
		drawBack = 1;              /* l'ecran reste trace a chaque frame */
		g->drawCnt++;
	}
	else if (g->drawMode == GRID3D_DRAW_ON_GOOM) {
		/* la fenetre est calee sur l'effet lignes (goom_core.c :
		 * timeSinceLastGoom < 5) : l'effet claque avec le goom puis
		 * s'eteint - buf et back suivent la meme fenetre, l'effet
		 * entier disparait hors goom */
		if (plug->sound.timeSinceLastGoom < GRID3D_ONGOOM_FRAMES) {
			bufColor = color;
			drawBuf = 1;
			drawBack = 1;
		}
		else {
			bufColor = 0;
			drawBuf = 0;
			drawBack = 0;
		}
	}
	else {
		bufColor = colorlow;       /* legacy : colorlow a chaque frame */
		drawBuf = 1;
		drawBack = 1;
	}
	v3d_to_v2d(g->surf.svertex, g->surf.nbvertex, W, H, dist, v2_array);

	for (x=0;x<g->defx;x++) {
		int z;
		v2x = v2_array[x];
		/* drag the first vertex of the column with the transformation
		 * buffer's velocity field */
		if ((flow != 0.0f)
				&& (v2x.x != -666) && (v2x.y != -666)) {
			float fvx, fvy;
			zoomFilterGetVelocity (plug, v2x.x, v2x.y, &fvx, &fvy);
			v2x.x += fvx * flow;
			v2x.y += fvy * flow;
		}

		for (z=1;z<g->defz;z++) {
			v2 = v2_array[z*g->defx + x];
			/* drag this vertex once, so segments sharing it stay connected */
			if ((flow != 0.0f)
					&& ((v2.x != -666) || (v2.y != -666))) {
				float fvx, fvy;
				zoomFilterGetVelocity (plug, v2.x, v2.y, &fvx, &fvy);
				v2.x += fvx * flow;
				v2.y += fvy * flow;
			}
			if (((v2.x != -666) || (v2.y!=-666))
					&& ((v2x.x != -666) || (v2x.y!=-666))) {
				if (drawBuf)
					plug->methods.draw_line (buf,v2x.x,v2x.y,v2.x,v2.y, bufColor, W, H);
				if (drawBack)
					plug->methods.draw_line (back,v2x.x,v2x.y,v2.x,v2.y, color, W, H);
			}
			v2x = v2;
		}
	}

	/* les formes en surface (ripple, tunnel) tracent aussi la direction
	 * x : les anneaux et les fronts d'onde sont orientes selon x, la
	 * colonne seule les ferait passer pour des tentacules */
	if (g->shape != GRID3D_SHAPE_TENTACLE) {
		int z, x2;
		for (z=0;z<g->defz;z++) {
			v2x = v2_array[z*g->defx];
			if ((flow != 0.0f)
					&& (v2x.x != -666) && (v2x.y != -666)) {
				float fvx, fvy;
				zoomFilterGetVelocity (plug, v2x.x, v2x.y, &fvx, &fvy);
				v2x.x += fvx * flow;
				v2x.y += fvy * flow;
			}
			for (x2=1;x2<g->defx;x2++) {
				v2 = v2_array[z*g->defx + x2];
				if ((flow != 0.0f)
						&& ((v2.x != -666) || (v2.y != -666))) {
					float fvx, fvy;
					zoomFilterGetVelocity (plug, v2.x, v2.y, &fvx, &fvy);
					v2.x += fvx * flow;
					v2.y += fvy * flow;
				}
				if (((v2.x != -666) || (v2.y!=-666))
						&& ((v2x.x != -666) || (v2x.y!=-666))) {
				if (drawBuf)
					plug->methods.draw_line (buf,v2x.x,v2x.y,v2.x,v2.y, bufColor, W, H);
				if (drawBack)
					plug->methods.draw_line (back,v2x.x,v2x.y,v2.x,v2.y, color, W, H);
				}
				v2x = v2;
			}
			/* fermer l'anneau : relier le dernier point au premier,
			 * sinon le tube reste ouvert entre gx=defx-1 et gx=0 */
			if (g->shape == GRID3D_SHAPE_TUNNEL) {
				v2 = v2_array[z*g->defx];
				if ((v2.x != -666) || (v2.y != -666)) {
					float fvx, fvy;
					zoomFilterGetVelocity (plug, v2.x, v2.y, &fvx, &fvy);
					v2.x += fvx * flow;
					v2.y += fvy * flow;
				}
				if (((v2.x != -666) || (v2.y!=-666))
						&& ((v2x.x != -666) || (v2x.y!=-666))) {
					if (drawBuf)
						plug->methods.draw_line (buf,v2x.x,v2x.y,v2.x,v2.y, bufColor, W, H);
					if (drawBack)
						plug->methods.draw_line (back,v2x.x,v2x.y,v2.x,v2.y, color, W, H);
				}
			}
		}
	}
}

void surf3d_rotate (surf3d *s, float angle) {
	int i;
	float cosa;
	float sina;
	SINCOS(angle,sina,cosa);
	for (i=0;i<s->nbvertex;i++) {
		Y_ROTATE_V3D(s->vertex[i],s->svertex[i],cosa,sina);
	}
}

void surf3d_translate (surf3d *s) {
	int i;
	for (i=0;i<s->nbvertex;i++) {
		TRANSLATE_V3D(s->center,s->svertex[i]);
	}
}

void grid3d_update (grid3d *g, float angle, float *vals, float *vals2, float dist) {
	int i;
	float cosa;
	float sina;
	surf3d *s = &(g->surf);
	v3d cam = s->center;
	cam.z += dist;

	SINCOS((angle/4.3f),sina,cosa);
	cam.y += sina*2.0f;
	SINCOS(angle,sina,cosa);

	if (g->shape == GRID3D_SHAPE_RIPPLE) {
		/* onde radiale qui se propage depuis le centre de la feuille :
		 * recompute la position de base a partir de la grille (sizex/
		 * sizez) et non des vertex, sinon la frame precedante pollue
		 * la suivante ; la phase avance a chaque update.
		 * trois composantes superposees pour que la feuille danse sur
		 * les deux axes : onde x par colonne (gauche), onde z par
		 * ligne (droite, vals2), et onde radiale centrale dont le
		 * nombre d'onde augmente avec l'energie - fort = hue, calme =
		 * plat. Amortissement doux pour que toute la feuille bouge */
		float halfx = (float)g->sizex * 0.5f;
		float halfz = (float)g->sizez * 0.5f;
		float energy = 0.0f;
		float wnum;
		if (vals) {
			int k;
			for (k=0;k<g->defx;k++)
				energy += vals[k] < 0.0f ? -vals[k] : vals[k];
			energy /= g->defx;
		}
		/* nombre d'onde radial : 5 calme -> 12 fort, le relief suit la
		 * musique au lieu d'un gain global uniforme */
		wnum = 5.0f + energy * 0.3f;
		if (wnum > 12.0f)
			wnum = 12.0f;
		for (i=0;i<s->nbvertex;i++) {
			int gx = i % g->defx;
			int gz = i / g->defx;
			float dx = (float)(gx - g->defx/2) / g->defx * g->sizex;
			float dz = (float)(gz - g->defz/2) / g->defz * g->sizez;
			float r = sqrtf(dx*dx + dz*dz) / (halfx + halfz) * 2.0f;
			float ax = vals ? vals[gx] : 0.0f;
			float az = vals2 ? vals2[gz] : 0.0f;
			s->vertex[i].x = dx;
			s->vertex[i].z = dz;
			/* onde x + onde z + onde radiale : les trois se croisent,
		 * la superposition fait vivre la surface en diagonale */
			s->vertex[i].y = ax * sinf(dz*0.08f - g->phase)
				+ az * sinf(dx*0.08f + g->phase)
				+ (ax + az) * 0.5f * sinf(r*wnum - g->phase)
					* expf(-r*0.6f);
		}
	}
	else if (g->shape == GRID3D_SHAPE_TUNNEL) {
		/* tunnel : anneaux perpendiculaires a l'axe z (l'axe de vue),
		 * empiles en profondeur avec un leger cone. Pre-rotation par
		 * -angle : la boucle commune reapplique +angle, le tunnel reste
		 * ainsi aligne sur la vue au lieu de basculer sur le cote ; il
		 * tourne autour de son propre axe via phase. Centre des anneaux
		 * sur l'axe de vue : -cam.y annule la translation. */
		/* torsion elastique : g->twist (cible) et g->twistCur (valeur
		 * relaxee) sont pilotes par le FX ; l'anneau profond vise la
		 * cible, l'avant suit avec un retard lineaire - la difference
		 * de vitesse angulaire entre anneaux fait la torsion apparente,
		 * qui apparait et disparait en douceur sans jamais sauter.
		 * displacement radial par colonne depuis la forme d'onde
		 * (signee) : le tunnel respire avec la musique ; rayon borne
		 * pour ne pas traverser l'axe */
		float cy = -cam.y;
		float cz = -cam.z;
		/* relaxation elastique : retard du premier ordre, amortit la
		 * cible et garantit qu'aucun changement n'apparait d'un coup */
		g->twistCur += (g->twist - g->twistCur) * 0.03f;
		for (i=0;i<s->nbvertex;i++) {
			int gx = i % g->defx;
			int gz = i / g->defx;
			/* cible en espace vue : anneau de rayon croissant (cone)
			 * centre sur l'axe, profond en z, tourne par phase */
			float dfrac = ((float)gz + 0.5f) / g->defz;
			float theta = ((float)gx + 0.5f) / g->defx * 6.2832f
				+ g->phase + g->twistCur * dfrac;
			float tz = 30.0f + dfrac * 120.0f;
			float tr = 35.0f + tz * 0.10f;
			if (vals)
				tr += vals[gx];
			if (tr < 8.0f)
				tr = 8.0f;
			float tx = tr * cosf(theta);
			float tyy = tr * sinf(theta);
			/* svertex = R(b)*vertex + cam ou b = pi/2 - angle (le site
			 * d'appel Y_ROTATE_V3D passe cosa,sina inverses). Pour poser
			 * svertex = cible : vertex = R(-b)*(cible - cam), le tunnel
			 * reste coaxial quelle que soit la rotation camera */
			float dx = tx;
			float dyy = tyy + cy;
			float dz = tz + cz;
			s->vertex[i].x = dx * sina + dz * cosa;
			s->vertex[i].y = dyy;
			s->vertex[i].z = -dx * cosa + dz * sina;
		}
	}
	else if (g->mode==0) {
		if (vals)
			for (i=0;i<g->defx;i++)
				s->vertex[i].y = s->vertex[i].y*0.2 + vals[i]*0.8;

		for (i=g->defx;i<s->nbvertex;i++) {
			s->vertex[i].y *= 0.255f;
			s->vertex[i].y += (s->vertex[i-g->defx].y * 0.777f);
		}
	}

	if (g->shape != GRID3D_SHAPE_TENTACLE)
		g->phase += 0.04f;

	for (i=0;i<s->nbvertex;i++) {
		Y_ROTATE_V3D(s->vertex[i],s->svertex[i],cosa,sina);
		TRANSLATE_V3D(cam,s->svertex[i]);
	}
}
