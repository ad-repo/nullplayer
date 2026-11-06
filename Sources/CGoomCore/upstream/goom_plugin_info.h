#ifndef _PLUGIN_INFO_H
#define _PLUGIN_INFO_H

#include "goom_typedefs.h"

#include "goom_config.h"

#include "goom_graphic.h"
#include "goom_config_param.h"
#include "goom_visual_fx.h"
#include "goom_filters.h"
#include "goom_tools.h"
//#include "goomsl.h"

typedef struct {
	char drawIFS;
	char drawPoints;
	char drawTentacle;

	char drawScope;
	int farScope;

	int rangemin;
	int rangemax;
} GoomState;

#define STATES_MAX_NB 128

/**
 * Gives informations about the sound.
 */
struct _SOUND_INFO {

	/* nota : a Goom is just a sound event... */

	int timeSinceLastGoom;   /* >= 0 */
	float goomPower;         /* power of the last Goom [0..1] */

	int timeSinceLastBigGoom;   /* >= 0 */

	float volume;     /* [0..1] */
	short samples[2][512];

	/* other "internal" datas for the sound_tester */
	float goom_limit; /* auto-updated limit of goom_detection */
	float bigGoomLimit;
	float accelvar;   /* acceleration of the sound - [0..1] */
	float speedvar;   /* speed of the sound - [0..100] */
	int allTimesMax;
	int totalgoom;    /* number of goom since last reset
			   * (a reset every 64 cycles) */

	float prov_max;   /* accel max since last reset */

	int cycle;

	/* private */
	PluginParam volume_p;
	PluginParam speed_p;
	PluginParam accel_p;
	PluginParam goom_limit_p;
    PluginParam goom_power_p;
	PluginParam last_goom_p;
	PluginParam last_biggoom_p;
	PluginParam biggoom_speed_limit_p;
	PluginParam biggoom_factor_p;

	PluginParameters params; /* contains the previously defined parameters. */
};


/* geometric wipe blend ("center-out" frontier between brutS and brutD).
 * NULL = LINEAR (the kernel uses buffratio exactly as before).
 * WIPE_RADIUS / WIPE_SEAMS ignore buffratio and select per pixel:
 * inside the frontier the new map (brutD), outside the old one
 * (brutS), with a soft lerp band of `ring` pixels (<= 0 = hard step).
 * wobble/luma: per-pixel frontier jitter driven by an invariant color
 * field (resx*resy bytes, one entry per output pixel); NULL luma or
 * wobble <= 0 disables the jitter. */
typedef struct {
	int   mode;       /* 0 = LINEAR (uses buffratio), 1 = WIPE_RADIUS, 2 = WIPE_SEAMS */
	float progress;   /* c in [0,1]; global endpoint overrides */
	float ring;       /* soft band width px; <= 0 = hard step */
	float cx, cy;     /* frontier center, pixels */
	float n1x, n1y;   /* WIPE_SEAMS: unit normal of fold line 0 */
	int   foldCount;  /* WIPE_SEAMS: N seam lines at angle step PI/N */
	float wobble;     /* 0..0.5 per-pixel frontier jitter spread */
	const unsigned char *luma; /* per-output-pixel invariant color field (resx*resy bytes), NULL = no wobble */
} ZoomBlend;

/**
 * Allows FXs to know the current state of the plugin.
 */
struct _PLUGIN_INFO {

	/* public datas */

	int nbParams;
	PluginParameters *params;

	/* private datas */

	struct _SIZE_TYPE {
		int width;
		int height;
		int size;   /* == screen.height * screen.width. */
	} screen;

	SoundInfo sound;

	int nbVisuals;
	VisualFX **visuals; /* pointers on all the visual fx */

	/** The known FX */
	VisualFX convolve_fx;
	VisualFX star_fx;
	VisualFX zoomFilter_fx;
	VisualFX tentacles_fx;
	VisualFX ifs_fx;

	/** image buffers */
	guint32 *pixel;
	guint32 *back;
	Pixel *p1, *p2;
	Pixel *conv;
  Pixel *outputBuf;

	/** state of goom */
	guint32 cycle;
	GoomState states[STATES_MAX_NB];
	int statesNumber;
	int statesRangeMax;

	GoomState *curGState;

	/** effet de ligne.. */
	GMLine *gmline1;
	GMLine *gmline2;

	/** sinus table */
	int sintable[0x10000];

	/* INTERNALS */
	
	/** goom_update internals.
	 * I took all static variables from goom_update and put them here.. for the moment.
	 */
	struct {
		int freezeOn;              /* Freeze actif : plus de changement de config de zoom */
		int kaleidoManualOn;       /* dernier etat connu du mode manuel */
		int kaleidoManualN;        /* dernier N manuel delivre au filtre */
		float kaleidoManualAngle;  /* dernier angle manuel delivre au filtre */
		int lockvar;               /* pour empecher de nouveaux changements */
		int goomvar;               /* boucle des gooms */
		int loopvar;               /* mouvement des points */
		int stop_lines;
		int ifs_incr;              /* dessiner l'ifs (0 = non: > = increment) */
		int decay_ifs;             /* disparition de l'ifs */
		int recay_ifs;             /* dedisparition de l'ifs */
		int cyclesSinceLastChange; /* nombre de Cycle Depuis Dernier Changement */
		int drawLinesDuration;     /* duree de la transition entre afficher les lignes ou pas */
		int lineMode;              /* l'effet lineaire a dessiner */
		float switchMultAmount;    /* SWITCHMULT (29.0f/30.0f) */
		int switchIncrAmount;      /* 0x7f */
		float switchMult;          /* 1.0f */
		int switchIncr;            /*  = SWITCHINCR; */
		int stateSelectionRnd;
		int stateSelectionBlocker;
		int previousZoomSpeed;
		int timeOfTitleDisplay;
		int holdMode;              /* NullPlayer port: 1 = Goom does not change the zoom mode itself */
                char titleText[1024];
		ZoomFilterData zoomFilterData;                
	} update;

	struct {
		int numberOfLinesInMessage;
		char message[0x800];
		int affiche;
		int longueur;
	} update_message;

	struct {
		void (*draw_line) (Pixel *data, int x1, int y1, int x2, int y2, int col, int screenx, int screeny);
		void (*zoom_filter) (int sizeX, int sizeY, Pixel *src, Pixel *dest, int *brutS, int *brutD, int buffratio, int precalCoef[16][16], const ZoomBlend *blend);
	} methods;
	
	GoomRandom *gRandom;
    
    //GoomSL *scanner;
    //GoomSL *main_scanner;
    //const char *main_script_str;
};

void plugin_info_init(PluginInfo *p, int nbVisual); 

/* i = [0..p->nbVisual-1] */
void plugin_info_add_visual(PluginInfo *p, int i, VisualFX *visual);

#endif
