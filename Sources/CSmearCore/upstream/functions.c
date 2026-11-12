// Modified for NullPlayer (2026-11-12): the audio data and the 3D
// matrix belong to the Environment's Smear (e->eState); EXECUTE, LOOP
// and WHILE return 0 when they run nothing; RND draws from the Smear's
// own generator.  See LICENSE.TXT.

#include "smear.h"

flFuncDeclare(fnPlus)
{
	int	i;
	double	d = flArgument(0);

	for (i = 1; i < ccp->ccArgumentCount; i++)
		d += flArgument(i);

	return d;
}


flFuncDeclare(fnMinus)
{
	return flArgument(0) - flArgument(1);
}


flFuncDeclare(fnTimes)
{
	int	i;
	double	d = flArgument(0);

	for (i = 1; i < ccp->ccArgumentCount; i++)
		d *= flArgument(i);

	return d;
}


flFuncDeclare(fnDivide)
{
	double	d = flArgument(1);

	if (d == 0.0)
	{
		RunTimeError("Sciprt: %s\n\nDivide by Zero (/)", e->eFile);
		return 0.0;
	}

	return flArgument(0) / flArgument(1);
}


flFuncDeclare(fnLAnd)
{
	int	i;
	double	n = (flArgument(0) != 0.0);

	for (i = 1; n && i < ccp->ccArgumentCount; i++)
		n = n && (flArgument(i) != 0.0);

	return n;
}


flFuncDeclare(fnLOr)
{
	int	i;
	double	n = (flArgument(0) != 0.0);

	for (i = 1; !n && i < ccp->ccArgumentCount; i++)
		n = n || (flArgument(i) != 0.0);

	return n;
}


flFuncDeclare(fnNot)
{
	return (double)(!(flArgument(0) != 0.0));
}


flFuncDeclare(fnEqual)
{
	return (double)(flArgument(0) == flArgument(1));
}


flFuncDeclare(fnNotEqual)
{
	return (double)(flArgument(0) != flArgument(1));
}


flFuncDeclare(fnLessThan)
{
	return (double)(flArgument(0) < flArgument(1));
}


flFuncDeclare(fnLessThanEqual)
{
	return (double)(flArgument(0) <= flArgument(1));
}


flFuncDeclare(fnGreaterThan)
{
	return (double)(flArgument(0) > flArgument(1));
}


flFuncDeclare(fnGreaterThanEqual)
{
	return (double)(flArgument(0) >= flArgument(1));
}


flFuncDeclare(fnSin)
{
	return sin(flArgument(0));
}


flFuncDeclare(fnCos)
{
	return cos(flArgument(0));
}


flFuncDeclare(fnTan)
{
	return tan(flArgument(0));
}


flFuncDeclare(fnEcho)
{
	double	d = flArgument(0);

	fprintf(stderr, "%lf\n", d);

	return d;
}


flFuncDeclare(fnIf)
{
	return flArgument(0) ? flArgument(1) : flArgument(2);
}


flFuncDeclare(fnRnd)
{
	double d1 = flArgument(0);
	double d2 = flArgument(1);

	if (d1 == 0.0 && d2 == 0.0)
		d2 = 1.0;
	else
	if (d1 > d2)
	{
		double	d = d1;
		d1 = d2;
		d2 = d;
	}

//	return drand48() * d;
	return (double)(smearRand(e->eState) & 32767) / 32768.0 * (d2 - d1) + d1;
}


flFuncDeclare(fnWrap)
{
	double	d = flArgument(0);
	double	l;
	double	h;

	switch (ccp->ccArgumentCount)
	{
	case 1:
		return d - floor(d);
	
	case 2:
		l = 0.0;
		h = flArgument(1);
		break;

	case 3:
		l = flArgument(1);
		h = flArgument(2);
		break;
	}

	if (l > h)
	{
		double	t;

		t = h;
		h = l;
		l = t;
	}

	if (l == h)
	{
		if (l > 0.0)
			l = 0.0;
		else
		if (l < 0.0)
			h = 0.0;
		else
			h = 1.0;
	}

	while (d > h)
		d -= (h - l);

	while (d < l)
		d += (h - l);

	return d;
}


flFuncDeclare(fnAbs)
{
	return fabs(flArgument(0));
}


flFuncDeclare(fnTrunc)
{
//	return trunc(flArgument(0));
	return floor(flArgument(0));
}

flFuncDeclare(fnSqrt)
{
	return sqrt(flArgument(0));
}

flFuncDeclare(fnAsin)
{
	return asin(flArgument(0));
}

flFuncDeclare(fnAcos)
{
	return acos(flArgument(0));
}

flFuncDeclare(fnAtan)
{
	return atan(flArgument(0));
}

flFuncDeclare(fnSign)
{
	return flArgument(0) >= 0.0 ? 1.0 : -1.0;
}

flFuncDeclare(fnLog)
{
	return log(flArgument(0));
}

flFuncDeclare(fnExp)
{
	return exp(flArgument(0));
}

flFuncDeclare(fnPow)
{
	return pow(flArgument(0), flArgument(1));
}

flFuncDeclare(fnMod)
{
	long	l = (long)flArgument(1);

	if (l == 0)
	{
		RunTimeError("Sciprt: %s\n\nDivide by Zero (Mod)", e->eFile);
		return 0.0;
	}

	return (double)((long)flArgument(0) % l);
}

flFuncDeclare(fnClamp)
{
	double	d = flArgument(0);
	double	l;
	double	h;

	switch (ccp->ccArgumentCount)
	{
	case 1:
		return d - floor(d);
	
	case 2:
		l = 0.0;
		h = flArgument(1);
		break;

	case 3:
		l = flArgument(1);
		h = flArgument(2);
		break;
	}

	if (d < l)
		return l;
	if (d > h)
		return h;

	return d;
}

flFuncDeclare(fnPos)
{
	double d = flArgument(0);

	return (d >= 0.0) ? d : 0.0;
}


flFuncDeclare(fnSet)
{
	double	d;
	double	*lv;

	d = flArgument(1);
	if ((lv = flLValue(0)) == (double *)0)
		return d;

	*lv = d;

	return d;
}

flFuncDeclare(fnExecute)
{
	int	i;
	double d = 0.0;

	for (i = 0; i < ccp->ccArgumentCount; i++)
		d = flArgument(i);

	return d;
}


flFuncDeclare(fnLoop)
{
	double	d = 0.0;
	double	start;
	double	end;
	double	*lv;

	if ((lv = flLValue(0)) == (double *)0)
		return 0.0;

	start = flArgument(1);
	end = flArgument(2);
	for (; start <= end; start += 1.0)
	{
		*lv = start;
		d = flArgument(3);
	}

	return d;
}


flFuncDeclare(fnWhile)
{
	double d = 0.0;

	while (flArgument(0) != 0.0)
		d = flArgument(1);

	return d;
}

flFuncDeclare(fnPolar)
{
	double	x;
	double	y;
	double	*lvRadius;
	double	*lvTheta;

	if ((lvRadius = flLValue(0)) == (double *)0 ||
	    (lvTheta = flLValue(1)) == (double *)0)
		return 0.0;

	x = flArgument(2);
	y = flArgument(3);

	*lvRadius = sqrt(x * x + y * y);
	*lvTheta = atan2(y, x);

	return *lvRadius;
}



flFuncDeclare(fnCart)
{
	double	radius;
	double	theta;
	double	*lvX;
	double	*lvY;

	if ((lvX = flLValue(0)) == (double *)0 ||
	    (lvY = flLValue(1)) == (double *)0)
		return 0.0;

	radius = flArgument(2);
	theta = flArgument(3);

	*lvX = radius * cos(theta);
	*lvY = radius * sin(theta);

	return *lvX;
}

flFuncDeclare(fnLSpect)
{
	int	n = (int)(flArgument(0) * 255.0);

	if (n < 0)
		n = 0;
	if (n > 255)
		n = 255;

	return (double)((double)e->eState->audioData.pLeftSpectrum[n] / 256.0);
}

flFuncDeclare(fnRSpect)
{
	int	n = (int)(flArgument(0) * 255.0);

	if (n < 0)
		n = 0;
	if (n > 255)
		n = 255;

	return (double)((double)e->eState->audioData.pRightSpectrum[n] / 256.0);
}

flFuncDeclare(fnLWave)
{
	int	n = (int)(flArgument(0) * 511.0);

	if (n < 0)
		n = 0;
	if (n > 511)
		n = 511;

	return (double)((double)e->eState->audioData.pLeftData[n] / 256.0);
}

flFuncDeclare(fnRWave)
{
	int	n = (int)(flArgument(0) * 511.0);

	if (n < 0)
		n = 0;
	if (n > 511)
		n = 511;

	return (double)((double)e->eState->audioData.pRightData[n] / 256.0);
}


flFuncDeclare(fnBitAnd)
{
	int	n = (int)(flArgument(0));
	int	i;

	for (i = 1; i < ccp->ccArgumentCount; i++)
		n &= (int)flArgument(i);

	return n;
}


flFuncDeclare(fnBitOr)
{
	int	n = (int)(flArgument(0));
	int	i;

	for (i = 1; i < ccp->ccArgumentCount; i++)
		n |= (int)flArgument(i);

	return n;
}


flFuncDeclare(fnBitLeft)
{
	int	n1 = (int)(flArgument(0));
	int	n2 = (int)(flArgument(1));

	return (double)(n1 << n2);
}


flFuncDeclare(fnBitRight)
{
	int	n1 = (int)(flArgument(0));
	int	n2 = (int)(flArgument(1));

	return (double)(n1 >> n2);
}


flFuncDeclare(fnNeg)
{
	return -(flArgument(0));
}


flFuncDeclare(fnCase)
{
	double	testVal = flArgument(0);
	int	i = 1;

	while (i < ccp->ccArgumentCount)
	{
		if (ccp->ccArgumentCount == i + 1)
			return flArgument(i);

		if (testVal == flArgument(i))
			return flArgument(i + 1);

		i += 2;
	}

	return 0;
}


flFuncDeclare(fnSetPlus)
{
	double	d;
	double	*lv;

	d = flArgument(1);
	if ((lv = flLValue(0)) == (double *)0)
		return d;

	return *lv += d;
}


flFuncDeclare(fnSetMinus)
{
	double	d;
	double	*lv;

	d = flArgument(1);
	if ((lv = flLValue(0)) == (double *)0)
		return d;

	return *lv -= d;
}


flFuncDeclare(fnSetDiv)
{
	double	d;
	double	*lv;

	d = flArgument(1);
	if ((lv = flLValue(0)) == (double *)0)
		return d;

	if (d == 0.0)
	{
		RunTimeError("Sciprt: %s\n\nDivide by Zero (/=)", e->eFile);
		return 0.0;
	}

	return *lv /= d;
}


flFuncDeclare(fnSetMult)
{
	double	d;
	double	*lv;

	d = flArgument(1);
	if ((lv = flLValue(0)) == (double *)0)
		return d;

	return *lv *= d;
}


flFuncDeclare(fnSetMod)
{
	long	l;
	double	*lv;

	l = (long)flArgument(1);

	if (l == 0)
	{
		RunTimeError("Sciprt: %s\n\nDivide by Zero (%=)", e->eFile);
		return 0.0;
	}

	if ((lv = flLValue(0)) == (double *)0)
		return 0.0;

	return *lv +=
		(double)((int)(*lv) % l);
}


#define	_3D(r, c)	(e->eState->matrix3d[r][c])

flFuncDeclare(fn3DSetup)
{
	double	Xrot = flArgument(0);
	double	Yrot = flArgument(1);
	double	Zrot = flArgument(2);
	double	t1, t2, t3, t4, t5, t6;
	double	m1, m2, m3;

	t1 = cos(Xrot);
	t2 = cos(Yrot);
	t3 = cos(Zrot);
	t4 = sin(Xrot);
	t5 = sin(Yrot);
	t6 = sin(Zrot);

	m1 = t2 * t3;
	m2 = t4 * t5;
	m3 = t2 * t6;

	_3D(0, 0) = m1 - m2 * t6;
	_3D(0, 1) = - t1 * t6;
	_3D(0, 2) = t3 * t5 + m3 * t4;
	_3D(1, 0) = m3 + m2 * t3;
	_3D(1, 1) = t1 * t3;
	_3D(1, 2) = t5 * t6 - m1 * t4;
	_3D(2, 0) = - t1 * t5;
	_3D(2, 1) = t4;
	_3D(2, 2) = t1 * t2;

	return 0.0;
}

flFuncDeclare(fn3DRotate)
{
	double	xv, yv, zv;
	double	*lvX, *lvY, *lvZ;

	if ((lvX = flLValue(0)) == (double *)0 ||
	    (lvY = flLValue(1)) == (double *)0 ||
	    (lvZ = flLValue(2)) == (double *)0)
		return 0.0;

	xv = flArgument(3);
	yv = flArgument(4);
	zv = flArgument(5);

	*lvX = xv * _3D(0, 0) + yv * _3D(0, 1) + zv * _3D(0, 2);
	*lvY = xv * _3D(1, 0) + yv * _3D(1, 1) + zv * _3D(1, 2);
	*lvZ = xv * _3D(2, 0) + yv * _3D(2, 1) + zv * _3D(2, 2);

	return 0.0;
}
