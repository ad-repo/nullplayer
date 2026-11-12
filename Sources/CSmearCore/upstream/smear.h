//////////////////////////////////////////////////////////////////////
//
// Just a generic include file for smear.  Includes all the others
// that are required.  Also a bit of config here, a bit of debug
// there.
//
// Modified for NullPlayer (2026-11-12): portable includes in place of
// the Windows ones; the thread, title-text, shared-memory and settings
// options are gone; every global the renderer kept is a field of
// SmearState, so each host has its own Smear.  See LICENSE.TXT.
//
//////////////////////////////////////////////////////////////////////

#ifndef	__SMEAR_H__
#define	__SMEAR_H__

#include <stdarg.h>
#include <stdio.h>
#include <math.h>
#include <string.h>
#include <strings.h>
#include <stdlib.h>
#include <stdint.h>

#define	stricmp	strcasecmp

//////////////////////////////////////////////////////////////////////////////////////
// This determines how long (in ms) the system tries to build a map per frame
// The higher this is the slow things run, but the quicker you can change
// maps.
#define	MAP_FASTBUILD	25
#define	MAP_SLOWBUILD	5

//////////////////////////////////////////////////////////////////////////////////////
// These defines determine how often the particle system sees if it needs to
// add more particles and how many is the maximum number of particles to run
#define	MAX_PARTICLES_RUNNING	3
#define	PARTICLE_TRY_TIMEOUT	1000		// Once per second

//////////////////////////////////////////////////////////////////////////////////////
// What is the maximum number of each script type
#define	MAX_ENVIRONMENTS	1024

//////////////////////////////////////////////////////////////////////////////////////
// How much wave data is supplied by sonique?
#define WAVE_DATA_SIZE	512

#include "parser.h"
#include "fnlist.h"

typedef	struct	_xycl
{
	short	x[512];
	short	y[512];
	short	color[512];
	short	last;
}	XYCL;

typedef	struct	_scriptList
{
	Environment	*list[MAX_ENVIRONMENTS];
	int		count;
}	ScriptList;

// Everything smear.c, file.c and the runtime kept in globals and function
// statics, one per Smear.
typedef	struct	SmearState
{
	uint64_t	startNs;
	unsigned int	randSeed;	// smearRand's state: libc rand() is shared by every core

	ScriptList	moves, colors, waveforms, particles;
	Environment	*heldMove;
	int		moveForced;

	AudioData	audioData;
	signed char	waveform[2][WAVE_DATA_SIZE];
	unsigned char	spectrum[2][256];
	double		matrix3d[3][3];

	uint32_t	*_Video;
	int		_width;
	int		_height;
	int		_myHeight;
	int		_pitch;

	uint32_t	colorMap[256];
	uint32_t	fadeMaps[2][256];

	Environment	*_global_move_ep;
	uint32_t	*mapsData[2];
	int		mapWidth;
	int		mapHeight;
	int		mapLine;
	int		mapEndTime;
	int		mapRebuildTime;
	int		mapMerging;
	int		mapMergeTime;
	int		mapMergeEnd;
	int		mapMergeFactor;

	int		lineLastWidth;
	int		lineLastHeight;
	int		lineLastLine;
	int		lineLastX;

	unsigned char	*sbData[2];
	unsigned char	*sbAllocs[2];
	int		sbWidth;
	int		sbHeight;
	unsigned char	sbFadeValue[256];

	XYCL		xycls[2][MAX_WAVEFORM_PATHS];

	int		waveformChanging;
	int		waveformStartTime;
	int		waveformEndTime;
	Environment	*waveformEnvironments[2];

	int		numRunning;
	Environment	*particleEnvironments[MAX_PARTICLES_RUNNING];
	int		particleState[MAX_PARTICLES_RUNNING];
	int		particleStartTime[MAX_PARTICLES_RUNNING];
	int		particleEndTime[MAX_PARTICLES_RUNNING];
	int		lastTry;

	int		colormapChanging;
	int		colormapStartTime;
	int		colormapEndTime;
	Environment	*colormapEnvironments[2];
}	SmearState;

// Milliseconds since this Smear started; stands in for GetTickCount().
extern	int	smearNow(SmearState *);
#define	smearRand(s)	rand_r(&(s)->randSeed)

extern	void	LoadEverything(SmearState *, const char *dir);
extern	Environment	*ChooseMoveScript(SmearState *);
extern	Environment	*ChooseColorScript(SmearState *);
extern	Environment	*ChooseWaveFormScript(SmearState *);
extern	Environment	*ChooseParticleScript(SmearState *);

extern	void	effectsDrawLine(SmearState *, int, int, int, int, int, int);
extern	void	effectsDrawPoint(SmearState *, int, int, int, int);
extern	void	effectsDrawParticle(SmearState *, int, int, int, int, int, int, int, int, int);
extern	void	effectsBufferLine(SmearState *, int, int, int, int, int, int);

#endif
