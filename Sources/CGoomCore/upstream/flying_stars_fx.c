#include "goom_fx.h"
#include "goom_plugin_info.h"
#include "goom_tools.h"

#include "mathtools.h"
#include <math.h>
/* scale applied to the transformation buffer's velocity when accelerating
 * particules */
#define FS_FLOW_FORCE 0.5f
/* max particule speed, as a fraction of the screen width (px/frame):
 * extreme transformation buffers would otherwise drag particules into
 * huge streaks */
#define FS_MAX_SPEED 0.01f


/* flow mode: number of particules spawned per frame while the effect
 * is active */
#define GOOM_FS_FLOW_SPAWN 5


/* calibration mode: define as an FX mode (FLOW_UNIFORM_FX, FLOW_SHAPE_FX,
 * FLOW_WAVEFORM_FX, FLOW_EMITTERS_FX or FLOW_RADAR_FX) to force that
 * effect, ignoring mode switches. Comment out for normal use. */
/* #define GOOM_FS_CALIBRATING FLOW_RADAR_FX */

/* TODO:-- FAIRE PROPREMENT... BOAH... */
#define NCOL 15

/*static const int colval[] = {
0xfdf6f5,
0xfae4e4,
0xf7d1d1,
0xf3b6b5,
0xefa2a2,
0xec9190,
0xea8282,
0xe87575,
0xe46060,
0xe14b4c,
0xde3b3b,
0xdc2d2f,
0xd92726,
0xd81619,
0xd50c09,
0
};
*/
static const int colval[] = {
	0x1416181a,
	0x1419181a,
	0x141f181a,
	0x1426181a,
	0x142a181a,
	0x142f181a,
	0x1436181a,
	0x142f1819,
	0x14261615,
	0x13201411,
	0x111a100a,
	0x0c180508,
	0x08100304,
	0x00050101,
	0x0
};


/* The different modes of the visual FX.
 * Put this values on fx_mode */

#define FLOW_UNIFORM_FX 0
#define FLOW_SHAPE_FX 1
#define FLOW_WAVEFORM_FX 2
#define FLOW_EMITTERS_FX 3
#define FLOW_RADAR_FX 4
#define LAST_FX 5

/* number of shapes cycled by FLOW_SHAPE_FX */
#define NB_SHAPES 3
/* number of orbiting sources in FLOW_EMITTERS_FX */
#define NB_EMITTERS 3
/* points stamped at once on goom events (shape outline, wave, line) */
#define GOOM_FS_BURST_PTS 128

typedef struct _FS_STAR {
	float x,y;
	float vx,vy;
	float ax,ay;
	float age,vage;
} Star;

typedef struct _FS_DATA{

	int fx_mode;
	int nbStars;

	int maxStars;
	Star *stars;

		int shape_idx;      /* current shape in FLOW_SHAPE_FX */
	float shape_rot;    /* rotation of the shape (cos256 units) */
	float shape_t;      /* trace position along the outline (cos256 units) */
	float radar_ang;    /* angle of the radar line (cos256 units) */

	PluginParam flow_coupling_p;
	PluginParam nbStars_p;
	PluginParam nbStars_limit_p;
	PluginParam fx_mode_p;

	PluginParameters params;
} FSData;

static void fs_init(VisualFX *_this, PluginInfo *info) {
	
	FSData *data;
	data = (FSData*)malloc(sizeof(FSData));

	data->fx_mode = FLOW_UNIFORM_FX;
	data->maxStars = 4096;
	data->stars = (Star*)malloc(data->maxStars * sizeof(Star));
	data->nbStars = 0;
	data->shape_idx = 0;
	data->shape_rot = 0.0f;
	data->shape_t = 0.0f;
	data->radar_ang = 0.0f;

	data->nbStars_limit_p = secure_i_param ("Max Number of Particules");
	IVAL(data->nbStars_limit_p) = 512;
	IMIN(data->nbStars_limit_p) = 0;
	IMAX(data->nbStars_limit_p) = data->maxStars;
	ISTEP(data->nbStars_limit_p) = 64;
	data->flow_coupling_p = secure_i_param ("Flow Coupling");
	IVAL(data->flow_coupling_p) = 30;
	IMIN(data->flow_coupling_p) = 0;
	IMAX(data->flow_coupling_p) = 100;
	ISTEP(data->flow_coupling_p) = 1;

	data->fx_mode_p = secure_i_param ("FX Mode");
	IVAL(data->fx_mode_p) = data->fx_mode;
	IMIN(data->fx_mode_p) = 1;
	IMAX(data->fx_mode_p) = LAST_FX;
	ISTEP(data->fx_mode_p) = 1;

	data->nbStars_p = secure_f_feedback ("Number of Particules (% of Max)");

	data->params = plugin_parameters ("Particule System", 5);
	data->params.params[0] = &data->fx_mode_p;
	data->params.params[1] = &data->nbStars_limit_p;
	data->params.params[2] = &data->flow_coupling_p;
	data->params.params[3] = 0;
	data->params.params[4] = &data->nbStars_p;

	_this->params = &data->params;
	_this->fx_data = (void*)data;
}

static void fs_free(VisualFX *_this) {
        FSData *data = (FSData*)_this->fx_data;
        free (data->stars);
        free (data->params.params);
	free (data);
}


/**
 * Cree une nouvelle 'bombe', c'est a dire une particule appartenant a une fusee d'artifice.
 */
static void addABomb (FSData *fs, int mx, int my, float radius, float vage, float gravity, PluginInfo *info) {

	int i = fs->nbStars;
	float ro;
	int theta;

	if (fs->nbStars >= fs->maxStars)
		return;
	fs->nbStars++;

	fs->stars[i].x = mx;
	fs->stars[i].y = my;

	ro = radius * (float)goom_irand(info->gRandom,100) / 100.0f;
	ro *= (float)goom_irand(info->gRandom,100)/100.0f + 1.0f;
	theta = goom_irand(info->gRandom,256);

	fs->stars[i].vx = ro * cos256[theta];
	fs->stars[i].vy = -0.2f + ro * sin256[theta];

	fs->stars[i].ax = 0;
	fs->stars[i].ay = gravity;

	fs->stars[i].age = 0;
	if (vage < 0.01f)
		vage = 0.01f;
	fs->stars[i].vage = vage;
}


/**
 * Met a jour la position et vitesse d'une particule.
 */
static void updateStar (Star *s) {
	s->x+=s->vx;
	s->y+=s->vy;
	s->vx+=s->ax;
	s->vy+=s->ay;
	s->age+=s->vage;
}


/**
 * 
 * outline point of the current shape; t in cos256 units (256 per turn) */
static void fs_shape_point (FSData *data, PluginInfo *info, float t, int *px, int *py) {

	float R = info->screen.height / 3.0f;
	int it = ((int)t) & 255;
	float x, y;

	switch (data->shape_idx) {
		case 1: { /* star: 5 branches, alternating outer/inner vertices */
			float seg = t * (10.0f / 256.0f);
			float fseg = seg - (float)(int)seg;
			float r = ((int)seg & 1) ? (0.4f + 0.6f*fseg) : (1.0f - 0.6f*fseg);
			x = R * r * cos256[it];
			y = R * r * sin256[it];
			break;
		}
		case 2: { /* heart (y flipped: screen y goes down) */
			float s = sin256[it];
			x = R * s*s*s;
			y = -R * (13.0f*cos256[it] - 5.0f*cos256[(2*it)&255]
					- 2.0f*cos256[(3*it)&255] - cos256[(4*it)&255]) * (1.0f/16.0f);
			break;
		}
		default: /* circle */
			x = R * cos256[it];
			y = R * sin256[it];
			break;
	}

	/* slow rotation around the screen center */
	{
		int ir = ((int)data->shape_rot) & 255;
		float rx = x*cos256[ir] - y*sin256[ir];
		float ry = x*sin256[ir] + y*cos256[ir];
		*px = info->screen.width/2 + (int)rx;
		*py = info->screen.height/2 + (int)ry;
	}
}

/* spawn one particule on the current shape's outline, advancing the trace */
static void fs_spawn_shape (FSData *data, PluginInfo *info) {

	int x, y;

	fs_shape_point (data, info, data->shape_t, &x, &y);
	addABomb (data, x, y, 0.1f, 0.18f, 0.0f, info);

	/* a full outline is traced in GOOM_FS_BURST_PTS calls */
	data->shape_t += 256.0f / GOOM_FS_BURST_PTS;
	if (data->shape_t >= 256.0f)
		data->shape_t -= 256.0f;
}

/* spawn one particule on the waveform of audio sample s */
static void fs_spawn_wave (FSData *data, PluginInfo *info, int s) {

	int channel = info->cycle & 1;
	int x = s * info->screen.width / 512;
	int y = info->screen.height/2
			+ (info->sound.samples[channel][s] * info->screen.height) / (32768*4);

	addABomb (data, x, y, 0.1f, 0.3f, 0.0f, info);
}

/* position of orbiting source e */
static void fs_emitter_pos (PluginInfo *info, int e, int *px, int *py) {

	/* cos256 units: one source runs backwards */
	float ang = (float)info->cycle * (0.4f + 0.25f*e) * (e==2 ? -1.0f : 1.0f)
			+ e * (256.0f / NB_EMITTERS);
	float rad = info->screen.height * (0.15f + 0.1f * info->sound.volume);
	int ia = ((int)ang) & 255;

	*px = info->screen.width/2 + (int)(rad * cos256[ia]);
	*py = info->screen.height/2 + (int)(rad * sin256[ia]);
}

/* spawn one particule on the radar line, at signed distance r from center */
static void fs_spawn_radar (FSData *data, PluginInfo *info, float r) {

	int ia = ((int)data->radar_ang) & 255;

	addABomb (data,
			info->screen.width/2 + (int)(r * cos256[ia]),
			info->screen.height/2 + (int)(r * sin256[ia]),
			0.1f, 0.2f, 0.0f, info);
}

/* continuous spawn: a few particules per frame, following the active
 * mode's pattern, with almost no initial velocity so the zoom field
 * drives them */
static void fs_spawn_continuous (FSData *data, PluginInfo *info) {

	int i;

	switch (data->fx_mode) {
		case FLOW_SHAPE_FX:
			for (i=0;i<GOOM_FS_FLOW_SPAWN;++i)
				fs_spawn_shape (data, info);
			data->shape_rot += 0.2f;
			break;
		case FLOW_WAVEFORM_FX:
			for (i=0;i<GOOM_FS_FLOW_SPAWN;++i)
				fs_spawn_wave (data, info, goom_irand(info->gRandom,512));
			break;
		case FLOW_EMITTERS_FX:
			for (i=0;i<NB_EMITTERS;++i) {
				int x, y;
				fs_emitter_pos (info, i, &x, &y);
				addABomb (data, x, y, 0.1f, 0.25f, 0.0f, info);
				addABomb (data, x, y, 0.1f, 0.25f, 0.0f, info);
			}
			break;
		case FLOW_RADAR_FX:
			for (i=0;i<GOOM_FS_FLOW_SPAWN;++i)
				fs_spawn_radar (data, info,
						(float)(goom_irand(info->gRandom,info->screen.height) - info->screen.height/2));
			data->radar_ang += 0.3f;
			break;
		default: /* FLOW_UNIFORM_FX */
			for (i=0;i<GOOM_FS_FLOW_SPAWN;++i)
				addABomb (data,
						goom_irand(info->gRandom,info->screen.width),
						goom_irand(info->gRandom,info->screen.height),
						0.1f, 0.2f, 0.0f, info);
			break;
	}
}

/**
 * Burst of new particules at the moment of a sound event: a denser
 * emission of the active mode's pattern.
 */
static void fs_sound_event_occured(VisualFX *_this, PluginInfo *info) {

	FSData *data = (FSData*)_this->fx_data;
	int i;
	int max = (int)((1.0f+info->sound.goomPower)*goom_irand(info->gRandom,150)) + 100;

	switch (data->fx_mode) {
		case FLOW_SHAPE_FX:
			/* stamp the whole outline, then switch to the next shape */
			for (i=0;i<GOOM_FS_BURST_PTS;++i)
				fs_spawn_shape (data, info);
			data->shape_idx = (data->shape_idx + 1) % NB_SHAPES;
			break;
		case FLOW_WAVEFORM_FX:
			/* stamp the whole current wave */
			for (i=0;i<512;i+=(512/GOOM_FS_BURST_PTS))
				fs_spawn_wave (data, info, i);
			break;
		case FLOW_EMITTERS_FX:
			/* velocity kick at each source */
			for (i=0;i<NB_EMITTERS;++i) {
				int x, y, k;
				fs_emitter_pos (info, i, &x, &y);
				for (k=0;k<16;++k)
					addABomb (data, x, y, 1.0f, 0.2f, 0.0f, info);
			}
			break;
		case FLOW_RADAR_FX:
			/* stamp the whole line */
			for (i=0;i<GOOM_FS_BURST_PTS;++i)
				fs_spawn_radar (data, info,
						((float)(i - GOOM_FS_BURST_PTS/2) / (GOOM_FS_BURST_PTS/2)) * (info->screen.height/2));
			break;
		default:
			/* FLOW_UNIFORM_FX: scatter all over the screen */
			max = max * info->screen.height / 800;
			for (i=0;i<max;++i)
				addABomb (data,
						goom_irand(info->gRandom,info->screen.width),
						goom_irand(info->gRandom,info->screen.height),
						0.1f, 0.2f, 0.0f, info);
			break;
	}
}


/**
 * Main methode of the FX.
 */
static void fs_apply(VisualFX *_this, Pixel *src, Pixel *dest, PluginInfo *info) {

	int i;
	int col;
	float flow_coupling;
	float vmax2;
	FSData *data = (FSData*)_this->fx_data;

	/* Get the new parameters values */
	flow_coupling = (float)IVAL(data->flow_coupling_p) / 100.0f;
	vmax2 = FS_MAX_SPEED * info->screen.width;
	vmax2 *= vmax2;
	FVAL(data->nbStars_p) = (data->maxStars > 0) ? (float)data->nbStars / (float)data->maxStars : 0.0f;
	data->nbStars_p.change_listener(&data->nbStars_p);
	data->maxStars = IVAL(data->nbStars_limit_p);
	data->fx_mode = IVAL(data->fx_mode_p);

	
#ifdef GOOM_FS_CALIBRATING
	/* calibration: force one effect, ignoring mode switches */
	data->fx_mode = GOOM_FS_CALIBRATING;
#endif

	/* look for events */
	if (info->sound.timeSinceLastGoom < 1) {
		fs_sound_event_occured(_this, info);
#ifndef GOOM_FS_CALIBRATING
		if (goom_irand(info->gRandom,20)==1) {
			IVAL(data->fx_mode_p) = goom_irand(info->gRandom,(LAST_FX*3));
			data->fx_mode_p.change_listener(&data->fx_mode_p);
		}
#endif
	}

	/* flow mode: continuously spawn the active mode's pattern, with almost no
	 * initial velocity so the zoom field drives the particules */
	fs_spawn_continuous (data, info);

	/* update particules */
	for (i=0;i<data->nbStars;++i) {
		
		/* accelerate the particule with the zoom filter's transformation
		 * buffer: relax its velocity towards the velocity of the image
		 * content at its position. The field is the flow the content really
		 * travels, folded states included (bounded, mirror-consistent, but
		 * flipped across the mirror seams). */
		if (flow_coupling > 0.0f) {
			float fvx, fvy;
			zoomFilterGetVelocity (info, data->stars[i].x, data->stars[i].y, &fvx, &fvy);
			
			fvx *= FS_FLOW_FORCE;
			fvy *= FS_FLOW_FORCE;
			data->stars[i].vx += (fvx - data->stars[i].vx) * flow_coupling;
			data->stars[i].vy += (fvy - data->stars[i].vy) * flow_coupling;
		}
		/* cap the particule speed (see FS_MAX_SPEED) */
		{
			float sp2 = data->stars[i].vx*data->stars[i].vx
					+ data->stars[i].vy*data->stars[i].vy;
			if (sp2 > vmax2) {
				float k = sqrtf (vmax2 / sp2);
				data->stars[i].vx *= k;
				data->stars[i].vy *= k;
			}
		}

		updateStar(&data->stars[i]);

		/* dead particule */
		if (data->stars[i].age>=NCOL)
			continue;

		/* choose the color of the particule */
		col = colval[(int)data->stars[i].age];

		/* draws the particule */
		info->methods.draw_line(dest,(int)data->stars[i].x,(int)data->stars[i].y,
				(int)(data->stars[i].x-data->stars[i].vx*6),
				(int)(data->stars[i].y-data->stars[i].vy*6),
				col,
				(int)info->screen.width, (int)info->screen.height);
		info->methods.draw_line(dest,(int)data->stars[i].x,(int)data->stars[i].y,
				(int)(data->stars[i].x-data->stars[i].vx*2),
				(int)(data->stars[i].y-data->stars[i].vy*2),
				col,
				(int)info->screen.width, (int)info->screen.height);
	}

	/* look for dead particules */
	for (i=0;i<data->nbStars;) {

		if ((data->stars[i].x > info->screen.width + 64)
				||((data->stars[i].vy>=0)&&(data->stars[i].y - 16*data->stars[i].vy > info->screen.height))
				||(data->stars[i].x < -64)
				||(data->stars[i].age>=NCOL)) {
			data->stars[i] = data->stars[data->nbStars-1];
			data->nbStars--;
		}
		else ++i;
	}
}

VisualFX flying_star_create(void) {
	VisualFX vfx = {
		init: fs_init,
		free: fs_free,
		apply: fs_apply,
		fx_data: 0
	};
	return vfx;
}
