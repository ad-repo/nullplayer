//////////////////////////////////////////////////////////////////////
//
// Handle all the runtime bits
//
// Modified for NullPlayer (2026-11-12): the audio data, the clock and
// TimedRunForLine's statics belong to the Environment's Smear
// (e->eState); 32-bit maps and colormaps; TimedRunForLine resets its
// resume column before using it; the line-based RunForLine and
// ClearAudioData, which nothing called, are gone; snprintf for sprintf;
// all 16 waveform paths draw; $Step and the PCM index reach their ends;
// a particle's height scales with Y and its width with X.
//
//////////////////////////////////////////////////////////////////////

#include "smear.h"

static double
_CalculatePeak(signed char *data)
{
    int		last = data[0];
    double	total = 0;
	int		x;

    for (x = 1; x < 512; x ++)
    {
      total += abs(last - data[x]);
      last = data[x];
    }

    total /= 256.0;
    if (total > 127.0)
		total = 127.0;

	total /= 127.0;

    return total;
}


static double
_CalculateBass(signed char *data)
{
	// Not done currently
	return 0.0;
}


static double
_CalculateTreble(signed char *data)
{
	// Not done currently
	return 0.0;
}


void
CalculateAudioData(AudioData *ad, signed char *leftData, signed char *rightData, unsigned char *leftSpectrum, unsigned char *rightSpectrum)
{
	ad->dLeftPeak = _CalculatePeak(leftData);
	ad->dRightPeak = _CalculatePeak(rightData);
	ad->dMidPeak = (ad->dLeftPeak + ad->dRightPeak) / 2.0;

	ad->dLeftBass = _CalculateBass(leftData);
	ad->dRightBass = _CalculateBass(rightData);
	ad->dMidBass = (ad->dLeftBass + ad->dRightBass) / 2.0;

	ad->dLeftTreble = _CalculateTreble(leftData);
	ad->dRightTreble = _CalculateTreble(rightData);
	ad->dMidTreble = (ad->dLeftTreble + ad->dRightTreble) / 2.0;

	ad->pLeftData = leftData;
	ad->pRightData = rightData;

	ad->pLeftSpectrum = leftSpectrum;
	ad->pRightSpectrum = rightSpectrum;
}


static	void
SetupRuntimeAudio(Environment *e, RuntimeAudio *rap)
{
	rap->pLeftPeak = GetVariablePointer(e, "LeftPeak");
	rap->pRightPeak = GetVariablePointer(e, "RightPeak");
	rap->pMidPeak = GetVariablePointer(e, "MidPeak");

	rap->pLeftBass = GetVariablePointer(e, "LeftBass");
	rap->pRightBass = GetVariablePointer(e, "RightBass");
	rap->pMidBass = GetVariablePointer(e, "MidBass");

	rap->pLeftTreble = GetVariablePointer(e, "LeftTreble");
	rap->pRightTreble = GetVariablePointer(e, "RightTreble");
	rap->pMidTreble = GetVariablePointer(e, "MidTreble");
}



static inline void
CopyRuntimeAudio(RuntimeAudio *rap, AudioData *ad)
{
	*(rap->pLeftPeak) = ad->dLeftPeak;
	*(rap->pRightPeak) = ad->dRightPeak;
	*(rap->pMidPeak) = ad->dMidPeak;

	*(rap->pLeftBass) = ad->dLeftBass;
	*(rap->pRightBass) = ad->dRightBass;
	*(rap->pMidBass) = ad->dMidBass;

	*(rap->pLeftTreble) = ad->dLeftTreble;
	*(rap->pRightTreble) = ad->dRightTreble;
	*(rap->pMidTreble) = ad->dMidTreble;
}


void
SetupForRun(Environment *e)
{
	SetVariable(e, "Pi", 3.14159265358979323);
	
	ExecuteFunction(e, "init");

	e->eRuntime.reMove.pX = GetVariablePointer(e, "X");
	e->eRuntime.reMove.pY = GetVariablePointer(e, "Y");
	e->eRuntime.reMove.pRadius = GetVariablePointer(e, "Radius");
	e->eRuntime.reMove.pTheta = GetVariablePointer(e, "Theta");

	e->eRuntime.reMove.pSrcX = GetVariablePointer(e, "SrcX");
	e->eRuntime.reMove.pSrcY = GetVariablePointer(e, "SrcY");
	e->eRuntime.reMove.pSrcRadius = GetVariablePointer(e, "SrcRadius");
	e->eRuntime.reMove.pSrcTheta = GetVariablePointer(e, "SrcTheta");

	e->eRuntime.reMove.reqRadius = (GetVariable(e, "RequireRadius") != 0.0);
	e->eRuntime.reMove.reqTheta = (GetVariable(e, "RequireTheta") != 0.0);
	e->eRuntime.reMove.usePolar = (GetVariable(e, "UsePolar") != 0.0);
	e->eRuntime.reMove.useAspect = (GetVariable(e, "UseAspect") != 0.0);

	if (e->eRuntime.reMove.usePolar)
		e->eRuntime.reMove.reqRadius = e->eRuntime.reMove.reqTheta = 1;

	e->eRuntime.reMove.pMoveFunction = FindFunction(e, "move");
}

static inline void
RunForXY(Environment *e, double *x, double *y)
{
	if (!e->eRuntime.reMove.pMoveFunction)
		return;
	
	*(e->eRuntime.reMove.pSrcX) = *(e->eRuntime.reMove.pX) = *x;
	*(e->eRuntime.reMove.pSrcY) = *(e->eRuntime.reMove.pY) = *y;
	
	if (e->eRuntime.reMove.reqRadius)
		*(e->eRuntime.reMove.pSrcRadius) = *(e->eRuntime.reMove.pRadius) = sqrt(*x * *x + *y * *y);
	if (e->eRuntime.reMove.reqTheta)
		*(e->eRuntime.reMove.pSrcTheta) = *(e->eRuntime.reMove.pTheta) = atan2(*y, *x);

	RunCompiledCommand(e, e->eRuntime.reMove.pMoveFunction);

	if (e->eRuntime.reMove.usePolar)
	{
		*x = *(e->eRuntime.reMove.pSrcRadius) * cos(*(e->eRuntime.reMove.pSrcTheta));
		*y = *(e->eRuntime.reMove.pSrcRadius) * sin(*(e->eRuntime.reMove.pSrcTheta));
	}
	else
	{
		*x = *(e->eRuntime.reMove.pSrcX);
		*y = *(e->eRuntime.reMove.pSrcY);
	}
}


int
TimedRunForLine(Environment *e, uint32_t *data, int width, int height, int line, int *ms)
{
	double	yBase;
	double	y;
	double	x;
	int	i;
	double	Xdivisor;
	double	Ydivisor;
	int	tms = 0;
	int	startTime;
	SmearState	*s = e->eState;

	Xdivisor = (double)width / 2.0;
	Ydivisor = (double)height / 2.0;

	if (e->eRuntime.reMove.useAspect)
	{
		if (Xdivisor > Ydivisor)
			Ydivisor = Xdivisor;
		else
			Xdivisor = Ydivisor;
	}

	yBase = ((double)line - (double)height / 2.0) / Ydivisor;

	if (s->lineLastWidth != width ||
	    s->lineLastHeight != height ||
	    s->lineLastLine != line)
		s->lineLastX = 0;

	data += (width * line + s->lineLastX) * 2;

	s->lineLastWidth = width;
	s->lineLastHeight = height;
	s->lineLastLine = line;
	startTime = smearNow(s);

	for (i = s->lineLastX; i < width; i++)
	{
		if ((tms = smearNow(s) - startTime) > *ms)
		{
			s->lineLastX = i;
			*ms -= tms;
			return -1;
		}

		x = ((double)i - (double)width / 2.0) / Xdivisor;
		y = yBase;

		RunForXY(e, &x, &y);

		x = x * Xdivisor + (double)width / 2.0;
		y = y * Ydivisor + (double)height / 2.0;
		
		if (x < 0.0)
			x = 0.0;
		if (x > (double)width - 1.0)
			x = (double)width - 1.0;
		if (y < 0.0)
			y = 0.0;
		if (y > (double)height - 1.0)
			y = (double)height - 1.0;

		*data++ = (int)(x * 65536.0);
		*data++ = (int)(y * 65536.0);
	}
	
	s->lineLastX = 0;
	*ms -= tms;

	return 0;
}

void
SetupForColorRun(Environment *e)
{
	SetVariable(e, "Pi", 3.14159265358979323);

	ExecuteFunction(e, "init");

	e->eRuntime.reColor.pTime = GetVariablePointer(e, "Time");
	e->eRuntime.reColor.pValue = GetVariablePointer(e, "Value");
	
	e->eRuntime.reColor.pH = GetVariablePointer(e, "H");
	e->eRuntime.reColor.pS = GetVariablePointer(e, "S");
	e->eRuntime.reColor.pV = GetVariablePointer(e, "V");

	e->eRuntime.reColor.pR = GetVariablePointer(e, "R");
	e->eRuntime.reColor.pG = GetVariablePointer(e, "G");
	e->eRuntime.reColor.pB = GetVariablePointer(e, "B");

	e->eRuntime.reColor.useHSV = (GetVariable(e, "UseHSV") != 0.0);
	e->eRuntime.reColor.useTime = (GetVariable(e, "UseTIME") != 0.0);
	e->eRuntime.reColor.useRelative = (GetVariable(e, "RelativeTime") != 0.0);
	e->eRuntime.reColor.tmpUsed = 0;

	SetupRuntimeAudio(e, &(e->eAudio));

	e->eRuntime.reColor.pColorFunction = FindFunction(e, "color");
}


void
RunForColor(Environment *e, uint32_t *colormap, int force)
{
	int	i;
	int	r;
	int	g;
	int	b;
	int	iH;
	int	v1, v2, v3;

	if (!e->eRuntime.reColor.pColorFunction)
		return;

	if (!e->eRuntime.reColor.useTime && e->eRuntime.reColor.tmpUsed && !force)
		return;

	CopyRuntimeAudio(&(e->eAudio), &e->eState->audioData);

	if (!e->eRuntime.reColor.tmpUsed)
	{
		e->eRuntime.reColor.tmpZero = e->eRuntime.reColor.useRelative ? smearNow(e->eState) : 0;
		e->eRuntime.reColor.tmpUsed = 1;
	}
	
	*(e->eRuntime.reColor.pTime) = (double)(smearNow(e->eState) - e->eRuntime.reColor.tmpZero) / 1000.0;

	for (i = 0; i < 256; i++, colormap++)
	{
		*(e->eRuntime.reColor.pValue) = (double)i / 256.0;

		RunCompiledCommand(e, e->eRuntime.reColor.pColorFunction);

		if (e->eRuntime.reColor.useHSV)
		{
			*(e->eRuntime.reColor.pH) = (*(e->eRuntime.reColor.pH) - floor(*(e->eRuntime.reColor.pH))) * 6.0;
			iH = (int)*(e->eRuntime.reColor.pH);
			*(e->eRuntime.reColor.pH) -= (double)iH;

			if (*(e->eRuntime.reColor.pS) <= 0.0)
				*(e->eRuntime.reColor.pS) = 0.0;
			if (*(e->eRuntime.reColor.pS) >= 1.0)
				*(e->eRuntime.reColor.pS) = 1.0;
			
			if (*(e->eRuntime.reColor.pV) <= 0.0)
				*(e->eRuntime.reColor.pV) = 0.0;
			if (*(e->eRuntime.reColor.pV) >= 1.0)
				*(e->eRuntime.reColor.pV) = 1.0;

			if (!(iH & 1))
				*(e->eRuntime.reColor.pH) = 1.0 - *(e->eRuntime.reColor.pH);

			*(e->eRuntime.reColor.pV) *= 256.0;

			v1 = (int)(*(e->eRuntime.reColor.pV));
			v2 = (int)(*(e->eRuntime.reColor.pV) * (1.0 - *(e->eRuntime.reColor.pS)));
			v3 = (int)(*(e->eRuntime.reColor.pV) * (1.0 - (*(e->eRuntime.reColor.pS) * *(e->eRuntime.reColor.pH))));

			switch (iH)
			{
			case 1: r = v3; g = v1; b = v2; break;
			case 2: r = v2; g = v1; b = v3; break;
			case 3: r = v2; g = v3; b = v1; break;// this is wrong
			case 4: r = v3; g = v2; b = v1; break;// this is wrong
			case 5: r = v1; g = v2; b = v3; break;
			case 0: default:
					r = v1; g = v3; b = v2; break;
			}
		}
		else
		{
			r = (int)((*(e->eRuntime.reColor.pR)) * 256.0);
			g = (int)((*(e->eRuntime.reColor.pG)) * 256.0);
			b = (int)((*(e->eRuntime.reColor.pB)) * 256.0);
		}

		if (r < 0) r = 0;
		if (r > 255) r = 255;
		if (g < 0) g = 0;
		if (g > 255) g = 255;
		if (b < 0) b = 0;
		if (b > 255) b = 255;

		*colormap = (r << 16) | (g << 8) | b;
	}
}





void
SetupForWaveForm(Environment *e)
{
	char	_tmp[16];
	int		i;

	SetVariable(e, "Pi", 3.14159265358979323);
	
	ExecuteFunction(e, "init");

	e->eRuntime.reWaveform.numPaths = (int)GetVariable(e, "Paths");
	if (e->eRuntime.reWaveform.numPaths <= 0)
		e->eRuntime.reWaveform.numPaths = 1;

	if (e->eRuntime.reWaveform.numPaths > MAX_WAVEFORM_PATHS)
		e->eRuntime.reWaveform.numPaths = MAX_WAVEFORM_PATHS;

	e->eRuntime.reWaveform.numSteps = (int)GetVariable(e, "Steps");
	if (e->eRuntime.reWaveform.numSteps == 0)
		e->eRuntime.reWaveform.numSteps = 256;
	if (e->eRuntime.reWaveform.numSteps < 2)
		e->eRuntime.reWaveform.numSteps = 2;
	if (e->eRuntime.reWaveform.numSteps > 512)
		e->eRuntime.reWaveform.numSteps = 512;


	for (i = 0; i < e->eRuntime.reWaveform.numPaths; i++)
	{
		snprintf(_tmp, sizeof(_tmp), "Loop%d", i);
		e->eRuntime.reWaveform.useLoop[i] = (GetVariable(e, _tmp) != 0.0);

		snprintf(_tmp, sizeof(_tmp), "NoLines%d", i);
		e->eRuntime.reWaveform.usePoints[i] = (GetVariable(e, _tmp) != 0.0);

		snprintf(_tmp, sizeof(_tmp), "X%d", i);
		e->eRuntime.reWaveform.pX[i] = GetVariablePointer(e, _tmp);

		snprintf(_tmp, sizeof(_tmp), "Y%d", i);
		e->eRuntime.reWaveform.pY[i] = GetVariablePointer(e, _tmp);

		snprintf(_tmp, sizeof(_tmp), "Fade%d", i);
		e->eRuntime.reWaveform.pFade[i] = GetVariablePointer(e, _tmp);
	}

	e->eRuntime.reWaveform.pTime = GetVariablePointer(e, "Time");
	e->eRuntime.reWaveform.pStep = GetVariablePointer(e, "Step");
	e->eRuntime.reWaveform.pLeft = GetVariablePointer(e, "Left");
	e->eRuntime.reWaveform.pRight = GetVariablePointer(e, "Right");
	e->eRuntime.reWaveform.pMid = GetVariablePointer(e, "Mid");

	SetupRuntimeAudio(e, &(e->eAudio));

	e->eRuntime.reWaveform.useAspect = (GetVariable(e, "UseAspect") != 0.0);
	e->eRuntime.reWaveform.useRelative = (GetVariable(e, "RelativeTime") != 0.0);
	e->eRuntime.reWaveform.tmpUsed = 0;
	if (GetVariable(e, "UseBlendType") >= 1.5)
		e->eRuntime.reWaveform.useBlendType = 2;
	else
	if (GetVariable(e, "UseBlendType") >= 0.5)
		e->eRuntime.reWaveform.useBlendType = 1;
	else
		e->eRuntime.reWaveform.useBlendType = 0;

	e->eRuntime.reWaveform.pWaveformFunction = FindFunction(e, "waveform");
	e->eRuntime.reWaveform.pNewLineFunction = FindFunction(e, "newline");
}



void
RunForWaveForm(Environment *e, int width, int height, int whichDraw)
{
	int	y;
	int	x;
	int	i;
	int	path;
	int	pos;
	int	lastpos = 0;
	int colo;
	double	Xdivisor;
	double	Ydivisor;

	if (!e->eRuntime.reWaveform.pWaveformFunction)
		return;

	CopyRuntimeAudio(&(e->eAudio), &e->eState->audioData);

	if (!e->eRuntime.reWaveform.tmpUsed)
	{
		e->eRuntime.reWaveform.tmpZero = e->eRuntime.reWaveform.useRelative ? smearNow(e->eState) : 0;
		e->eRuntime.reWaveform.tmpUsed = 1;
	}

	*(e->eRuntime.reWaveform.pTime) = (double)(smearNow(e->eState) - e->eRuntime.reWaveform.tmpZero) / 1000.0;

	if (e->eRuntime.reWaveform.pNewLineFunction)
		RunCompiledCommand(e, e->eRuntime.reWaveform.pNewLineFunction);

	Xdivisor = (double)width / 2.0;
	Ydivisor = (double)height / 2.0;

	if (e->eRuntime.reWaveform.useAspect)
	{
		if (Xdivisor > Ydivisor)
			Ydivisor = Xdivisor;
		else
			Xdivisor = Ydivisor;
	}

	for (i = 0; i < e->eRuntime.reWaveform.numSteps; i++)
	{
		*(e->eRuntime.reWaveform.pStep) = (double)i / (double)(e->eRuntime.reWaveform.numSteps - 1);
		pos = (i * (WAVE_DATA_SIZE - 1)) / (e->eRuntime.reWaveform.numSteps - 1);
		
		*(e->eRuntime.reWaveform.pLeft) = (double)(e->eState->audioData.pLeftData[pos]) / 128.0;
		*(e->eRuntime.reWaveform.pRight) = (double)(e->eState->audioData.pRightData[pos]) / 128.0;
		*(e->eRuntime.reWaveform.pMid) = (*(e->eRuntime.reWaveform.pLeft) + *(e->eRuntime.reWaveform.pRight)) / 2.0;

		RunCompiledCommand(e, e->eRuntime.reWaveform.pWaveformFunction);

		for (path = 0; path < e->eRuntime.reWaveform.numPaths; path++)
		{
			x = (int)(*e->eRuntime.reWaveform.pX[path] * Xdivisor + (double)width / 2.0);
			y = (int)(*e->eRuntime.reWaveform.pY[path] * Ydivisor + (double)height / 2.0);


			if (i == 0)
			{
				e->eRuntime.reWaveform.tmpFirstX[path] = x;
				e->eRuntime.reWaveform.tmpFirstY[path] = y;
			}
			else
			{
				colo = (int)((1.0 - *(e->eRuntime.reWaveform.pFade[path])) * 255.0);
				if (colo > 255)
					colo = 255;
				if (colo < 0)
					colo = 0;

				if (whichDraw)
					effectsBufferLine(e->eState, e->eRuntime.reWaveform.tmpPreviousX[path], e->eRuntime.reWaveform.tmpPreviousY[path], colo, whichDraw, path, lastpos);
				else
					if (e->eRuntime.reWaveform.usePoints[path])
						effectsDrawPoint(e->eState, x, y, colo, e->eRuntime.reWaveform.useBlendType);
					else
						effectsDrawLine(e->eState, x, y, e->eRuntime.reWaveform.tmpPreviousX[path], e->eRuntime.reWaveform.tmpPreviousY[path], colo, e->eRuntime.reWaveform.useBlendType);
			}

			e->eRuntime.reWaveform.tmpPreviousX[path] = x;
			e->eRuntime.reWaveform.tmpPreviousY[path] = y;
		}
		lastpos = pos;
	}

	for (path = 0; path < e->eRuntime.reWaveform.numPaths; path++)
		if (whichDraw)
		{
			colo = (int)((1.0 - *(e->eRuntime.reWaveform.pFade[path])) * 255.0);
			if (colo > 255)
				colo = 255;
			if (colo < 0)
				colo = 0;

			effectsBufferLine(e->eState, e->eRuntime.reWaveform.tmpPreviousX[path], e->eRuntime.reWaveform.tmpPreviousY[path], colo, whichDraw, path, 511);
		}
		else
		if (e->eRuntime.reWaveform.useLoop[path] && !e->eRuntime.reWaveform.usePoints[path])
		{
			colo = (int)((1.0 - *(e->eRuntime.reWaveform.pFade[path])) * 255.0);
			if (colo > 255)
				colo = 255;
			if (colo < 0)
				colo = 0;

			effectsDrawLine(e->eState, e->eRuntime.reWaveform.tmpFirstX[path], e->eRuntime.reWaveform.tmpFirstY[path], e->eRuntime.reWaveform.tmpPreviousX[path], e->eRuntime.reWaveform.tmpPreviousY[path], colo, e->eRuntime.reWaveform.useBlendType);
		}

	return;
}


void
SetupForParticle(Environment *e)
{
	SetVariable(e, "Pi", 3.14159265358979323);
	
	ExecuteFunction(e, "init");

	e->eRuntime.reParticle.numParticles = (int)GetVariable(e, "numParticles");
	if (e->eRuntime.reParticle.numParticles <= 0)
		e->eRuntime.reParticle.numParticles = 1;

	if (e->eRuntime.reParticle.numParticles >= MAX_PARTICLE_POINTS)
		e->eRuntime.reParticle.numParticles = MAX_PARTICLE_POINTS - 1;

	e->eRuntime.reParticle.pParticle = GetVariablePointer(e, "Particle");
	e->eRuntime.reParticle.pX = GetVariablePointer(e, "X");
	e->eRuntime.reParticle.pY = GetVariablePointer(e, "Y");
	e->eRuntime.reParticle.pXend = GetVariablePointer(e, "Xend");
	e->eRuntime.reParticle.pYend = GetVariablePointer(e, "Yend");
	e->eRuntime.reParticle.pFade = GetVariablePointer(e, "Fade");
	e->eRuntime.reParticle.pSize = GetVariablePointer(e, "Size");
	e->eRuntime.reParticle.pStyle = GetVariablePointer(e, "Style");
	e->eRuntime.reParticle.pTime = GetVariablePointer(e, "Time");

	SetupRuntimeAudio(e, &(e->eAudio));

	e->eRuntime.reParticle.useAspect = (GetVariable(e, "UseAspect") != 0.0);
	e->eRuntime.reParticle.useRelative = (GetVariable(e, "RelativeTime") != 0.0);
	e->eRuntime.reParticle.tmpUsed = 0;

	if (GetVariable(e, "UseBlendType") >= 1.5)
		e->eRuntime.reParticle.useBlendType = 2;
	else
	if (GetVariable(e, "UseBlendType") >= 0.5)
		e->eRuntime.reParticle.useBlendType = 1;
	else
		e->eRuntime.reParticle.useBlendType = 0;

	e->eRuntime.reParticle.pNewFrameFunction = FindFunction(e, "newFrame");
	e->eRuntime.reParticle.pParticleFunction = FindFunction(e, "particle");
}


void
RunForParticle(Environment *e, int width, int height, double fade)
{
	int	y;
	int	x;
	int	xend;
	int	yend;
	int	h;
	int	w;
	int	i;
	int	colo;
	double	tc;
	double	Xdivisor;
	double	Ydivisor;

	if (!e->eRuntime.reParticle.pParticleFunction)
		return;

	CopyRuntimeAudio(&(e->eAudio), &e->eState->audioData);

	if (!e->eRuntime.reParticle.tmpUsed)
	{
		e->eRuntime.reParticle.tmpZero = e->eRuntime.reParticle.useRelative ? smearNow(e->eState) : 0;
		e->eRuntime.reParticle.tmpUsed = 1;
	}

	*(e->eRuntime.reParticle.pTime) = (double)(smearNow(e->eState) - e->eRuntime.reParticle.tmpZero) / 1000.0;

	if (e->eRuntime.reParticle.pNewFrameFunction)
	{
		RunCompiledCommand(e, e->eRuntime.reParticle.pNewFrameFunction);
	}

	Xdivisor = (double)width / 2.0;
	Ydivisor = (double)height / 2.0;

	if (e->eRuntime.reParticle.useAspect)
	{
		if (Xdivisor > Ydivisor)
			Ydivisor = Xdivisor;
		else
			Xdivisor = Ydivisor;
	}

	for (i = 0; i < e->eRuntime.reParticle.numParticles; i++)
	{
		*(e->eRuntime.reParticle.pParticle) = (double)i;
		
		RunCompiledCommand(e, e->eRuntime.reParticle.pParticleFunction);

		tc = (int)((1.0 - *(e->eRuntime.reParticle.pFade)) * 255.0);
		if (tc < 0.0)
			tc = 0.0;
		if (tc > 255.0)
			tc = 255.0;

		colo = (int)(tc * (1.0 - fade));
				
		if (colo > 255)
			colo = 255;
		if (colo < 0)
			colo = 0;

		x = (int)(*(e->eRuntime.reParticle.pX) * Xdivisor + (double)width / 2.0);
		y = (int)(*(e->eRuntime.reParticle.pY) * Ydivisor + (double)height / 2.0);

		xend = (int)(*(e->eRuntime.reParticle.pXend) * Xdivisor + (double)width / 2.0);
		yend = (int)(*(e->eRuntime.reParticle.pYend) * Ydivisor + (double)height / 2.0);

		h = (int)(*(e->eRuntime.reParticle.pSize) * Ydivisor * 256.0);
		w = (int)(*(e->eRuntime.reParticle.pSize) * Xdivisor * 256.0);

		effectsDrawParticle(e->eState, x, y, xend, yend, h, w, colo, (int)(*(e->eRuntime.reParticle.pStyle)), e->eRuntime.reParticle.useBlendType);
	}

	return;
}

