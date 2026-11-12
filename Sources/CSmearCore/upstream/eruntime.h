//////////////////////////////////////////////////////////////////////
//
// Runtime environment
//
// Modified for NullPlayer (2026-11-12): the waveform is signed and the
// spectrum unsigned whatever the compiler's plain char is (MSVC's was
// signed, which turned spectrum values over 127 negative).
//
//////////////////////////////////////////////////////////////////////

#ifndef	__ERUNTIME_H__
#define	__ERUNTIME_H__

#define	MAX_WAVEFORM_PATHS	16
#define	MAX_PARTICLE_POINTS	256

typedef	struct	__audioData
{
	double		dLeftPeak;
	double		dRightPeak;
	double		dMidPeak;

	double		dLeftBass;
	double		dRightBass;
	double		dMidBass;

	double		dLeftTreble;
	double		dRightTreble;
	double		dMidTreble;

	signed char	*pLeftData;
	signed char	*pRightData;

	unsigned char	*pLeftSpectrum;
	unsigned char	*pRightSpectrum;
}	AudioData;


typedef	struct	__runtimeAudio
{
	double		*pLeftPeak;
	double		*pRightPeak;
	double		*pMidPeak;

	double		*pLeftBass;
	double		*pRightBass;
	double		*pMidBass;

	double		*pLeftTreble;
	double		*pRightTreble;
	double		*pMidTreble;
}	RuntimeAudio;


typedef	struct	__reMove
{
	double		*pX;
	double		*pY;
	double		*pRadius;
	double		*pTheta;

	double		*pSrcX;
	double		*pSrcY;
	double		*pSrcRadius;
	double		*pSrcTheta;

	int		reqRadius;
	int		reqTheta;

	int		usePolar;
	int		useAspect;

	CompiledCommand	*pMoveFunction;
}	RuntimeEnvironmentMove;



typedef	struct	__reColor
{
	double		*pTime;
	double		*pValue;
	
	double		*pH, *pS, *pV;
	double		*pR, *pG, *pB;

	int		useHSV;
	int		useTime;
	int		useRelative;

	int		tmpZero;
	int		tmpUsed;

	CompiledCommand	*pColorFunction;
}	RuntimeEnvironmentColor;


typedef	struct	__reWaveform
{
	double		*pX[MAX_WAVEFORM_PATHS];
	double		*pY[MAX_WAVEFORM_PATHS];
	double		*pFade[MAX_WAVEFORM_PATHS];
	double		*pStep;
	double		*pTime;

	double		*pLeft;
	double		*pRight;
	double		*pMid;

	int		useLoop[MAX_WAVEFORM_PATHS];
	int		usePoints[MAX_WAVEFORM_PATHS];
	int		useAspect;
	int		useRelative;
	int		useBlendType;
	int		numPaths;
	int		numSteps;

	int		tmpPreviousX[MAX_WAVEFORM_PATHS];
	int		tmpPreviousY[MAX_WAVEFORM_PATHS];
	int		tmpFirstX[MAX_WAVEFORM_PATHS];
	int		tmpFirstY[MAX_WAVEFORM_PATHS];
	
	int		tmpZero;
	int		tmpUsed;

	CompiledCommand	*pNewLineFunction;
	CompiledCommand	*pWaveformFunction;
}	RuntimeEnvironmentWaveform;


typedef	struct	__reParticle
{
	double		*pX;
	double		*pY;
	double		*pXend;
	double		*pYend;
	double		*pFade;
	double		*pSize;
	double		*pStyle;
	double		*pTime;
	double		*pParticle;

	int		useAspect;
	int		useRelative;
	int		numParticles;
	int		useBlendType;

	int		tmpZero;
	int		tmpUsed;

	CompiledCommand	*pNewFrameFunction;
	CompiledCommand	*pParticleFunction;
}	RuntimeEnvironmentParticle;


typedef	union	__runtime_environment
{
	RuntimeEnvironmentMove		reMove;
	RuntimeEnvironmentColor		reColor;
	RuntimeEnvironmentWaveform	reWaveform;
	RuntimeEnvironmentParticle	reParticle;
}	RuntimeEnvironment;

#endif
