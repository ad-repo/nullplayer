/*
 * Modified for NullPlayer, 2026-11-06 (LGPL-2.1 section 2(a)):
 * adds the Spiral, Vortex, Flower, Heart and Pentagram zoom modes to zoomVector and
 * raises the "Zoom Mode" parameter maximum to match.
 * Upstream: https://github.com/j3k0/goom at e4fc3550457cf5a5b194fa9ec8219d3f1e78acc7.
 */
// --- CHUI EN TRAIN DE SUPPRIMER LES EXTERN RESOLX ET C_RESOLY ---

/* filter.c version 0.7
* contient les filtres applicable a un buffer
* creation : 01/10/2000
*  -ajout de sinFilter()
*  -ajout de zoomFilter()
*  -copie de zoomFilter() en zoomFilterRGB(), gerant les 3 couleurs
*  -optimisation de sinFilter (utilisant une table de sin)
*	-asm
*	-optimisation de la procedure de generation du buffer de transformation
*		la vitesse est maintenant comprise dans [0..128] au lieu de [0..100]
*/

/* #define _DEBUG_PIXEL */

#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <stdio.h>
#include <inttypes.h>

#include "goom_filters.h"
#include "goom_graphic.h"
#include "goom_tools.h"
#include "goom_plugin_info.h"
#include "goom_fx.h"
#include "v3d.h"

/* TODO : MOVE THIS AWAY !!! */
/* jeko: j'ai essayer de le virer, mais si on veut les laisser inline c'est un peu lourdo... */
static inline void setPixelRGB (PluginInfo *goomInfo, Pixel *buffer, Uint x, Uint y, Color c)
{
    Pixel i;
    
    i.channels.b = c.b;
    i.channels.g = c.v;
    i.channels.r = c.r;
    *(buffer + (x + y * goomInfo->screen.width)) = i;
}

static inline void setPixelRGB_ (Pixel *buffer, Uint x, Color c)
{
    buffer[x].channels.r = c.r;
    buffer[x].channels.g = c.v;
    buffer[x].channels.b = c.b;
}

static inline void getPixelRGB (PluginInfo *goomInfo, Pixel *buffer, Uint x, Uint y, Color * c)
{
    Pixel i = *(buffer + (x + y * goomInfo->screen.width));
    c->b = i.channels.b;
    c->v = i.channels.g;
    c->r = i.channels.r;
}

static inline void getPixelRGB_ (Pixel *buffer, Uint x, Color * c)
{
    Pixel i = *(buffer + x);
    c->b = i.channels.b;
    c->v = i.channels.g;
    c->r = i.channels.r;
}
/* END TODO */


/* DEPRECATED */
// retourne x>>s , en testant le signe de x
//#define ShiftRight(_x,_s) (((_x)<0) ? -(-(_x)>>(_s)) : ((_x)>>(_s)))
//#define EFFECT_DISTORS 4
//#define EFFECT_DISTORS_SL 2
//#define INTERLACE_ADD 9
//#define INTERLACE_AND 0xf
/* END DEPRECATED */

#define BUFFPOINTNB 16
#define BUFFPOINTNBF 16.0f
#define BUFFPOINTMASK 0xffff

#define sqrtperte 16
/* faire : a % sqrtperte <=> a & pertemask */
#define PERTEMASK 0xf
/* faire : a / sqrtperte <=> a >> PERTEDEC */
#define PERTEDEC 4

/* pure c version of the zoom filter */
static void c_zoom (Pixel *expix1, Pixel *expix2, unsigned int prevX, unsigned int prevY, signed int *brutS, signed int *brutD, int buffratio, int precalCoef[BUFFPOINTNB][BUFFPOINTNB], const ZoomBlend *blend);

/* simple wrapper to give it the same proto than the others */
void zoom_filter_c (int sizeX, int sizeY, Pixel *src, Pixel *dest, int *brutS, int *brutD, int buffratio, int precalCoef[16][16], const ZoomBlend *blend) {
    c_zoom(src, dest, sizeX, sizeY, brutS, brutD, buffratio, precalCoef, blend);
}

static void generatePrecalCoef (int precalCoef[BUFFPOINTNB][BUFFPOINTNB]);


typedef struct _ZOOM_FILTER_FX_WRAPPER_DATA {
    
    PluginParam enabled_bp;
    PluginParam freeze_bp;
    PluginParameters params;
    /* writable kaleido controls */
    PluginParam kaleidoMode_p;
    PluginParam kaleidoStartP_p;
    PluginParam kaleidoStopP_p;
    PluginParam kaleidoManual_bp;
    PluginParam kaleidoManualN_p;
    PluginParam kaleidoManualAngle_p;
    PluginParam foldTransition_p;
    PluginParam wipeFrames_p;
    PluginParam wipeRing_p;
    PluginParam wipeWobble_p;
    /* read-only monitors of the applied state */
    PluginParam zoomMode_p;
    PluginParam vitesse_p;
    PluginParam reverse_p;
    PluginParam middleX_p;
    PluginParam middleY_p;
    PluginParam noisify_p;
    PluginParam waveFx_p;
    PluginParam hypercosFx_p;
    
    unsigned int *coeffs, *freecoeffs;
    
    signed int *brutS, *freebrutS; /* source */
    signed int *brutD, *freebrutD; /* dest */
    signed int *brutT, *freebrutT; /* temp (en cours de generation) */
    
    guint32 zoom_width;
    
    unsigned int prevX, prevY;
    
    float general_speed;
    int reverse; /* reverse the speed */
    char theMode;
    int waveEffect;
    int hypercosEffect;
    int vPlaneEffect;
    int hPlaneEffect;
    char noisify;
    int middleX, middleY;
    
    int mustInitBuffers;
    int interlace_start;
    
    /** modif by jeko : fixedpoint : buffration = (16:16) (donc 0<=buffration<=2^16) */
    int buffratio;
    int *firedec;

    /* flux percu : pas de ramp de cette frame (buffratio avant ramp) et
     * validite du terme de sweep (0 aux vraies discontinuites seulement) */
    int prevRatio;
    int sweepValid;
    
    /** modif d'optim by Jeko : precalcul des 4 coefs resultant des 2 pos */
    int precalCoef[BUFFPOINTNB][BUFFPOINTNB];
    
    /** calculatePXandPY statics */
    int wave;
    int wavesp;

    /** kaleidoscope addon (kaleidoEffect) : eventail de 2 miroirs precalcule */
    int     kaleidoEffect;          /* addon actif (1 = plier l'espace source) */
    int     kaleidoN;              /* nombre de secteurs (0 = non calcule) */
    float   kaleidoAngle;          /* angle du 1er miroir (radians) */
    float   kaleidoN1x, kaleidoN1y;    /* normale cote chambre du 1er miroir */
    float   kaleidoN2x, kaleidoN2y;    /* normale cote chambre du 2eme miroir */

    /** jauge des tables brutS/brutD : le pli dans le referentiel duquel
     * elles echantillonnent. Commit au swap, peut donc retarder d'une
     * transition sur la config vivante ci-dessus. */
    int     gaugeActive;           /* 1 = les tables sont en jauge pliee */
    int     gaugeMidx, gaugeMidy; /* sommet du pli de la jauge : le moteur
                                   * peut deplacer middleX dans le meme
                                   * changement de config qui eteint le pli
                                   * (tirage "changement de milieu" du cycle
                                   * goom) ; les projections (de-pli du bake,
                                   * reprojection du flux) doivent se faire
                                   * autour du sommet que le mandala montrait. */
    int     gaugeN;                /* nombre de secteurs de la jauge */
    float   gaugeAngle;            /* angle du 1er miroir de la jauge */
    float   gaugeN1x, gaugeN1y;    /* normales de la jauge (meme convention) */
    float   gaugeN2x, gaugeN2y;

    /** transition geometrique (wipe) en cours : selection spatiale entre
     * brutS (ancienne carte) et brutD (nouvelle) au lieu du lerp
     * buffratio. Demarre au swap de la nouvelle table, la jauge se commit
     * a la fin (beta=1 partout => brutS == brutD en jauge cible). */
    int     wipeActive;
    int     wipeMode;              /* 1 = WIPE_RADIUS, 2 = WIPE_SEAMS */
    int     wipeFrameK;            /* kernel calls rendered since the swap */
    float   wipeProgress;          /* c in [0,1] */
    int     wipeFrames;            /* duree en frames (param Wipe Frames) */
    float   wipeRing;              /* bande douce en px (param Wipe Ring) */
    int     stampedGauge;        /* re-gauge pli->pli : sources = f_old(f_new(p)),
                                  * le flux de base se lit cote brutD */
    float   wipeHalfDiag;          /* 0.5*sqrt(prevX^2+prevY^2) au demarrage */
    ZoomBlend wipeBlend;           /* ce que recoivent les noyaux */
    unsigned char *wipeLuma;       /* champ de couleur invariant (resx*resy) */
} ZoomFilterFXWrapperData;



/* Kaleidoscope : precalcul des 2 miroirs du secteur fondamental.
 * Secteur = chambre entre la droite d'angle foldAngle et celle d'angle
 * foldAngle + pi/N. Refleter alternativement sur les 2 miroirs ramene
 * tout point dans la chambre en <= N reflexions (groupe diedral 2N). */
static void kaleidoPrecompute (ZoomFilterFXWrapperData *data, int foldCount, float foldAngle)
{
    float d = (float)M_PI / foldCount;

    data->kaleidoN = foldCount;
    data->kaleidoAngle = foldAngle;

    /* normales cote chambre : miroir 1 (droite d'angle a) */
    data->kaleidoN1x = -sinf (foldAngle);
    data->kaleidoN1y = cosf (foldAngle);
    /* miroir 2 (droite d'angle a + pi/N) */
    data->kaleidoN2x = sinf (foldAngle + d);
    data->kaleidoN2y = -cosf (foldAngle + d);
}

/* Kaleidoscope : replie (X, Y) dans la chambre fondamentale definie par les
 * 2 normales (cote chambre) n1, n2, en au plus 2*foldCount+2 reflexions.
 * zoomVector travaille deja en coordonnees relatives au milieu, le centre du
 * pli est donc (0, 0). Rend le point replie via (fx, fy).
 * Si g != NULL, il recoit en plus l'image lineaire du secteur, en 2x2 par
 * colonnes (g[0],g[1] = image de (1,0)) : p = g.f. Le pli l'accumule en
 * g <- g.R a chaque reflexion, soit g = R1...Rj = (Rj...R1)-1 : re-projeter
 * un vecteur de la chambre dans le secteur du pixel revient a multiplier
 * par g. Sert au flux percu (zoomFilterGetVelocity) et au re-gauge. */
static inline void kaleidoFoldNormals (float n1x, float n1y, float n2x, float n2y, int foldCount,
                                       float X, float Y, float *fx, float *fy, float *g)
{
    int i;

    if (g) {
        g[0] = 1.0f; g[1] = 0.0f;
        g[2] = 0.0f; g[3] = 1.0f;
    }

    for (i = 0; i < 2 * foldCount + 2; i++) {
        float d1 = X * n1x + Y * n1y;
        float d2 = X * n2x + Y * n2y;

        if (d1 >= 0.0f && d2 >= 0.0f)
            break;              /* dans la chambre : fini */
        if (d1 < 0.0f) {
            /* reflexion p' = p - 2 (p.n) n */
            X -= 2.0f * d1 * n1x;
            Y -= 2.0f * d1 * n1y;
            if (g) {
                /* g <- g.R1 : R agit sur les lignes de g */
                float a = 2.0f * (g[0] * n1x + g[2] * n1y);
                float b = 2.0f * (g[1] * n1x + g[3] * n1y);
                g[0] -= a * n1x; g[2] -= a * n1y;
                g[1] -= b * n1x; g[3] -= b * n1y;
            }
        }
        else {
            X -= 2.0f * d2 * n2x;
            Y -= 2.0f * d2 * n2y;
            if (g) {
                float a = 2.0f * (g[0] * n2x + g[2] * n2y);
                float b = 2.0f * (g[1] * n2x + g[3] * n2y);
                g[0] -= a * n2x; g[2] -= a * n2y;
                g[1] -= b * n2x; g[3] -= b * n2y;
            }
        }
    }

    *fx = X;
    *fy = Y;
}

static inline void kaleidoFold (ZoomFilterFXWrapperData *data, float X, float Y,
                                float *fx, float *fy, float *g)
{
    kaleidoFoldNormals (data->kaleidoN1x, data->kaleidoN1y,
                        data->kaleidoN2x, data->kaleidoN2y, data->kaleidoN,
                        X, Y, fx, fy, g);
}

static inline v2g zoomVector(ZoomFilterFXWrapperData *data, float X, float Y)
{
    v2g vecteur;
    float vx, vy;
    float fx = X, fy = Y;   /* point replie (identique si l'addon est inactif) */
    float sq_dist;

    /* Kaleidoscope addon : plie l'espace AVANT tout le reste, puis on
     * evalue le mode de base sur le point replie. Comme fold(g.p) == fold(p)
     * pour toute image diedrale g, chaque image miroir echantillonne la
     * meme source -> la symetrie est preservee quel que soit le mode. */
    if (data->kaleidoEffect && data->kaleidoN > 0)
        kaleidoFold (data, X, Y, &fx, &fy, NULL);

    sq_dist = fx*fx + fy*fy;
    
    /*    sx = (X < 0.0f) ? -1.0f : 1.0f;
    sy = (Y < 0.0f) ? -1.0f : 1.0f;
    */  
    float coefVitesse = (1.0f+ data->general_speed) / 50.0f;
    float spin = 0.0f;   /* NullPlayer port: rotation added to the radial move */
    
    // Effects
    
    /* Centralized FX */
    
    switch (data->theMode) {
        case CRYSTAL_BALL_MODE:
            coefVitesse -= (sq_dist-0.3f)/15.0f;
            break;
        case AMULETTE_MODE:
            coefVitesse += sq_dist * 3.5f;
            break;
        case WAVE_MODE:
            coefVitesse += sin(sq_dist*20.0f) / 100.0f;
            break;
        case SCRUNCH_MODE:
            coefVitesse += sq_dist / 10.0f;
            break;
            //case HYPERCOS1_MODE:
            break;
            //case HYPERCOS2_MODE:
            break;
            //case YONLY_MODE:
            break;
        case SPEEDWAY_MODE:
            coefVitesse *= 4.0f * Y;
            break;
        case SPIRAL_MODE:
            spin = 0.012f;
            break;
        case VORTEX_MODE:
            /* whirlpool: turns fastest at the eye */
            spin = fminf(0.0015f / (sq_dist + 0.05f), 0.025f);
            break;
        case FLOWER_MODE:
            /* five petals: the zoom speed rises and falls around the circle */
            coefVitesse += sinf(5.0f * atan2f(fy, fx)) * 0.012f;
            break;
        case HEART_MODE: {
            /* heart-shaped ripples: h is a "distance" whose level sets are hearts
             * (x^2 + (y - |x|)^2 = r^2, y up; screen Y grows downwards) */
            float hy = -fy - fabsf(fx);
            float h = sqrtf(fx*fx + hy*hy);
            coefVitesse += sinf(h * 12.0f) / 60.0f;
            break;
        }
        case PENTAGRAM_MODE: {
            /* star-shaped ripples: h scales the point-up pentagram outline through
             * (x, y), so its level sets are pentagrams. Fold the angle into half a
             * point (0 = tip, pi/5 = inner corner), then h = (n.p) / (n.tip) with n
             * the normal of the edge from the tip (1, 0) to the inner corner. */
            const float sector = 2.0f * (float)M_PI / 5.0f;
            const float inner = 0.381966f;   /* cos(2pi/5) / cos(pi/5) */
            const float ix = inner * 0.809017f, iy = inner * 0.587785f;
            const float nx = iy, ny = 1.0f - ix;   /* normal of (inner - tip) */
            float a = fmodf(atan2f(-fy, fx) - (float)M_PI / 2.0f + 4.0f * (float)M_PI, sector);
            float r = sqrtf(sq_dist);
            float fold = (float)M_PI / 5.0f - fabsf(a - (float)M_PI / 5.0f);
            float h = (nx * r * cosf(fold) + ny * r * sinf(fold)) / nx;
            coefVitesse += sinf(h * 14.0f) / 60.0f;
            break;
        }
        default:
            break;
    }
    
    if (coefVitesse < -2.01f)
        coefVitesse = -2.01f;
    if (coefVitesse > 2.01f)
        coefVitesse = 2.01f;
    vx = coefVitesse * fx - spin * fy;
    vy = coefVitesse * fy + spin * fx;
    
    /* Amulette 2 */
    // vx = X * tan(dist);
    // vy = Y * tan(dist);
    
    /* Rotate */
    //vx = (X+Y)*0.1;
    //vy = (Y-X)*0.1;
    
    
    // Effects adds-on
    
    /* Noise */
    if (data->noisify)
    {
        vx += (((float)random()) / ((float)RAND_MAX) - 0.5f) / 50.0f;
        vy += (((float)random()) / ((float)RAND_MAX) - 0.5f) / 50.0f;
    }
    
    /* Hypercos (evalue sur le point replie : symetrique pour l'addon) */
    if (data->hypercosEffect)
    {
        vx += sin(fy*10.0f)/120.0f;
        vy += sin(fx*10.0f)/120.0f;
    }

    /* H Plane */
    if (data->hPlaneEffect) vx += fy * 0.0025f * data->hPlaneEffect;

    /* V Plane */
    if (data->vPlaneEffect) vy += fx * 0.0025f * data->vPlaneEffect;
    
    /* TODO : Water Mode */
    //    if (data->waveEffect)

    /* Finish and avoid null displacement : sur le vecteur du mode de base
     * (mode + add-ons, qui ne depend que du point replie). Il reste donc
     * constant sur une orbite : les miroirs gardent des sources egales et
     * la symetrie du mandala ne casse pas sur les coutures. */
    {
        float min = 2.0f / ((float)data->prevX * BUFFPOINTNBF);
        if (fabs(vx) < min) vx = (vx < 0.0f) ? -min : min;
        if (fabs(vy) < min) vy = (vy < 0.0f) ? -min : min;
    }

    /* Kaleidoscope addon : deplacement du pli lui-meme. Le noyau
     * echantillonne la source en (X - vx) : ajouter (X - fx) fait lire
     * dans le secteur replie, la ou le mode de base a ete evalue. */
    if (data->kaleidoEffect && data->kaleidoN > 0) {
        vx += X - fx;
        vy += Y - fy;
    }

    vecteur.x = vx;
    vecteur.y = vy;
    
    return vecteur;
}


/*
 * Makes a stripe of a transform buffer (brutT)
 *
 * The transform is (in order) :
 * Translation (-data->middleX, -data->middleY)
 * Homothetie (Center : 0,0   Coeff : 2/data->prevX)
 */
static void makeZoomBufferStripe(ZoomFilterFXWrapperData * data, int INTERLACE_INCR)
{
    // Position of the pixel to compute in pixmap coordinates
    Uint x, y;
    /* un pas de 0 (resy petit) ne genérerait aucune ligne : bouclage infini */
    if (INTERLACE_INCR < 1) INTERLACE_INCR = 1;
    // Where (verticaly) to stop generating the buffer stripe
    int maxEnd = (data->interlace_start + INTERLACE_INCR);
    // Ratio from pixmap to normalized coordinates
    float ratio = 2.0f/((float)data->prevX);
    // Ratio from normalized to virtual pixmap coordinates
    float inv_ratio = BUFFPOINTNBF/ratio;
    // Y position of the pixel to compute in normalized coordinates
    float Y = ((float)(data->interlace_start - data->middleY)) * ratio;
    
    maxEnd = data->prevY;
    if (maxEnd > (data->interlace_start + INTERLACE_INCR))
        maxEnd = (data->interlace_start + INTERLACE_INCR);
    
    for (y = data->interlace_start; (y < data->prevY) && ((signed int)y<maxEnd); y++) {
        Uint premul_y_prevX = y * data->prevX * 2;
        float X = - ((float)data->middleX) * ratio;
        for (x = 0; x < data->prevX; x++)
        {
            v2g vector = zoomVector (data, X, Y);

            /* Quantification avec biais de 0.25 : pour un pli "rationnel"
             * (miroirs sur la grille pixel) les valeurs mathematiques
             * tombent sur des entieres ou demi-unites, et la troncature
             * simple perd le bit de poids faible au bruit float entre
             * p et g.p — les miroirs liraient des sources decalees d'un
             * seizieme de pixel. Biaisee d'un quart, la meme quantification
             * sort le meme entier pour toute l'orbite. */
            data->brutT[premul_y_prevX] = ((int)((X-vector.x)*inv_ratio + 0.25f)+((int)(data->middleX*BUFFPOINTNB)));
            data->brutT[premul_y_prevX+1] = ((int)((Y-vector.y)*inv_ratio + 0.25f)+((int)(data->middleY*BUFFPOINTNB)));
            /* Kaleidoscope : les reflexions peuvent envoyer la source hors
             * buffer, et les noyaux ne testent que la borne superieure
             * (px >= ax -> noir) : on borne des deux cotes pour garder les
             * noyaux inchanges et eviter les trous noirs aux bords. */
            {
                int sx = data->brutT[premul_y_prevX];
                int sy = data->brutT[premul_y_prevX+1];
                int maxX = ((data->prevX - 1) << PERTEDEC) - 1;
                int maxY = ((data->prevY - 1) << PERTEDEC) - 1;
                if (sx < 0) sx = 0;
                else if (sx > maxX) sx = maxX;
                if (sy < 0) sy = 0;
                else if (sy > maxY) sy = maxY;
                data->brutT[premul_y_prevX] = sx;
                data->brutT[premul_y_prevX+1] = sy;
            }
            premul_y_prevX += 2;
            X += ratio;
        }
        Y += ratio;
    }
    data->interlace_start += INTERLACE_INCR;
    /* y = premiere ligne non generee : fini seulement quand elles le sont
     * toutes (l'ancien test prevY-1 sautait la derniere ligne quand un pas
     * finissait dessus, laissant une ligne de l'ancienne table). */
    if (y >= data->prevY) data->interlace_start = -1;
}


/*
 * calculer px et py en fonction de x,y,middleX,middleY et theMode
 * px et py indique la nouvelle position (en sqrtperte ieme de pixel)
 * (valeur * 16)
 
 inline void calculatePXandPY (PluginInfo *goomInfo, ZoomFilterFXWrapperData *data, int x, int y, int *px, int *py)
 {
     if (data->theMode == WATER_MODE) {
         int yy;
         
         yy = y + goom_irand(goomInfo->gRandom, 4) - goom_irand(goomInfo->gRandom, 4) + data->wave / 10;
         if (yy < 0)
             yy = 0;
         if (yy >= (signed int)goomInfo->screen.height)
             yy = goomInfo->screen.height - 1;
         
         *px = (x << 4) + data->firedec[yy] + (data->wave / 10);
         *py = (y << 4) + 132 - ((data->vitesse < 131) ? data->vitesse : 130);
         
         data->wavesp += goom_irand(goomInfo->gRandom, 3) - goom_irand(goomInfo->gRandom, 3);
         if (data->wave < -10)
             data->wavesp += 2;
         if (data->wave > 10)
             data->wavesp -= 2;
         data->wave += (data->wavesp / 10) + goom_irand(goomInfo->gRandom, 3) - goom_irand(goomInfo->gRandom, 3);
         if (data->wavesp > 100)
             data->wavesp = (data->wavesp * 9) / 10;
     }
     else {
         int     dist = 0, vx9, vy9;
         int     vx, vy;
         int     ppx, ppy;
         int     fvitesse = data->vitesse << 4;
         
         if (data->noisify) {
             x += goom_irand(goomInfo->gRandom, data->noisify) - goom_irand(goomInfo->gRandom, data->noisify);
             y += goom_irand(goomInfo->gRandom, data->noisify) - goom_irand(goomInfo->gRandom, data->noisify);
         }
         vx = (x - data->middleX) << 9;
         vy = (y - data->middleY) << 9;
         
         if (data->hPlaneEffect)
             vx += data->hPlaneEffect * (y - data->middleY);
         
         if (data->vPlaneEffect)
             vy += data->vPlaneEffect * (x - data->middleX);
         
         if (data->waveEffect) {
             fvitesse *=
             1024 +
             ShiftRight (goomInfo->sintable
                         [(unsigned short) (dist * 0xffff + EFFECT_DISTORS)], 6);
             fvitesse /= 1024;
         }
         
         if (data->hypercosEffect) {
             vx += ShiftRight (goomInfo->sintable[(-vy + dist) & 0xffff], 1);
             vy += ShiftRight (goomInfo->sintable[(vx + dist) & 0xffff], 1);
         }
         
         vx9 = ShiftRight (vx, 9);
         vy9 = ShiftRight (vy, 9);
         dist = vx9 * vx9 + vy9 * vy9;
         
         switch (data->theMode) {
             case WAVE_MODE:
                 fvitesse *=
                 1024 +
                 ShiftRight (goomInfo->sintable
                             [(unsigned short) (dist * 0xffff * EFFECT_DISTORS)], 6);
                 fvitesse>>=10;
                 break;
             case CRYSTAL_BALL_MODE:
                 fvitesse += (dist >> (10-EFFECT_DISTORS_SL));
                 break;
             case AMULETTE_MODE:
                 fvitesse -= (dist >> (4 - EFFECT_DISTORS_SL));
                 break;
             case SCRUNCH_MODE:
                 fvitesse -= (dist >> (10 - EFFECT_DISTORS_SL));
                 break;
             case HYPERCOS1_MODE:
                 vx = vx + ShiftRight (goomInfo->sintable[(-vy + dist) & 0xffff], 1);
                 vy = vy + ShiftRight (goomInfo->sintable[(vx + dist) & 0xffff], 1);
                 break;
             case HYPERCOS2_MODE:
                 vx =
                 vx + ShiftRight (goomInfo->sintable[(-ShiftRight (vy, 1) + dist) & 0xffff], 0);
                 vy =
                     vy + ShiftRight (goomInfo->sintable[(ShiftRight (vx, 1) + dist) & 0xffff], 0);
                 fvitesse = 128 << 4;
                 break;
             case YONLY_MODE:
                 fvitesse *= 1024 + ShiftRight (goomInfo->sintable[vy & 0xffff], 6);
                 fvitesse >>= 10;
                 break;
             case SPEEDWAY_MODE:
                 fvitesse -= (ShiftRight(vy,10-EFFECT_DISTORS_SL));
                 break;
         }
         
         if (fvitesse < -3024)
             fvitesse = -3024;
         
         if (vx < 0)									// pb avec decalage sur nb negatif
             ppx = -(-(vx * fvitesse) >> 16);
         // 16 = 9 + 7 (7 = nb chiffre virgule de vitesse * (v = 128 => immobile)
         //    * * * * * 9 = nb chiffre virgule de vx) 
         else
             ppx = ((vx * fvitesse) >> 16);
         
         if (vy < 0)
             ppy = -(-(vy * fvitesse) >> 16);
         else
             ppy = ((vy * fvitesse) >> 16);
         
         *px = (data->middleX << 4) + ppx;
         *py = (data->middleY << 4) + ppy;
     }
 }
 */



/* Per-pixel wipe beta [0..1] in screen pixel coords: 0 = keep the old map
 * (brutS), 1 = use the new map (brutD). Exact endpoint overrides: c <= 0
 * yields 0 everywhere, c >= 1 yields 1 everywhere (the swap frame must
 * render the untouched old map). Hard step (ring <= 0) never calls sqrtf.
 * Shared with zoomFilterGetVelocity (same selection as the kernels).
 * halfDiagonal = 0.5*sqrt(prevX^2+prevY^2) at the current canvas size;
 * the frontier is W = c * halfDiagonal with the per-pixel progress
 * c = progress * j (j = 1 + wobble*(luma*2/255 - 1), j = 1 without
 * wobble), R = W for WIPE_RADIUS. */
static float wipeBeta (int mode, const ZoomBlend *blend, float x, float y,
                       float halfDiagonal, int idx)
{
    float d, W, j, cp;

    if (blend->progress <= 0.0f) return 0.0f;
    if (blend->progress >= 1.0f) return 1.0f;

    /* wobble par pixel : j = 1 + wobble*(l*2/255 - 1), cp = progress*j
     * (cp peut depasser 1 : auto-completion voulue ; seuls les overrides
     * globaux ci-dessus sont des endpoints exacts). */
    if (blend->luma != NULL && blend->wobble > 0.0f) {
        float l = (float) blend->luma[idx];          /* idx = output pixel index, row-major */
        /* fmaf: single rounding, bit-identical to the NEON vfmaq forms */
        j = fmaf (blend->wobble, fmaf (l, 2.0f / 255.0f, -1.0f), 1.0f);
    } else {
        j = 1.0f;
    }
    cp = blend->progress * j;
    W = cp * halfDiagonal;
    if (mode == 2) {           /* WIPE_SEAMS */
        /* s = distance to the nearest of the N seam lines (the fold's
         * mirror axes, normals n1 rotated by m*PI/N). */
        float s = 0.0f;
        float a = 0.0f;
        float ca = 1.0f, sa = 0.0f;
        int m;
        /* meme borne que le noyau NEON (seamU[32], zoom_filter_neon.c) :
         * les deux chemins restent bit-exacts si un jour N depasse 32
         * (maximum actuel : 25 dans kaleidoFoldCounts). */
        for (m = 0; m < blend->foldCount && m < 32; m++) {
            float ux = blend->n1x * ca - blend->n1y * sa;
            float uy = blend->n1x * sa + blend->n1y * ca;
            float sm = (x - blend->cx) * ux + (y - blend->cy) * uy;
            if (sm < 0.0f) sm = -sm;
            if (m == 0 || sm < s) s = sm;
            a += (float)M_PI / (float)blend->foldCount;
            ca = cosf(a);
            sa = sinf(a);
        }
        if (blend->ring <= 0.0f)
            return (s <= W) ? 1.0f : 0.0f;
        d = s;
    } else {                   /* WIPE_RADIUS: hard step compares d2, no sqrt */
        float dx = x - blend->cx;
        float dy = y - blend->cy;
        float d2 = fmaf (dy, dy, dx * dx);   /* matches the NEON fma(dfy,dfy,dfx*dfx) */
        if (blend->ring <= 0.0f)
            return (d2 <= W * W) ? 1.0f : 0.0f;
        d = sqrtf (d2);
    }

    {
        float b = (W + blend->ring * 0.5f - d) / blend->ring;
        if (b < 0.0f) b = 0.0f;
        else if (b > 1.0f) b = 1.0f;
        return b;
    }
}

static void c_zoom (Pixel *expix1, Pixel *expix2, unsigned int prevX, unsigned int prevY, signed int *brutS, signed int *brutD,
                    int buffratio, int precalCoef[16][16], const ZoomBlend *blend)
{
    int     myPos, myPos2;
    Color   couleur;
    
    unsigned int ax = (prevX - 1) << PERTEDEC, ay = (prevY - 1) << PERTEDEC;
    
    int     bufsize = prevX * prevY * 2;
    int     bufwidth = prevX;
    /* wipe blend: incremental screen coords of the output pixel */
    int     blendMode = blend ? blend->mode : 0;
    float   wx = 0.0f, wy = 0.0f;   /* screen coords of the output pixel */
    float   wipeHalfDiag = 0.5f * sqrtf ((float) (prevX * prevX + prevY * prevY));
    
    expix1[0].val=expix1[prevX-1].val=expix1[prevX*prevY-1].val=expix1[prevX*prevY-prevX].val=0;
    
    for (myPos = 0; myPos < bufsize; myPos += 2) {
        Color   col1, col2, col3, col4;
        int     c1, c2, c3, c4, px, py;
        int     pos;
        int     coeffs;
        
        int     brutSmypos = brutS[myPos];
        
        myPos2 = myPos + 1;
        
        if (blendMode != 0) {
            /* geometric wipe: beta selects / soft-lerps between the two
             * pure maps (brutS = old, brutD = new); buffratio is ignored.
             * Exact endpoints: a full select (beta 0 or 1, the hard step
             * and the c<=0 / c>=1 overrides) reads the map DIRECTLY:
             * routing 65535 through the lerp would leave the 1/65536
             * residue (D-S), which is orbit-varying across brutS's own
             * gauge and would break exact grown-region symmetry. */
            int beta_fix;
            float beta = wipeBeta (blendMode, blend, wx, wy, wipeHalfDiag,
                                   myPos >> 1);
            beta_fix = (int)(beta * 65535.0f + 0.5f);
            if (beta_fix >= 65535) {
                px = brutD[myPos];
                brutSmypos = brutS[myPos2];
                py = brutD[myPos2];
            }
            else if (beta_fix <= 0) {
                px = brutSmypos;
                brutSmypos = brutS[myPos2];
                py = brutSmypos;
            }
            else {
                px = brutSmypos + (((brutD[myPos] - brutSmypos) * beta_fix) >> BUFFPOINTNB);
                brutSmypos = brutS[myPos2];
                py = brutSmypos + (((brutD[myPos2] - brutSmypos) * beta_fix) >> BUFFPOINTNB);
            }
        } else {
            px = brutSmypos + (((brutD[myPos] - brutSmypos) * buffratio) >> BUFFPOINTNB);
            brutSmypos = brutS[myPos2];
            py = brutSmypos + (((brutD[myPos2] - brutSmypos) * buffratio) >> BUFFPOINTNB);
        }
        if ((py >= ay) || (px >= ax)) {
            pos = coeffs = 0;
        } else {
            pos = ((px >> PERTEDEC) + prevX * (py >> PERTEDEC));
            /* coef en modulo 15 */
            coeffs = precalCoef[px & PERTEMASK][py & PERTEMASK];
        }
        getPixelRGB_ (expix1, pos, &col1);
        getPixelRGB_ (expix1, pos + 1, &col2);
        getPixelRGB_ (expix1, pos + bufwidth, &col3);
        getPixelRGB_ (expix1, pos + bufwidth + 1, &col4);
        
        c1 = coeffs;
        c2 = (c1 >> 8) & 0xFF;
        c3 = (c1 >> 16) & 0xFF;
        c4 = (c1 >> 24) & 0xFF;
        c1 = c1 & 0xff;
        
        couleur.r = col1.r * c1 + col2.r * c2 + col3.r * c3 + col4.r * c4;
        if (couleur.r > 5)
            couleur.r -= 5;
        couleur.r >>= 8;
        
        couleur.v = col1.v * c1 + col2.v * c2 + col3.v * c3 + col4.v * c4;
        if (couleur.v > 5)
            couleur.v -= 5;
        couleur.v >>= 8;
        
        couleur.b = col1.b * c1 + col2.b * c2 + col3.b * c3 + col4.b * c4;
        if (couleur.b > 5)
            couleur.b -= 5;
        couleur.b >>= 8;
        
        setPixelRGB_ (expix2, myPos >> 1, couleur);
        /* advance the output pixel coords (x increments every iteration,
         * y every prevX of them) */
        wx += 1.0f;
        if (wx >= (float)prevX) {
            wx = 0.0f;
            wy += 1.0f;
        }
    }
}

/** generate the water fx horizontal direction buffer */
static void generateTheWaterFXHorizontalDirectionBuffer(PluginInfo *goomInfo, ZoomFilterFXWrapperData *data) {
    
    int loopv;
    int decc = goom_irand(goomInfo->gRandom, 8) - 4;
    int spdc = goom_irand(goomInfo->gRandom, 8) - 4;
    int accel = goom_irand(goomInfo->gRandom, 8) - 4;
    
    for (loopv = data->prevY; loopv != 0;) {
        
        loopv--;
        data->firedec[loopv] = decc;
        decc += spdc / 10;
        spdc += goom_irand(goomInfo->gRandom, 3) - goom_irand(goomInfo->gRandom, 3);
        
        if (decc > 4)
            spdc -= 1;
        if (decc < -4)
            spdc += 1;
        
        if (spdc > 30)
            spdc = spdc - goom_irand(goomInfo->gRandom, 3) + accel / 10;
        if (spdc < -30)
            spdc = spdc + goom_irand(goomInfo->gRandom, 3) + accel / 10;
        
        if (decc > 8 && spdc > 1)
            spdc -= goom_irand(goomInfo->gRandom, 3) - 2;
        
        if (decc < -8 && spdc < -1)
            spdc += goom_irand(goomInfo->gRandom, 3) + 2;
        
        if (decc > 8 || decc < -8)
            decc = decc * 8 / 9;
        
        accel += goom_irand(goomInfo->gRandom, 2) - goom_irand(goomInfo->gRandom, 2);
        if (accel > 20)
            accel -= 2;
        if (accel < -20)
            accel += 2;
    }
}

/* Wipe : convergence de la carte cible sur le point replie. Pour chaque
 * pixel de sortie p, la source ecrite est celle du point replie f(p) —
 * le meme pour toute l'orbite (fold(g.p) == fold(p)) — lue bilineairement
 * dans brutD (la meme lecture que le re-gauge du bake). La table
 * resultante est EXACTEMENT constante sur les orbites du pli : les
 * tables construites pixel par pixel wobblent a +/- 1/16 px entre
 * miroirs (bruit float du build, absent sur les toiles ou le pli tombe
 * pile sur la grille, p.ex. 64x64), le chemin LINEAR masque ce wobble au
 * dernier pas du lerp (il se raccroche au re-gauge, exactement constant),
 * mais la selection spatiale du wipe le rendait tel quel — ~3% des
 * pixels fantomes le long des coutures a 864x542, persistants jusqu'a
 * la prochaine transition. Sur une carte deja constante sur les orbites
 * la lecture est un no-op : les invariants verifies a 64x64 ne voient
 * rien. S et D recoivent la meme carte : l'invariant de merge (S/D en
 * la meme jauge) reste vrai pour la transition suivante. */
static void wipeConvergeGauge (ZoomFilterFXWrapperData *data)
{
    size_t bytes = (size_t) data->prevX * data->prevY * 2 * sizeof (int);
    int maxX = ((data->prevX - 1) << PERTEDEC) - 1;
    int maxY = ((data->prevY - 1) << PERTEDEC) - 1;
    int *scratch = (int *) malloc (bytes);
    Uint px, py;

    if (scratch == NULL) {
        /* OOM : l'ancienne convergence (copie brute, le wobble reste) */
        memcpy (data->brutS, data->brutD, bytes);
        return;
    }

    for (py = 0; py < (Uint)data->prevY; py++) {
        for (px = 0; px < (Uint)data->prevX; px++) {
            float fx, fy, gx, gy, tx, ty;
            int ix, iy, ix1, iy1, sx, sy;
            Uint p00, p10, p01, p11;
            float s00, s10, s01, s11;
            int wpos = (int)((py * data->prevX + px) * 2);

            kaleidoFold (data, (float)px - (float)data->middleX,
                              (float)py - (float)data->middleY, &fx, &fy, NULL);
            gx = fx + (float)data->middleX;
            gy = fy + (float)data->middleY;
            if (gx < 0.0f) gx = 0.0f;
            else if (gx > (float)(data->prevX - 1)) gx = (float)(data->prevX - 1);
            if (gy < 0.0f) gy = 0.0f;
            else if (gy > (float)(data->prevY - 1)) gy = (float)(data->prevY - 1);

            ix = (int)gx;
            iy = (int)gy;
            ix1 = ix + 1 < (int)data->prevX ? ix + 1 : (int)data->prevX - 1;
            iy1 = iy + 1 < (int)data->prevY ? iy + 1 : (int)data->prevY - 1;
            tx = gx - (float)ix;
            ty = gy - (float)iy;
            p00 = (iy * data->prevX + ix) * 2;
            p10 = (iy * data->prevX + ix1) * 2;
            p01 = (iy1 * data->prevX + ix) * 2;
            p11 = (iy1 * data->prevX + ix1) * 2;

            s00 = (float)data->brutD[p00];
            s10 = (float)data->brutD[p10];
            s01 = (float)data->brutD[p01];
            s11 = (float)data->brutD[p11];
            sx = (int)((1.0f - tx) * ((1.0f - ty) * s00 + ty * s01)
                     + tx * ((1.0f - ty) * s10 + ty * s11) + 0.5f);

            s00 = (float)data->brutD[p00+1];
            s10 = (float)data->brutD[p10+1];
            s01 = (float)data->brutD[p01+1];
            s11 = (float)data->brutD[p11+1];
            sy = (int)((1.0f - tx) * ((1.0f - ty) * s00 + ty * s01)
                     + tx * ((1.0f - ty) * s10 + ty * s11) + 0.5f);

            if (sx < 0) sx = 0;
            else if (sx > maxX) sx = maxX;
            if (sy < 0) sy = 0;
            else if (sy > maxY) sy = maxY;
            scratch[wpos] = sx;
            scratch[wpos+1] = sy;
        }
    }

    memcpy (data->brutS, scratch, bytes);
    memcpy (data->brutD, scratch, bytes);
    free (scratch);
}

/* Wipe : fin de la transition geometrique. Le dernier rendu a pris
 * beta = 1 partout (brutD, la carte fusionnee en jauge cible) ; on
 * converge les deux tables dessus (lecture au point replie, voir
 * wipeConvergeGauge) pour que les frames suivantes, rendues en LINEAR a
 * buffratio = BUFFPOINTMASK, ne laissent paraitre aucun residu, et
 * que l'invariant de merge (S/D en la meme jauge) reste vrai pour la
 * transition suivante. */
static void wipeComplete (ZoomFilterFXWrapperData *data)
{
    data->wipeActive = 0;
    data->buffratio = BUFFPOINTMASK;
    data->sweepValid = 0;

    /* S/D <- la carte cible convergee sur le point replie : la jauge des
     * deux tables est desormais celle du pli vivant, exactement comme
     * apres un swap LINEAR re-gauge. */
    if (data->brutS != NULL && data->brutD != NULL)
        wipeConvergeGauge (data);

    /* commit de la jauge : brutS/brutD echantillonnent desormais dans le
     * referentiel du pli vivant (reporte depuis le swap : pendant le wipe,
     * brutS garde sa propre jauge pour la selection spatiale). */
    data->gaugeActive = data->kaleidoEffect && data->kaleidoN > 0;
    data->gaugeN = data->kaleidoN;
    data->gaugeAngle = data->kaleidoAngle;
    data->gaugeN1x = data->kaleidoN1x;
    data->gaugeN1y = data->kaleidoN1y;
    data->gaugeN2x = data->kaleidoN2x;
    data->gaugeN2y = data->kaleidoN2y;
    data->gaugeMidx = data->middleX;
    data->gaugeMidy = data->middleY;
}


/**
* Main work for the dynamic displacement map.
 * 
 * Reads data from pix1, write to pix2.
 *
 * Useful datas for this FX are stored in ZoomFilterData.
 * 
 * If you think that this is a strange function name, let me say that a long time ago,
 *  there has been a slow version and a gray-level only one. Then came these function,
 *  fast and workin in RGB colorspace ! nice but it only was applying a zoom to the image.
 *  So that is why you have this name, for the nostalgy of the first days of goom
 *  when it was just a tiny program writen in Turbo Pascal on my i486...
 */
void zoomFilterFastRGB (PluginInfo *goomInfo, Pixel * pix1, Pixel * pix2, ZoomFilterData * zf, Uint resx, Uint resy, int *switchIncr, float *switchMult)
{
    ZoomFilterFXWrapperData *data = (ZoomFilterFXWrapperData*)goomInfo->zoomFilter_fx.fx_data;
    
    if (!BVAL(data->enabled_bp)) return;
    
    /* expose the live applied state to the control UI (read-only monitors) */
    IVAL(data->zoomMode_p) = data->theMode;
    {
        int vitesse = (int)(data->general_speed * 128.0f) + 128;
        if (data->reverse) vitesse = 256 - vitesse;
        if (vitesse < 0) vitesse = 0;
        if (vitesse > 255) vitesse = 255;
        IVAL(data->vitesse_p) = vitesse;
    }
    IVAL(data->reverse_p) = data->reverse ? 1 : 0;
    IVAL(data->middleX_p) = data->middleX;
    IVAL(data->middleY_p) = data->middleY;
    IVAL(data->noisify_p) = data->noisify;
    IVAL(data->waveFx_p) = data->waveEffect ? 1 : 0;
    IVAL(data->hypercosFx_p) = data->hypercosEffect ? 1 : 0;
    
    /** changement de taille **/
    if ((data->prevX != resx) || (data->prevY != resy)) {
        data->prevX = resx;
        data->prevY = resy;
        
        if (data->brutS) free (data->freebrutS);
        data->brutS = 0;
        if (data->brutD) free (data->freebrutD);
        data->brutD = 0;
        if (data->brutT) free (data->freebrutT);
        data->brutT = 0;
        if (data->wipeLuma) free (data->wipeLuma);
        data->wipeLuma = 0;
        
        data->middleX = resx / 2;
        data->middleY = resy / 2;
        data->mustInitBuffers = 1;
        if (data->firedec) free (data->firedec);
        data->firedec = 0;
    }
    
    if (data->interlace_start != -2)
        zf = NULL;
    
    /** changement de config **/
    if (zf) {
        /* un wipe en cours est force-acheve d'abord : le merge bake
         * ci-dessous suppose S/D en jauges coherentes. */
        if (data->wipeActive)
            wipeComplete (data);

        /* Choix de la transition AVANT d'ecraser l'etat courant :
         *  - fold ON : wipe geometrique si le style le demande (la
         *    selection spatiale ne melange jamais deux jauges) ;
         *  - tout le reste (re-sectorisation, fold OFF, zoom non-pli,
         *    style = 0) : chemin LINEAR historique, re-gauge au bake
         *    inclus, inchange. */
        int foldOn = data->kaleidoEffect == 0 && zf->kaleidoEffect != 0;
        int style = IVAL (data->foldTransition_p);

        /* l'etat du pli cible d'abord : l'armement du wipe en depend
         * (kaleidoN doit deja etre celui du pli cible). */
        data->kaleidoEffect = zf->kaleidoEffect;
        if (!data->kaleidoEffect) {
            data->kaleidoN = 0;      /* desactive : le pli ne s'applique plus */
            data->kaleidoAngle = 0.0f;
        }
        else if (zf->foldCount != data->kaleidoN || zf->foldAngle != data->kaleidoAngle)
            kaleidoPrecompute (data, zf->foldCount ? zf->foldCount : 4, zf->foldAngle);

        /* Choix de la transition AVANT d'ecraser l'etat courant :
         *  - fold ON : wipe geometrique si le style le demande (la
         *    selection spatiale ne melange jamais deux jauges) ;
         *  - tout le reste (re-sectorisation, fold OFF, zoom non-pli,
         *    style = 0) : chemin LINEAR historique, re-gauge au bake
         *    inclus, inchange.
         * Arme seulement si le pli cible est reel (kaleidoN > 0) : un
         * foldCount == 0 (pli degeneri, pli jamais initialise) rendrait
         * WIPE_SEAMS divergente entre C (beta = 1 partout, s initie a 0)
         * et NEON (beta = 0 partout, smin initie a 1e30). */
        data->wipeMode = (foldOn && style != 0 && data->kaleidoN > 0) ? style : 0;
        data->wipeFrames = IVAL (data->wipeFrames_p);
        if (data->wipeFrames < 2) data->wipeFrames = 2;
        else if (data->wipeFrames > 120) data->wipeFrames = 120;
        data->wipeRing = (float)IVAL (data->wipeRing_p);

        data->reverse = zf->reverse;
        data->general_speed = (float)(zf->vitesse-128)/128.0f;
        if (data->reverse) data->general_speed = -data->general_speed;
        data->middleX = zf->middleX;
        data->middleY = zf->middleY;
        data->theMode = zf->mode;
        data->hPlaneEffect = zf->hPlaneEffect;
        data->vPlaneEffect = zf->vPlaneEffect;
        data->waveEffect = zf->waveEffect;
        data->hypercosEffect = zf->hypercosEffect;
        data->noisify = zf->noisify;
        data->interlace_start = 0;
    }
    
    
    if (data->mustInitBuffers) {
        
        /* un wipe en cours est abandonne, pas converge : les tables
         * viennent d'etre liberees par le changement de taille (les
         * converger ici serait un memcpy entre pointeurs NULL), et la
         * reconstruction remet S=D. La jauge se recommitera au prochain
         * swap (wipeActive est remis a zero : le commit a lieu). */
        data->wipeActive = 0;
        data->mustInitBuffers = 0;
        data->sweepValid = 0;
        data->freebrutS = (signed int *) calloc (resx * resy * 2 + 128, sizeof(unsigned int));
        data->brutS = (gint32 *) ((1 + ((uintptr_t) (data->freebrutS)) / 128) * 128);
        
        data->freebrutD = (signed int *) calloc (resx * resy * 2 + 128, sizeof(unsigned int));
        data->brutD = (gint32 *) ((1 + ((uintptr_t) (data->freebrutD)) / 128) * 128);
        
        data->freebrutT = (signed int *) calloc (resx * resy * 2 + 128, sizeof(unsigned int));
        data->brutT = (gint32 *) ((1 + ((uintptr_t) (data->freebrutT)) / 128) * 128);

        data->wipeLuma = (unsigned char *) calloc (resx * resy, 1);
        
        data->buffratio = 0;
        
        data->firedec = (int *) malloc (data->prevY * sizeof (int));
        generateTheWaterFXHorizontalDirectionBuffer(goomInfo, data);
        
        data->interlace_start = 0;
        makeZoomBufferStripe(data,resy);
        
        /* Copy the data from temp to dest and source */
        memcpy(data->brutS,data->brutT,resx * resy * 2 * sizeof(int));
        memcpy(data->brutD,data->brutT,resx * resy * 2 * sizeof(int));
    }
    
    /* generation du buffer de trans */
    if (data->interlace_start == -1) {
        /* Sauvegarde de l'etat actuel dans la nouvelle source, EN JAUGE
         * CIBLE quand le pli change. brutS et brutD doivent echantillonner
         * dans le meme referentiel : a cheval sur deux jauges, l'interpolation
         * (buffratio plus bas) fait glisser chaque source le long du
         * deplacement du pli (X - f) : un arrachement de la taille de l'ecran,
         * qui s'inverse a chaque couture. Le pli n'est pas continu (il
         * identifie des points entre eux) : la jauge se commite d'un coup.
         *  - cible pliee : on re-echantillonne l'etat courant A TRAVERS le
         *    pli (la source lue est celle du point replie). Chaque miroir
         *    recoit le contenu de la chambre : le mandala s'allume d'un coup,
         *    et toute la transition suivante reste dans la chambre (bornee,
         *    symetrique).
         *  - cible non pliee, source pliee : on re-projette chaque source
         *    dans le secteur du pixel (ou le rendu etait identique, l'etat
         *    etant symetrique) : les miroirs s'ouvrent sans arrachement. */
        Uint px, py;
        int targetFolded = data->kaleidoEffect && data->kaleidoN > 0;
        /* wipe : brutS garde SA jauge (la selection spatiale ne melange
         * jamais deux jauges), le re-gauge est saute ; la jauge cible se
         * commitera a la fin du wipe (wipeActive est pris au swap, qui est
         * APRES ce bloc : le wipe en attente est encore dans wipeMode). */
        int wipeNow = data->wipeActive || data->wipeMode != 0;
        int regauge = !wipeNow && (targetFolded ? (!data->gaugeActive
                                       || data->gaugeN != data->kaleidoN
                                       || data->gaugeAngle != data->kaleidoAngle)
                                    : (data->gaugeActive != 0));
        float mx = (float)data->middleX, my = (float)data->middleY;
        int maxX = ((data->prevX - 1) << PERTEDEC) - 1;
        int maxY = ((data->prevY - 1) << PERTEDEC) - 1;
        /* la cible pliee lit brutS/brutD au point replie et ecrit partout :
         * aucun des trois buffers n'est libre, on passe par un scratch. */
        int *dst = data->brutS;
        int *scratch = NULL;

        data->stampedGauge = 0;
        if (targetFolded && regauge) {
            scratch = (int *)malloc (data->prevX * data->prevY * 2 * sizeof (int));
            dst = scratch;
            /* repli -> repli : la re-gauge lit l'ancienne carte (elle-meme
             * pliee) au point replie, les sources gardent le pli compose
             * f_old(f_new(p)). Bon contenu (le mandala se replie sur lui-
             * meme) mais ce n'est pas une carte "une frame" : son
             * deplacement n'est pas du mouvement. */
            data->stampedGauge = (data->gaugeActive != 0);
        }

        for (py = 0; py < data->prevY; py++) {
            for (px = 0; px < data->prevX; px++) {
                Uint rx = px, ry = py;
                float fx = 0.0f, fy = 0.0f, g[4];
                float gx = 0.0f, gy = 0.0f;
                int haveG = 0, haveB = 0;

                if (regauge) {
                    if (targetFolded) {
                        /* Lecture CONTINUE de l'etat au point replie (4 taps
                         * bilineaires). La lecture au pixel le plus proche
                         * construisait une carte en escalier : round(f(p))
                         * saute d'un pixel des que f franchit une demi-unite,
                         * et le bruit de chemin du pli entre jumeaux miroirs
                         * amplifiait le saut en sources differentes d'un
                         * pixel : miroirs casures le long des lignes de
                         * preimage. La lecture bilineaire est de Lipschitz :
                         * l'erreur de chemin devient ~0.005 px de source,
                         * sous le quantum 1/16 px du tableau. */
                        kaleidoFold (data, (float)px - mx, (float)py - my, &fx, &fy, NULL);
                        gx = fx + mx;
                        gy = fy + my;
                        if (gx < 0.0f) gx = 0.0f;
                        else if (gx > (float)(data->prevX - 1)) gx = (float)(data->prevX - 1);
                        if (gy < 0.0f) gy = 0.0f;
                        else if (gy > (float)(data->prevY - 1)) gy = (float)(data->prevY - 1);
                        haveB = 1;
                    }
                    else {
                        /* p = g.f : g ramene la source de la chambre dans le
                         * secteur du pixel (meme couleur : l'etat est
                         * symetrique). Le pli est celui de la JAUGE : son
                         * sommet est capture au commit (gaugeMidx/Midy) —
                         * le moteur peut deplacer middleX dans le meme
                         * changement de config qui eteint le pli (tirage
                         * "changement de milieu" du cycle goom), et la
                         * projection doit se faire autour du sommet que le
                         * mandala montrait, pas autour du nouveau. */
                        kaleidoFoldNormals (data->gaugeN1x, data->gaugeN1y,
                                            data->gaugeN2x, data->gaugeN2y,
                                            data->gaugeN,
                                            (float)px - (float)data->gaugeMidx,
                                            (float)py - (float)data->gaugeMidy,
                                            &fx, &fy, g);
                        haveG = 1;
                    }
                }
                {
                    Uint wpos = (py * data->prevX + px) * 2;
                    int sx, sy;

                    if (haveB) {
                        /* merged source field, bilinear at (gx, gy) */
                        int ix = (int)gx, iy = (int)gy;
                        int ix1 = ix + 1 < (int)data->prevX ? ix + 1 : (int)data->prevX - 1;
                        int iy1 = iy + 1 < (int)data->prevY ? iy + 1 : (int)data->prevY - 1;
                        float tx = gx - (float)ix, ty = gy - (float)iy;
                        Uint p00 = (iy * data->prevX + ix) * 2;
                        Uint p10 = (iy * data->prevX + ix1) * 2;
                        Uint p01 = (iy1 * data->prevX + ix) * 2;
                        Uint p11 = (iy1 * data->prevX + ix1) * 2;
                        float s00x, s10x, s01x, s11x, s00y, s10y, s01y, s11y;

                        s00x = (float)(data->brutS[p00]
                            + (((data->brutD[p00] - data->brutS[p00]) * data->buffratio) >> BUFFPOINTNB));
                        s10x = (float)(data->brutS[p10]
                            + (((data->brutD[p10] - data->brutS[p10]) * data->buffratio) >> BUFFPOINTNB));
                        s01x = (float)(data->brutS[p01]
                            + (((data->brutD[p01] - data->brutS[p01]) * data->buffratio) >> BUFFPOINTNB));
                        s11x = (float)(data->brutS[p11]
                            + (((data->brutD[p11] - data->brutS[p11]) * data->buffratio) >> BUFFPOINTNB));
                        s00y = (float)(data->brutS[p00+1]
                            + (((data->brutD[p00+1] - data->brutS[p00+1]) * data->buffratio) >> BUFFPOINTNB));
                        s10y = (float)(data->brutS[p10+1]
                            + (((data->brutD[p10+1] - data->brutS[p10+1]) * data->buffratio) >> BUFFPOINTNB));
                        s01y = (float)(data->brutS[p01+1]
                            + (((data->brutD[p01+1] - data->brutS[p01+1]) * data->buffratio) >> BUFFPOINTNB));
                        s11y = (float)(data->brutS[p11+1]
                            + (((data->brutD[p11+1] - data->brutS[p11+1]) * data->buffratio) >> BUFFPOINTNB));
                        sx = (int)((1.0f - tx) * ((1.0f - ty) * s00x + ty * s01x)
                                 + tx * ((1.0f - ty) * s10x + ty * s11x) + 0.5f);
                        sy = (int)((1.0f - tx) * ((1.0f - ty) * s00y + ty * s01y)
                                 + tx * ((1.0f - ty) * s10y + ty * s11y) + 0.5f);
                    } else {
                        Uint rpos = (ry * data->prevX + rx) * 2;
                        sx = data->brutS[rpos]
                            + (((data->brutD[rpos] - data->brutS[rpos]) * data->buffratio) >> BUFFPOINTNB);
                        sy = data->brutS[rpos+1]
                            + (((data->brutD[rpos+1] - data->brutS[rpos+1]) * data->buffratio) >> BUFFPOINTNB);
                    }

                    if (haveG) {
                        /* la source vit dans l'espace du pli de la jauge :
                         * g agit autour de SON sommet (en 1/16 px). */
                        float vx = (float)sx - (float)data->gaugeMidx * (float)BUFFPOINTNB;
                        float vy = (float)sy - (float)data->gaugeMidy * (float)BUFFPOINTNB;
                        sx = (int)(g[0] * vx + g[2] * vy
                                   + (float)data->gaugeMidx * (float)BUFFPOINTNB + 0.5f);
                        sy = (int)(g[1] * vx + g[3] * vy
                                   + (float)data->gaugeMidy * (float)BUFFPOINTNB + 0.5f);
                    }
                    if (sx < 0) sx = 0;
                    else if (sx > maxX) sx = maxX;
                    if (sy < 0) sy = 0;
                    else if (sy > maxY) sy = maxY;
                    dst[wpos] = sx;
                    dst[wpos+1] = sy;
                }
            }
        }
        if (scratch != NULL) {
            memcpy (data->brutS, scratch, data->prevX * data->prevY * 2 * sizeof (int));
            free (scratch);
        }
        data->buffratio = 0;
    }
    
    if (data->interlace_start == -1) {
        signed int * tmp;
        tmp = data->brutD;
        data->brutD=data->brutT;
        data->brutT=tmp;
        tmp = data->freebrutD;
        data->freebrutD=data->freebrutT;
        data->freebrutT=tmp;
        data->interlace_start = -2;

        /* commit de la jauge : brutS/brutD echantillonnent desormais dans le
         * referentiel du pli vivant (le re-gauge a ete fait au bloc
         * precedent). zoomFilterGetVelocity y lit le flux percu.
         * Wipe : reporte a la fin de la transition (wipeComplete), brutS
         * doit garder SA jauge pendant la selection spatiale. */
        if (data->wipeMode != 0) {
            int mode = data->wipeMode;
            data->wipeActive = 1;
            data->wipeFrameK = 0;
            data->wipeProgress = 0.0f;
            data->wipeMode = 0;   /* consumed; wipeActive now drives */
            /* cache the wipe geometry from the params + the NEW fold */
            data->wipeBlend.mode = mode;
            data->wipeBlend.cx = (float)data->middleX;
            data->wipeBlend.cy = (float)data->middleY;
            data->wipeBlend.n1x = data->kaleidoN1x;
            data->wipeBlend.n1y = data->kaleidoN1y;
            data->wipeBlend.foldCount = data->kaleidoN;
            data->wipeBlend.ring = data->wipeRing;
            data->wipeBlend.luma = data->wipeLuma;
            data->wipeBlend.wobble =
                (float)IVAL (data->wipeWobble_p) * 0.01f;
            if (data->wipeBlend.wobble < 0.0f) data->wipeBlend.wobble = 0.0f;
            else if (data->wipeBlend.wobble > 0.5f) data->wipeBlend.wobble = 0.5f;
            data->wipeHalfDiag = 0.5f * sqrtf ((float)data->prevX * (float)data->prevX
                                               + (float)data->prevY * (float)data->prevY);
            data->wipeBlend.progress = 0.0f;
        }
        if (!data->wipeActive) {
        data->gaugeActive = data->kaleidoEffect && data->kaleidoN > 0;
        data->gaugeN = data->kaleidoN;
        data->gaugeAngle = data->kaleidoAngle;
        data->gaugeN1x = data->kaleidoN1x;
        data->gaugeN1y = data->kaleidoN1y;
        data->gaugeN2x = data->kaleidoN2x;
        data->gaugeN2y = data->kaleidoN2y;
        data->gaugeMidx = data->middleX;
        data->gaugeMidy = data->middleY;
        }
    }
    
    if (data->interlace_start>=0)
    {
        /* creation de la nouvelle destination */
        /* Kaleidoscope actif : 4x moins de lignes par frame -> la pliure
         * progresse sur ~64 frames au lieu de 16 (transition douce). */
        makeZoomBufferStripe(data, data->kaleidoEffect ? resy/64 : resy/16);
    }
    
    /* Wipe : le ramp buffratio est remplace par la selection spatiale.
     * k compte les appels noyau depuis le swap (le swap lui-meme = 0,
     * il rend c = 0 : l'ancienne carte intacte) ; l'appel k rend a
     * c = min(1, k / wipeFrames). */
    /* flux percu : snapshot du buffratio d'ENTREE de ramp (celui rendu
     * au noyau de la frame precedente) ; le pas de ramp de cette frame
     * est buffratio - prevRatio, lu par zoomFilterGetVelocity. Au swap,
     * le bake vient de remettre buffratio = 0 : le pas capture le
     * glissement du lerp depuis la base cuite. */
    data->prevRatio = data->buffratio;
    if (data->wipeActive) {
        data->wipeBlend.progress =
            data->wipeProgress = (float)data->wipeFrameK / (float)data->wipeFrames;
        if (data->wipeBlend.progress > 1.0f)
            data->wipeBlend.progress = 1.0f;
        /* les params peuvent changer en cours de wipe : rafraichir */
        data->wipeBlend.wobble = (float)IVAL (data->wipeWobble_p) * 0.01f;
        if (data->wipeBlend.wobble < 0.0f) data->wipeBlend.wobble = 0.0f;
        else if (data->wipeBlend.wobble > 0.5f) data->wipeBlend.wobble = 0.5f;
    } else {
        if (*switchIncr != 0) {
            data->buffratio += *switchIncr;
            if (data->buffratio > BUFFPOINTMASK)
                data->buffratio = BUFFPOINTMASK;
        }
        
        if (*switchMult != 1.0f) {
            data->buffratio = (int) ((float) BUFFPOINTMASK * (1.0f - *switchMult) +
                                     (float) data->buffratio * *switchMult);
        }
    }
    
    data->zoom_width = data->prevX;

    /* luma field: one byte per output pixel, invariant under the fold
     * (brutD is the new folded table, orbit-constant in its own gauge: the
     * orbit mates read the same source pixel). Read it BEFORE the kernel
     * overwrites pix1 (flow query reads wipeLuma later this same frame). */
    if (data->wipeActive) {
        int i;
        unsigned int ax = ((unsigned int)data->prevX - 1) << PERTEDEC;
        unsigned int ay = ((unsigned int)data->prevY - 1) << PERTEDEC;
        for (i = 0; i < (int)(data->prevX * data->prevY); i++) {
            int pxd = data->brutD[2*i], pyd = data->brutD[2*i+1];
            int pos = (((unsigned)pyd >= ay) || ((unsigned)pxd >= ax)) ? 0
                    : ((pxd >> PERTEDEC) + data->prevX * (pyd >> PERTEDEC));
            data->wipeLuma[i] = ((const unsigned char *)(pix1 + pos))[0];   /* byte 0 = red on COLOR_RGBA */
        }
    }

    goomInfo->methods.zoom_filter (data->prevX, data->prevY, pix1, pix2,
                                   data->brutS, data->brutD, data->buffratio, data->precalCoef,
                                   data->wipeActive ? &data->wipeBlend : NULL);
    
    if (data->wipeActive) {
        /* le rendu de c >= 1 acheve la transition (beta = 1 partout :
         * brutS est maintenant la carte fusionnee en jauge cible) */
        data->wipeFrameK += 1;
        if (data->wipeFrameK >= data->wipeFrames)
            wipeComplete (data);
    }

    /* flux percu : ce que le noyau vient de rendre est exactement le
     * lerp a buffratio (le query lit le meme blend). Le snapshot de
     * prevRatio est fait AVANT le ramp (plus haut) : a l'issue de cet
     * appel, prevRatio = buffratio d'entree, le query lit donc
     * dr = le pas de ramp de CETTE frame. Pas de re-inscription ici :
     * elle effacerait le pre-ramp et annulerait le sweep. */
    data->sweepValid = 1;
}
void zoomFilterGetVelocity (PluginInfo *goomInfo, float x, float y, float *vx, float *vy)
{
    ZoomFilterFXWrapperData *data = (ZoomFilterFXWrapperData*)goomInfo->zoomFilter_fx.fx_data;
    int ix, iy, pos;
    int effx, effy;

    *vx = 0.0f;
    *vy = 0.0f;

    if (!BVAL(data->enabled_bp) || (data->brutS == NULL) || (data->brutD == NULL))
        return;

    if (x < 0.0f) x = 0.0f;
    if (y < 0.0f) y = 0.0f;
    ix = (int)x;
    iy = (int)y;
    if (ix >= (int)data->prevX) ix = (int)data->prevX - 1;
    if (iy >= (int)data->prevY) iy = (int)data->prevY - 1;

    pos = (ix + iy * (int)data->prevX) * 2;

    /* same blend the zoom applies this frame (see c_zoom) : en wipe,
     * selection par pixel via beta (le ramp buffratio est ignore). */
    if (data->wipeActive) {
        float beta = wipeBeta (data->wipeBlend.mode, &data->wipeBlend,
                               (float)ix, (float)iy, data->wipeHalfDiag,
                               pos >> 1);
        int beta_fix = (int)(beta * 65535.0f + 0.5f);
        effx = data->brutS[pos]
            + (((data->brutD[pos] - data->brutS[pos]) * beta_fix) >> BUFFPOINTNB);
        effy = data->brutS[pos+1]
            + (((data->brutD[pos+1] - data->brutS[pos+1]) * beta_fix) >> BUFFPOINTNB);
    } else if (data->stampedGauge) {
        /* carte tamponnee (re-gauge pli -> pli) : le deplacement de carte
         * n'est pas du mouvement ; le flux de base se lit sur la cible
         * pure (brutD), le glissement de la morph passe par le sweep. */
        effx = data->brutD[pos];
        effy = data->brutD[pos+1];
    } else {
        effx = data->brutS[pos]
            + (((data->brutD[pos]   - data->brutS[pos])   * data->buffratio) >> BUFFPOINTNB);
        effy = data->brutS[pos+1]
            + (((data->brutD[pos+1] - data->brutS[pos+1]) * data->buffratio) >> BUFFPOINTNB);
    }

    /* the field stores source coordinates in 1/16 px, so the content
     * velocity is (dest - source) / 16.
     *
     * Etat plie : les tables sont en jauge chambre (la source est commune a
     * tous les miroirs) et (dest - source) porte le deplacement du pli
     * lui-meme (de l'ordre de l'ecran, inverse a chaque couture) : ce n'est
     * pas le mouvement que le contenu fait voir. On re-projette la source
     * dans le secteur du pixel avant de differencier,
     *     u = (p - m) - g.(s - m)   avec   p = g.f
     * exactement le flux percu : borne comme le mode de base, et equivariant
     * u(g.p) = g.u(p) (les copies miroirs d'un meme contenu derivent en
     * miroir). Sans pli, g = I et la formule ci-dessus est (dest - source). */
    {
        float sxp = (float)effx / (float)sqrtperte - (float)data->middleX;
        float syp = (float)effy / (float)sqrtperte - (float)data->middleY;
        /* le g (2x2 column-major, p = g.f) utilise ci-dessus pour la
         * reprojection ; le sweep le reutilise tel quel. */
        float g[4];
        int haveG = 0;

        /* Wipe : sous la frontiere la carte vient du pli NOUVEAU (jauge
         * kaleido vivante), dehors de l'ancienne (jauge commitee) :
         * exactement la selection du noyau. Apres completion la jauge
         * commitee est la nouvelle : coherent partout. */
        if (data->wipeActive) {
            float beta = wipeBeta (data->wipeBlend.mode, &data->wipeBlend,
                                   (float)ix, (float)iy, data->wipeHalfDiag,
                                   pos >> 1);
            if (beta >= 0.5f && data->kaleidoEffect && data->kaleidoN > 0) {
                float fx, fy, gx, gy;
                kaleidoFoldNormals (data->kaleidoN1x, data->kaleidoN1y,
                                    data->kaleidoN2x, data->kaleidoN2y,
                                    data->kaleidoN,
                                    (float)ix - (float)data->middleX,
                                    (float)iy - (float)data->middleY, &fx, &fy, g);
                haveG = 1;
                gx = g[0] * sxp + g[2] * syp;
                gy = g[1] * sxp + g[3] * syp;
                sxp = gx;
                syp = gy;
            }
        }
        else if (data->gaugeActive) {
            /* le pli de la jauge vit autour de SON sommet (capture au
             * commit) : le moteur peut deplacer middleX en meme temps
             * qu'il eteint le pli. On plie p autour du sommet de la jauge,
             * on re-base le vecteur source dans cet espace, on y applique
             * g, puis retour dans l'espace courant (l'origine se simplifie
             * dans u = p - g.s). */
            float fx, fy, gx, gy;
            float dmx = (float)data->middleX - (float)data->gaugeMidx;
            float dmy = (float)data->middleY - (float)data->gaugeMidy;
            kaleidoFoldNormals (data->gaugeN1x, data->gaugeN1y,
                                data->gaugeN2x, data->gaugeN2y, data->gaugeN,
                                (float)ix - (float)data->gaugeMidx,
                                (float)iy - (float)data->gaugeMidy, &fx, &fy, g);
            haveG = 1;
            gx = g[0] * (sxp + dmx) + g[2] * (syp + dmy) - dmx;
            gy = g[1] * (sxp + dmx) + g[3] * (syp + dmy) - dmy;
            sxp = gx;
            syp = gy;
        }
        *vx = ((float)ix - (float)data->middleX) - sxp;
        *vy = ((float)iy - (float)data->middleY) - syp;

        /* sweep : le contenu glisse parce que le lerp avance (le ramp
         * monte buffratio d'un pas par frame). u_sweep = -g . ds, ds =
         * pas de lerp en px (les tables sont en 1/16 px), via le MEME g
         * que la reprojection ; identite sans pli. Pendant un wipe, la
         * selection spatiale remplace le ramp : pas de sweep. */
        if (!data->wipeActive && data->sweepValid) {
            int dr = data->buffratio - data->prevRatio;      /* this frame's ramp step */
            float ks = (float) dr * (1.0f / (65536.0f * 16.0f));   /* tables are 1/16 px fixed point */
            float dsx = (float)(data->brutD[pos] - data->brutS[pos]) * ks;
            float dsy = (float)(data->brutD[pos+1] - data->brutS[pos+1]) * ks;
            /* u_sweep = -g . ds  (features appear to move opposite the source motion) */
            if (haveG) {
                *vx -= g[0] * dsx + g[2] * dsy;
                *vy -= g[1] * dsx + g[3] * dsy;
            } else {
                *vx -= dsx;   /* g = I : subtract ds directly */
                *vy -= dsy;
            }
        }
    }
}

static void generatePrecalCoef (int precalCoef[16][16])
{
    int coefh, coefv;
    
    for (coefh = 0; coefh < 16; coefh++) {
        for (coefv = 0; coefv < 16; coefv++) {
            
            int i;
            int diffcoeffh;
            int diffcoeffv;
            
            diffcoeffh = sqrtperte - coefh;
            diffcoeffv = sqrtperte - coefv;
            
            if (!(coefh || coefv)) {
                i = 255;
            }
            else {
                int i1, i2, i3, i4;
                
                i1 = diffcoeffh * diffcoeffv;
                i2 = coefh * diffcoeffv;
                i3 = diffcoeffh * coefv;
                i4 = coefh * coefv;
                
                // TODO: faire mieux...
                if (i1) i1--;
                if (i2) i2--;
                if (i3) i3--;
                if (i4) i4--;
                
                i = (i1) | (i2 << 8) | (i3 << 16) | (i4 << 24);
            }
            precalCoef[coefh][coefv] = i;
        }
    }
}

/* VisualFX Wrapper */

static void zoomFilterVisualFXWrapper_init (struct _VISUAL_FX *_this, PluginInfo *info)
{
    ZoomFilterFXWrapperData *data = (ZoomFilterFXWrapperData*)malloc(sizeof(ZoomFilterFXWrapperData));
    
    data->coeffs = 0;
    data->freecoeffs = 0;
    data->brutS = 0;
    data->freebrutS = 0;
    data->brutD = 0;
    data->freebrutD = 0;
    data->brutT = 0;
    data->freebrutT = 0;
    data->wipeLuma = 0;
    data->prevX = 0;
    data->prevY = 0;
    
    data->mustInitBuffers = 1;
    data->interlace_start = -2;
    
    data->general_speed = 0.0f;
    data->reverse = 0;
    data->theMode = AMULETTE_MODE;
    data->waveEffect = 0;
    data->hypercosEffect = 0;
    data->vPlaneEffect = 0;
    data->hPlaneEffect = 0;
    data->noisify = 2;
    
    /** modif by jeko : fixedpoint : buffration = (16:16) (donc 0<=buffration<=2^16) */
    data->buffratio = 0;
    data->firedec = 0;
    data->prevRatio = 0;
    data->sweepValid = 0;
    
    data->wave = data->wavesp = 0;

    data->kaleidoEffect = 0;    /* addon inactif au demarrage */
    kaleidoPrecompute (data, 4, 0.0f);
    data->gaugeActive = 0;      /* tables en jauge non pliee */
    data->gaugeN = 0;
    data->gaugeMidx = 0;
    data->gaugeMidy = 0;
    data->gaugeAngle = 0.0f;
    data->gaugeN1x = data->gaugeN1y = 0.0f;
    data->gaugeN2x = data->gaugeN2y = 0.0f;
    data->wipeActive = 0;
    data->wipeMode = 0;
    data->wipeFrameK = 0;
    data->wipeProgress = 0.0f;
    data->wipeFrames = 20;
    data->wipeRing = 0.0f;
    data->wipeHalfDiag = 0.0f;
    
    data->enabled_bp = secure_b_param("Enabled", 1);

    data->freeze_bp = secure_b_param("Freeze", 0);

    data->kaleidoMode_p = secure_i_param("Kaleido");
    IVAL(data->kaleidoMode_p) = 1;
    IMIN(data->kaleidoMode_p) = 0;
    IMAX(data->kaleidoMode_p) = 2;
    ISTEP(data->kaleidoMode_p) = 1;

    data->kaleidoStartP_p = secure_i_param("Kaleido Start 1/N");
    IVAL(data->kaleidoStartP_p) = 60;
    IMIN(data->kaleidoStartP_p) = 1;
    IMAX(data->kaleidoStartP_p) = 256;
    ISTEP(data->kaleidoStartP_p) = 1;

    data->kaleidoStopP_p = secure_i_param("Kaleido Stop 1/N");
    IVAL(data->kaleidoStopP_p) = 63;
    IMIN(data->kaleidoStopP_p) = 1;
    IMAX(data->kaleidoStopP_p) = 64;
    ISTEP(data->kaleidoStopP_p) = 1;

    data->kaleidoManual_bp = secure_b_param("Kaleido Manual", 0);

    data->kaleidoManualN_p = secure_i_param("Kaleido N");
    IVAL(data->kaleidoManualN_p) = 6;
    IMIN(data->kaleidoManualN_p) = 2;
    IMAX(data->kaleidoManualN_p) = 16;
    ISTEP(data->kaleidoManualN_p) = 1;

    data->kaleidoManualAngle_p = secure_f_param("Kaleido Angle");
    FVAL(data->kaleidoManualAngle_p) = 0.0f;
    FMIN(data->kaleidoManualAngle_p) = 1.2f;
    FMAX(data->kaleidoManualAngle_p) = 3.1415f;
    FSTEP(data->kaleidoManualAngle_p) = 0.01f;

    data->wipeWobble_p = secure_i_param("Wipe Wobble");
    IVAL(data->wipeWobble_p) = 10;
    IMIN(data->wipeWobble_p) = 0;
    IMAX(data->wipeWobble_p) = 50;
    ISTEP(data->wipeWobble_p) = 1;

    data->foldTransition_p = secure_i_param("Fold Transition");
    IVAL(data->foldTransition_p) = 1;
    IMIN(data->foldTransition_p) = 0;
    IMAX(data->foldTransition_p) = 2;
    ISTEP(data->foldTransition_p) = 1;

    data->wipeFrames_p = secure_i_param("Wipe Frames");
    IVAL(data->wipeFrames_p) = 20;
    IMIN(data->wipeFrames_p) = 2;
    IMAX(data->wipeFrames_p) = 120;
    ISTEP(data->wipeFrames_p) = 1;

    data->wipeRing_p = secure_i_param("Wipe Ring");
    IVAL(data->wipeRing_p) = 0;
    IMIN(data->wipeRing_p) = 0;
    IMAX(data->wipeRing_p) = 16;
    ISTEP(data->wipeRing_p) = 1;

    data->zoomMode_p = secure_i_feedback("Zoom Mode");
    IVAL(data->zoomMode_p) = 0;
    IMIN(data->zoomMode_p) = 0;
    IMAX(data->zoomMode_p) = NB_ZOOM_MODES - 1;
    ISTEP(data->zoomMode_p) = 1;

    data->vitesse_p = secure_i_feedback("Vitesse");
    IVAL(data->vitesse_p) = 128;
    IMIN(data->vitesse_p) = 0;
    IMAX(data->vitesse_p) = 255;
    ISTEP(data->vitesse_p) = 1;

    data->reverse_p = secure_i_feedback("Reverse");
    IVAL(data->reverse_p) = 0;
    IMIN(data->reverse_p) = 0;
    IMAX(data->reverse_p) = 1;
    ISTEP(data->reverse_p) = 1;

    data->middleX_p = secure_i_feedback("Middle X");
    IVAL(data->middleX_p) = 0;
    IMIN(data->middleX_p) = 0;
    IMAX(data->middleX_p) = 1000000;
    ISTEP(data->middleX_p) = 1;

    data->middleY_p = secure_i_feedback("Middle Y");
    IVAL(data->middleY_p) = 0;
    IMIN(data->middleY_p) = 0;
    IMAX(data->middleY_p) = 1000000;
    ISTEP(data->middleY_p) = 1;

    data->noisify_p = secure_i_feedback("Noisify");
    IVAL(data->noisify_p) = 2;
    IMIN(data->noisify_p) = 0;
    IMAX(data->noisify_p) = 2;
    ISTEP(data->noisify_p) = 1;

    data->waveFx_p = secure_i_feedback("Wave FX");
    IVAL(data->waveFx_p) = 0;
    IMIN(data->waveFx_p) = 0;
    IMAX(data->waveFx_p) = 1;
    ISTEP(data->waveFx_p) = 1;

    data->hypercosFx_p = secure_i_feedback("Hypercos FX");
    IVAL(data->hypercosFx_p) = 0;
    IMIN(data->hypercosFx_p) = 0;
    IMAX(data->hypercosFx_p) = 1;
    ISTEP(data->hypercosFx_p) = 1;

    data->params = plugin_parameters ("Zoom Filter", 20);
    data->params.params[0] = &data->enabled_bp;
    data->params.params[1] = &data->freeze_bp;
    data->params.params[2] = &data->kaleidoMode_p;
    data->params.params[3] = &data->kaleidoStartP_p;
    data->params.params[4] = &data->kaleidoStopP_p;
    data->params.params[5] = &data->zoomMode_p;
    data->params.params[6] = &data->vitesse_p;
    data->params.params[7] = &data->reverse_p;
    data->params.params[8] = &data->middleX_p;
    data->params.params[9] = &data->middleY_p;
    data->params.params[10] = &data->noisify_p;
    data->params.params[11] = &data->waveFx_p;
    data->params.params[12] = &data->hypercosFx_p;
    data->params.params[13] = &data->kaleidoManual_bp;
    data->params.params[14] = &data->kaleidoManualN_p;
    data->params.params[15] = &data->kaleidoManualAngle_p;
    data->params.params[16] = &data->foldTransition_p;
    data->params.params[17] = &data->wipeFrames_p;
    data->params.params[18] = &data->wipeRing_p;
    data->params.params[19] = &data->wipeWobble_p;
    
    _this->params = &data->params;
    _this->fx_data = (void*)data;
    
    /** modif d'optim by Jeko : precalcul des 4 coefs resultant des 2 pos */
    generatePrecalCoef(data->precalCoef);
}

static void zoomFilterVisualFXWrapper_free (struct _VISUAL_FX *_this)
{
    ZoomFilterFXWrapperData *data = (ZoomFilterFXWrapperData*)_this->fx_data;
    if (data->brutS) free (data->freebrutS);
    if (data->brutD) free (data->freebrutD);
    if (data->brutT) free (data->freebrutT);
    if (data->wipeLuma) free (data->wipeLuma);
    free (data->firedec);
    free (data->params.params);
    free(_this->fx_data);
}

static void zoomFilterVisualFXWrapper_apply (struct _VISUAL_FX *_this, Pixel *src, Pixel *dest, PluginInfo *info)
{
}

VisualFX zoomFilterVisualFXWrapper_create(void)
{
    VisualFX fx;
    fx.init = zoomFilterVisualFXWrapper_init;
    fx.free = zoomFilterVisualFXWrapper_free;
    fx.apply = zoomFilterVisualFXWrapper_apply;
    return fx;
}


/* TODO : MOVE THIS AWAY */

void pointFilter (PluginInfo *goomInfo, Pixel * pix1, Color c, float t1, float t2, float t3, float t4, Uint cycle)
{
    Uint x = (Uint) ((int) (goomInfo->screen.width / 2)
                     + (int) (t1 * cos ((float) cycle / t3)));
    Uint y = (Uint) ((int) (goomInfo->screen.height/2)
                     + (int) (t2 * sin ((float) cycle / t4)));
    
    if ((x > 1) && (y > 1) && (x < goomInfo->screen.width - 2) && (y < goomInfo->screen.height - 2)) {
        setPixelRGB (goomInfo, pix1, x + 1, y, c);
        setPixelRGB (goomInfo, pix1, x, y + 1, c);
        setPixelRGB (goomInfo, pix1, x + 1, y + 1, WHITE);
        setPixelRGB (goomInfo, pix1, x + 2, y + 1, c);
        setPixelRGB (goomInfo, pix1, x + 1, y + 2, c);
    }
}
