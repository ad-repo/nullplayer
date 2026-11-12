//////////////////////////////////////////////////////////////////////////////////////
//
// Sonique Visual Plugin Wrapper File
//
//   (c) 1999 Sonique Team
//       Edited by Rajest Singh (shock@ihug.com.au)
//       Edited futher by mykel (mykel@earthling.net)
//
// Modified for NullPlayer (2026-11-12), see LICENSE.TXT:
//   - Every global and function static is a field of SmearState, passed in; so is
//     the random generator (smearRand, in place of rand()).
//   - The map and screen buffers' allocations are checked: a failed one skips the frame.
//   - The x86 assembly of sbApplyMove and DwordCopy_Inline is gone; the move uses
//     upstream's own C version of the same loop (OLDsbApplyMove).
//   - The Sonique plugin entry points, VIS.INI settings, map thread, "map constant
//     merge"/"total mayhem" modes, title screen, song titles and click overlay are
//     gone. The settings are upstream's defaults, with the title screen disabled
//     (its quick first map is used instead): the text needed Windows GDI.
//   - Maps and colormaps are 32-bit (they were `unsigned long`, 64-bit on macOS, and
//     the colormap fade walks them four bytes at a time).
//   - The renderer is smearRender, called by SmearCore.c in place of visRender.
//   - effectsDrawLine plots through effectsDrawPoint (the same test and blend it had
//     inline) and scales by multiplying, not shifting a negative value.
//
//////////////////////////////////////////////////////////////////////////////////////

#include "smear.h"

#define	SIMPLE_RAND(n) (smearRand(s) % n)

// Upstream's VIS.INI defaults (1/10ths of seconds; chance in percent).
#define	ARG_MovemapHoldTime	150
#define	ARG_MovemapFadeTime	30
#define	ARG_ColormapHoldTime	130
#define	ARG_ColormapFadeTime	30
#define	ARG_WaveformHoldTime	150
#define	ARG_WaveformFadeTime	15
#define	ARG_ParticleHoldTime	100
#define	ARG_ParticleFadeTime	30
#define	ARG_LetterBoxPercent	100
#define	VALUE_ParticleChance	0.10

#define	SB_PIXEL(s, x, y)	((s)->sbData[0][(y) * (s)->sbWidth + (x)])


//////////////////////////////////////////////////////////////////////////////////////
//
// maps
//
// Handle map lists.  Various build functions.
//
//////////////////////////////////////////////////////////////////////////////////////

static void
mapFunctionExternalSetup(SmearState *s)
{
	s->_global_move_ep = ChooseMoveScript(s);
	if (s->_global_move_ep)
		SetupForRun(s->_global_move_ep);
}


// Fix the allocation, return 1 if map data was reallocated, -1 if that failed
static int
mapsCheckAllocation(SmearState *s)
{
	int		i;
	uint32_t	*mp;
	int		yadd;
	int		xadd;
	int		yv;
	int		x, y;

	if (s->mapWidth == s->_width &&
		s->mapHeight == s->_myHeight &&
		s->mapsData[0] != (uint32_t *)0 &&
		s->mapsData[1] != (uint32_t *)0)
		  return 0;

	s->mapWidth = s->_width;
	s->mapHeight = s->_myHeight;

	for (i = 0; i < 2; i++)
	{
		free(s->mapsData[i]);
		s->mapsData[i] = (uint32_t *)calloc((size_t)s->mapWidth * s->mapHeight * 2, sizeof(uint32_t));
	}
	if (s->mapsData[0] == (uint32_t *)0 || s->mapsData[1] == (uint32_t *)0)
	{
		s->mapWidth = s->mapHeight = -1;	// try again next frame
		return -1;
	}

	s->mapLine = 0;

	// The title screen is disabled: build the quickest and dirtiest map here..
	mp = s->mapsData[0];

	yadd = s->mapHeight / 2;
	xadd = s->mapWidth / 2;
	for (y = 0; y < s->mapHeight; y++)
	{
		yv = (y - yadd) * 64500 + (yadd << 16);
		for (x = 0; x < s->mapWidth; x++)
		{
			*(mp++) = (x - xadd) * 64500 + (xadd << 16);
			*(mp++) = yv;
		}
	}

	return 1;
}


// Swap the map pointers.
static inline void
mapsSwap(SmearState *s)
{
	uint32_t	*temp;

	temp = s->mapsData[0];
	s->mapsData[0] = s->mapsData[1];
	s->mapsData[1] = temp;
}


static int
mapsTimedBuildLines(SmearState *s, int ms)
{
	if (!s->_global_move_ep)
		return -1;

	do
	{
		if (s->mapLine >= s->mapHeight)
			return 1;

		if (TimedRunForLine(s->_global_move_ep, s->mapsData[1], s->_width, s->_myHeight, s->mapLine, &ms) == 0)
			s->mapLine++;

	} while (ms > 0);

	return 0;
}


// Handle the map stuff - just do it.  0 when the maps could not be allocated.
static int
mapsHandleMaps(SmearState *s)
{
	int	now;
	int	rv;

	now = smearNow(s);

	if (s->moveForced)
	{
		s->moveForced = 0;

		// Build a complete map
		mapFunctionExternalSetup(s);
		s->mapLine = 0;
		s->mapRebuildTime = MAP_FASTBUILD;
		s->mapEndTime = now;
		s->mapMergeTime = 100 * ARG_MovemapFadeTime * (SIMPLE_RAND(100) + 50) / 100;
	}


	if ((rv = mapsCheckAllocation(s)) < 0)
		return 0;

	if (rv == 1)
	{
		s->mapMerging = 0;
		mapFunctionExternalSetup(s);
		s->mapRebuildTime = (MAP_SLOWBUILD + MAP_FASTBUILD) >> 1;
		s->mapLine = 0;
		s->mapEndTime = now + 100 * ARG_MovemapHoldTime * (SIMPLE_RAND(100) + 50) / 200;
		s->mapMergeTime = 100 * ARG_MovemapFadeTime * (SIMPLE_RAND(100) + 50) / 100;
	}

	if (s->mapMerging)
	{
		if (now >= s->mapMergeEnd || s->mapMergeTime <= 0)
			s->mapMerging = 0;
		else
		{
			s->mapMergeFactor = (s->mapMergeEnd - now) * 256 / s->mapMergeTime;
			if (s->mapMergeFactor > 255)
				s->mapMergeFactor = 255;
			if (s->mapMergeFactor <= 0)
				s->mapMerging = 0;
		}

		if (s->mapMerging == 0)
		{
			mapsSwap(s);
			mapFunctionExternalSetup(s);
			s->mapRebuildTime = MAP_SLOWBUILD;
			s->mapLine = 0;
			s->mapEndTime = now + 100 * ARG_MovemapHoldTime * (SIMPLE_RAND(100) + 50) / 100;
			s->mapMergeTime = 100 * ARG_MovemapFadeTime * (SIMPLE_RAND(100) + 50) / 100;
		}
		else
			return 1;
	}

	if ((rv = mapsTimedBuildLines(s, s->mapRebuildTime)) == 1)
	{
		if (now >= s->mapEndTime)
		{
			s->mapMerging = 1;
			if (s->mapMergeTime > 3 * ARG_MovemapFadeTime * 100 / 2)
				s->mapMergeTime = 3 * ARG_MovemapFadeTime * 100 / 2;
			s->mapMergeEnd = now + s->mapMergeTime;
			s->mapMergeFactor = 255;
		}
	}

	if (rv == -1)
	{
		mapFunctionExternalSetup(s);

		s->mapRebuildTime = MAP_SLOWBUILD;
		s->mapLine = 0;
		s->mapEndTime = now + 100 * ARG_MovemapHoldTime * (SIMPLE_RAND(100) + 50) / 100;
		s->mapMergeTime = 100 * ARG_MovemapFadeTime * (SIMPLE_RAND(100) + 50) / 100;
	}
	return 1;
}


//////////////////////////////////////////////////////////////////////////////////////
//
// sb (screen buffer)
//
// Functions for handling the screen buffer.  This is a 0-255 value buffer that maps
// directly to the screen.
//
//////////////////////////////////////////////////////////////////////////////////////

static void
sbInitFadeValue(SmearState *s)
{
	int	i;

	for (i = 0; i < 256; i++)
		s->sbFadeValue[i] = (int)((double)i * (0.95 + (double)SIMPLE_RAND(500) / 10000.0));
}


static int
sbCheckAllocation(SmearState *s)
{
	int	i;
	size_t	size;

	if (s->sbWidth == -1)
		sbInitFadeValue(s);

	if (s->sbWidth == s->_width &&
		s->sbHeight == s->_myHeight &&
		s->sbData[0] != (unsigned char *)0 &&
		s->sbData[1] != (unsigned char *)0)
		  return 0;

	s->sbWidth = s->_width;
	s->sbHeight = s->_myHeight;

	// A row and a pixel of padding either side: the move reads the pixel right of and
	// the row below where it samples.
	size = (size_t)s->sbWidth * s->sbHeight + 2 * s->sbWidth + 2;
	for (i = 0; i < 2; i++)
	{
		free(s->sbAllocs[i]);
		s->sbAllocs[i] = (unsigned char *)calloc(size, 1);
		s->sbData[i] = s->sbAllocs[i] ? s->sbAllocs[i] + s->sbWidth + 1 : (unsigned char *)0;
	}
	if (s->sbData[0] == (unsigned char *)0 || s->sbData[1] == (unsigned char *)0)
	{
		s->sbWidth = s->sbHeight = -1;	// try again next frame
		return -1;
	}

	return 1;
}


// Swap the sb pointers.
static inline void
sbSwap(SmearState *s)
{
	unsigned char	*temp;

	temp = s->sbData[0];
	s->sbData[0] = s->sbData[1];
	s->sbData[1] = temp;
}


#define	INTERPOLATE16(a, b, v)	((a) + ((((b) - (a)) * (v)) >> 16))

// 0 when the maps or screen buffers could not be allocated.
static int
sbApplyMove(SmearState *s)
{
	uint32_t	*mp;
	uint32_t	*mp0;
	uint32_t	*mp1;
	unsigned char	*op;
	int		i;
	int		x;
	int		y;
	unsigned char	*offsetData;
	int		v1;
	int		v2;
	int		w;

	if (!mapsHandleMaps(s) || sbCheckAllocation(s) < 0)
		return 0;

	w = s->sbWidth;

	if (s->mapMerging && s->mapMergeFactor > 0 && s->mapMergeFactor < 255)
	{
		mp0 = s->mapsData[0];
		mp1 = s->mapsData[1];
		op = s->sbData[1];

		for (i = s->sbWidth * s->sbHeight; i > 0; i--, op++, mp0++, mp1++)
		{
			x = (((*mp1++) >> 4) * (256 - s->mapMergeFactor) + ((*mp0++) >> 4) * s->mapMergeFactor) >> 4;
			y = (((*mp1) >> 4) * (256 - s->mapMergeFactor) + ((*mp0) >> 4) * s->mapMergeFactor) >> 4;

			offsetData = s->sbData[0] + (x >> 16) + (y >> 16) * w;

			v1 = INTERPOLATE16(*(offsetData), *(offsetData + 1), x & 0xffff);
			v2 = INTERPOLATE16(*(offsetData + w), *(offsetData + w + 1), x & 0xffff);

			*op = s->sbFadeValue[INTERPOLATE16(v1, v2, y & 0xffff)];
		}
	}
	else
	{
		mp = s->mapsData[0];
		op = s->sbData[1];

		for (i = s->sbWidth * s->sbHeight; i > 0; i--, op++, mp++)
		{
			x = *mp++;
			y = *mp;

			offsetData = s->sbData[0] + (x >> 16) + (y >> 16) * w;

			v1 = INTERPOLATE16(*(offsetData), *(offsetData + 1), x & 0xffff);
			v2 = INTERPOLATE16(*(offsetData + w), *(offsetData + w + 1), x & 0xffff);

			*op = s->sbFadeValue[INTERPOLATE16(v1, v2, y & 0xffff)];
		}
	}

	sbSwap(s);
	return 1;
}


//////////////////////////////////////////////////////////////////////////////////////
//
// cmap (Colour Map)
//
// Functions for dealing with the colour map
//
//////////////////////////////////////////////////////////////////////////////////////

static void
cmapMapSBToVideo(SmearState *s)
{
	uint32_t	*op;
	uint32_t	*lop;
	unsigned char	*ip;
	int		x;
	int		y;
	int		ymin = (s->_height - s->_myHeight) / 2;

	op = s->_Video;
	ip = s->sbData[0];

	for (y = 0; y < ymin; y++, op += s->_pitch)
		memset(op, 0, sizeof(uint32_t) * s->_width);

	for (y = 0; y < s->_myHeight; y++, op += s->_pitch)
		for (lop = op, x = 0; x < s->_width; x++, lop++, ip++)
			*lop = s->colorMap[*ip];

	for (y = ymin + s->_myHeight; y < s->_height; y++, op += s->_pitch)
		memset(op, 0, sizeof(uint32_t) * s->_width);
}


//////////////////////////////////////////////////////////////////////////////////////
//
// actually do something here.
//
//////////////////////////////////////////////////////////////////////////////////////

void
effectsDrawPoint(SmearState *s, int x, int y, int color, int blend)
{
	if (x >= 1 && x < s->_width - 1 && y >= 1 && y < s->_myHeight - 1)
		switch (blend)
		{
		case 1:
			if ((short)(SB_PIXEL(s, x, y)) + color > 255)
				SB_PIXEL(s, x, y) = 255;
			else
				SB_PIXEL(s, x, y) += color;
			break;

		case 2:
			if ((short)(SB_PIXEL(s, x, y)) < color)
				SB_PIXEL(s, x, y) = color;

			break;
		default:
			SB_PIXEL(s, x, y) = color;
		}
}


void
effectsDrawLine(SmearState *s, int x1, int y1, int x2, int y2, int color, int blend)
{
	int	i;
	int	stx;
	int	sty;
	int	steps;

	if ((stx = x2 - x1) < 0)
		stx = - stx;

	if ((sty = y2 - y1) < 0)
		sty = - sty;

	if (stx > sty)
		steps = stx;
	else
		steps = sty;

	if (steps == 0)
		return;

	stx = ((x2 - x1) * 65536) / steps;
	sty = ((y2 - y1) * 65536) / steps;

	x1 *= 65536;
	y1 *= 65536;

	for (i = 0; i < steps; i++)
	{
		effectsDrawPoint(s, x1 >> 16, y1 >> 16, color, blend);

		x1 += stx;
		y1 += sty;
	}
}


static void
effectsInitBuffer(SmearState *s)
{
	memset(s->xycls, 0, sizeof(s->xycls));
}


void
effectsBufferLine(SmearState *s, int x, int y, int color, int whichDraw, int path, int pos)
{
	XYCL	*xyclp = &(s->xycls[whichDraw - 1][path]);
	int	i;

	xyclp->x[pos] = x;
	xyclp->y[pos] = y;
	xyclp->color[pos] = color;

	if (pos == 0)
	{
		xyclp->last = pos;
		return;
	}

	for (i = xyclp->last + 1; i < pos; i++)
	{
		// Interpolate X/Y
		xyclp->x[i] = xyclp->x[xyclp->last] +
			((xyclp->x[pos] - xyclp->x[xyclp->last]) *
			 (i - xyclp->last) / (pos - xyclp->last));
		xyclp->y[i] = xyclp->y[xyclp->last] +
			((xyclp->y[pos] - xyclp->y[xyclp->last]) *
			 (i - xyclp->last) / (pos - xyclp->last));
		xyclp->color[i] = xyclp->color[xyclp->last] +
			((xyclp->color[pos] - xyclp->color[xyclp->last]) *
			 (i - xyclp->last) / (pos - xyclp->last));
	}

	xyclp->last = pos;
}


static void
effectsDrawMerge(SmearState *s, int n0, int n1, int v0, int v1, int up)
{
	XYCL	*l0 = &(s->xycls[0][n0]);
	XYCL	*l1 = &(s->xycls[1][n1]);
	int	i;
	int	m = l0->last;

	if (l1->last < m)
		m = l1->last;

#define	VBLEND(a, b) ((((a) * v0) + ((b) * v1)) >> 8)
	if (up)
		for (i = 0; i < m; i++)
			effectsDrawPoint(s, VBLEND(l0->x[i]    , l1->x[i]    ),
					 VBLEND(l0->y[i]    , l1->y[i]    ),
					 VBLEND(l0->color[i], l1->color[i]), 0);
	else
		for (i = 1; i < m; i++)
			effectsDrawLine(s, VBLEND(l0->x[i - 1], l1->x[i - 1]),
					VBLEND(l0->y[i - 1], l1->y[i - 1]),
					VBLEND(l0->x[i]    , l1->x[i]    ),
					VBLEND(l0->y[i]    , l1->y[i]    ),
					VBLEND(l0->color[i], l1->color[i]), 0);
#undef	VBLEND
}


static void
effectsDrawBuffer(SmearState *s, int np0, int np1, int *up0, int *up1, int v0, int v1)
{
	int	count = np0;
	int	i;

	if (count < np1)
		count = np1;

	for (i = 0; i < count; i++)
		effectsDrawMerge(s, i % np0, i % np1, v0, v1, (up0[i % np0] || up1[i % np1]));
}


void
effectsDrawParticle(SmearState *s, int x, int y, int xe, int ye, int h, int w, int color, int style, int blend)
{
	int	dif;
	int	i, j, x0, y0;

	if (style == 2)
	{
		effectsDrawLine(s, x, y, xe, ye, color, blend);
		return;
	}

	if (h < 16 || w < 16)
		return;

	if (h < 256)
	{
		color = (color * h) >> 8;
		h = 256;
	}

	if (w < 256)
	{
		color = (color * w) >> 8;
		w = 256;
	}

	h >>= 8;
	w >>= 8;

	dif = (h + w) / 2;

	for (y0 = y - h / 2, i = 0; i <= h; i++, y0++)
		for (x0 = x - w / 2, j = 0; j <= w; j++, x0++)
			if ((x0 - x) * (x0 - x) + (y0 - y) * (y0 - y) < dif)
				effectsDrawPoint(s, x0, y0, color, blend);
}


static void
waveformHandle(SmearState *s)
{
	int	now;

	now = smearNow(s);

	if (s->waveformEnvironments[0] == (Environment *)0)
	{
		if ((s->waveformEnvironments[0] = ChooseWaveFormScript(s)) == (Environment *)0)
			return;
		SetupForWaveForm(s->waveformEnvironments[0]);

		s->waveformChanging = 0;
		s->waveformStartTime = now;
		s->waveformEndTime = s->waveformStartTime + 100 * ARG_WaveformHoldTime * (SIMPLE_RAND(100) + 50) / 100;
	}

	if (now >= s->waveformEndTime)
	{
		s->waveformStartTime = now;
		s->waveformChanging = !s->waveformChanging;

		if (s->waveformChanging)
		{
			s->waveformEnvironments[1] = ChooseWaveFormScript(s);
			SetupForWaveForm(s->waveformEnvironments[1]);

			s->waveformEndTime = s->waveformStartTime + 100 * ARG_WaveformFadeTime * (SIMPLE_RAND(100) + 50) / 100;
		}
		else
		{
			s->waveformEnvironments[0] = s->waveformEnvironments[1];
			s->waveformEndTime = s->waveformStartTime + 100 * ARG_WaveformHoldTime * (SIMPLE_RAND(100) + 50) / 100;
		}
	}

	if (s->waveformChanging)
	{
		Environment	*e0 = s->waveformEnvironments[0];
		Environment	*e1 = s->waveformEnvironments[1];
		int v1 = (now - s->waveformStartTime) * 256 / (s->waveformEndTime - s->waveformStartTime);
		int v0 = 256 - v1;

		effectsInitBuffer(s);

		RunForWaveForm(e0, s->_width, s->_myHeight, 1);
		RunForWaveForm(e1, s->_width, s->_myHeight, 2);

		effectsDrawBuffer(s, e0->eRuntime.reWaveform.numPaths,
				  e1->eRuntime.reWaveform.numPaths,
				  e0->eRuntime.reWaveform.usePoints,
				  e1->eRuntime.reWaveform.usePoints,
				  v0, v1);
	}
	else
		RunForWaveForm(s->waveformEnvironments[0], s->_width, s->_myHeight, 0);
}


static void
particleHandle(SmearState *s)
{
	double		fade = 0.0;
	int		i;
	int		now;

	now = smearNow(s);

	// Start new ones
	if (s->numRunning < MAX_PARTICLES_RUNNING &&
	    s->lastTry + PARTICLE_TRY_TIMEOUT < now)
	{
		double	d = (double)SIMPLE_RAND(32767) / 32767.0;
		int	yes = 0;
		double	c = 1.0;

		s->lastTry = now;

		for (i = 0; !yes && i < MAX_PARTICLES_RUNNING; i++)
		{
			if (s->numRunning > i)
				continue;

			c *= VALUE_ParticleChance;

			if (d >= c)
				continue;

			yes = 1;
		}

		if (yes)
		{
			for (i = 0; i < MAX_PARTICLES_RUNNING; i++)
				if (s->particleState[i] == 0)
					break;

			if (i < MAX_PARTICLES_RUNNING &&
			    (s->particleEnvironments[i] = ChooseParticleScript(s)) != (Environment *)0)
			{
				int	j;

				for (j = 0; j < MAX_PARTICLES_RUNNING; j++)
					if (s->particleState[j] > 0 &&
					    s->particleEnvironments[j] ==
					    s->particleEnvironments[i])
						j = 9999;

				if (j < 9999)
				{
					SetupForParticle(s->particleEnvironments[i]);
					s->particleState[i] = 1;
					s->particleStartTime[i] = now;
					s->particleEndTime[i] = now + 100 * ARG_ParticleFadeTime * (SIMPLE_RAND(100) + 50) / 100;

					s->numRunning++;
				}
			}
		}
	}

	for (i = 0; i < MAX_PARTICLES_RUNNING; i++)
	{
		if (s->particleState[i] == 0)
			continue;

		if (now > s->particleEndTime[i])
		{
			s->particleState[i]++;

			if (s->particleState[i] > 3)
			{
				s->particleState[i] = 0;
				s->numRunning--;
				continue;
			}

			s->particleStartTime[i] = now;

			if (s->particleState[i] == 2)
				s->particleEndTime[i] = now + 100 * ARG_ParticleHoldTime * (SIMPLE_RAND(100) + 50) / 100;
			else
				s->particleEndTime[i] = now + 100 * ARG_ParticleFadeTime * (SIMPLE_RAND(100) + 50) / 100;
		}

		switch (s->particleState[i])
		{
		case 1:
			fade = (double)(s->particleEndTime[i] - now) / (double)(s->particleEndTime[i] - s->particleStartTime[i]);
			break;

		case 2:
			fade = 0.0;
			break;

		case 3:
			fade = (double)(now - s->particleStartTime[i]) / (double)(s->particleEndTime[i] - s->particleStartTime[i]);
			break;

		default:
			fade = 1.0;
			break;
		}

		if (fade < 0.0)
			fade = 0.0;

		if (fade > 1.0)
			fade = 1.0;

		RunForParticle(s->particleEnvironments[i], s->_width, s->_myHeight, fade);
	}
}


static void
colormapHandle(SmearState *s)
{
	int	now;
	int	forceRun = 0;

	now = smearNow(s);

	if (s->colormapEnvironments[0] == (Environment *)0)
	{
		if ((s->colormapEnvironments[0] = ChooseColorScript(s)) == (Environment *)0)
			return;
		SetupForColorRun(s->colormapEnvironments[0]);

		s->colormapChanging = 0;
		s->colormapStartTime = now;
		s->colormapEndTime = s->colormapStartTime + 100 * ARG_ColormapHoldTime * (SIMPLE_RAND(100) + 50) / 100;

		forceRun = 1;
	}

	if (now >= s->colormapEndTime)
	{
		s->colormapStartTime = now;
		s->colormapChanging = !s->colormapChanging;
		forceRun = 1;

		if (s->colormapChanging)
		{
			s->colormapEnvironments[1] = ChooseColorScript(s);
			SetupForColorRun(s->colormapEnvironments[1]);

			s->colormapEndTime = s->colormapStartTime + 100 * ARG_ColormapFadeTime * (SIMPLE_RAND(100) + 50) / 100;
		}
		else
		{
			s->colormapEnvironments[0] = s->colormapEnvironments[1];
			s->colormapEndTime = s->colormapStartTime + 100 * ARG_ColormapHoldTime * (SIMPLE_RAND(100) + 50) / 100;
		}
	}

	if (s->colormapChanging)
	{
		unsigned char	*i0p, *i1p, *op;
		int		v0, v1;
		int		i;

		RunForColor(s->colormapEnvironments[0], s->fadeMaps[0], forceRun);
		RunForColor(s->colormapEnvironments[1], s->fadeMaps[1], forceRun);

		op = (unsigned char *)s->colorMap;
		i0p = (unsigned char *)s->fadeMaps[0];
		i1p = (unsigned char *)s->fadeMaps[1];
		v1 = (now - s->colormapStartTime) * 256 / (s->colormapEndTime - s->colormapStartTime);
		if (v1 < 0)
			v1 = 0;
		if (v1 > 256)
			v1 = 256;
		v0 = 256 - v1;
		for (i = 0; i < 256; i++)
		{
			*op = (unsigned char)(((int)(*i0p) * v0 + (int)(*i1p) * v1) >> 8);
			op++; i0p++; i1p++;
			*op = (unsigned char)(((int)(*i0p) * v0 + (int)(*i1p) * v1) >> 8);
			op++; i0p++; i1p++;
			*op = (unsigned char)(((int)(*i0p) * v0 + (int)(*i1p) * v1) >> 8);
			op++; i0p++; i1p++;
			op++; i0p++; i1p++;
		}
	}
	else
		RunForColor(s->colormapEnvironments[0], s->colorMap, forceRun);
}


//////////////////////////////////////////////////////////////////////////////////////
//
// smearRender (was visRender)
//
// Draws one frame into Video, 0x00RRGGBB pixels, row 0 at the top.
//
//////////////////////////////////////////////////////////////////////////////////////
int
smearRender(SmearState *s, uint32_t *Video, int width, int height, int pitch)
{
	s->_Video	= Video;
	s->_width	= width;
	s->_height	= height;
	s->_pitch	= pitch;

	s->_myHeight = (width * ARG_LetterBoxPercent) / 100;
	if (s->_myHeight > height)
		s->_myHeight = height;

	CalculateAudioData(&s->audioData, s->waveform[0], s->waveform[1],
			   s->spectrum[0], s->spectrum[1]);

	colormapHandle(s);

	if (!sbApplyMove(s))
		return 0;
	waveformHandle(s);
	particleHandle(s);

	cmapMapSBToVideo(s);
	return 1;
}
