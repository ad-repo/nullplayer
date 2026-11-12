// Modified for NullPlayer (2026-11-12): a grown array zeroes all of its
// new elements, not sizeof(double) bytes of them; an access starts
// zeroed, so a half-compiled one can be freed; an out-of-range access
// (or one the array could not grow to) uses the array's own error slot,
// not a static shared by every Smear.  See LICENSE.TXT.

#include "smear.h"


static	void
arrayCheckAllocation(ArrayStructure *asp, int offset)
{
	int	allocCount;
	double	*dp;

	if (offset < 0 ||
	    offset >= MAX_ARRAY_OFFSET ||
	    offset < asp->asAllocated)
		return;

	allocCount = asp->asAllocated;

	while (allocCount <= offset)
		allocCount += ARRAY_ALLOCATION_CHUNK;

	dp = (double *)malloc(allocCount * sizeof(double));
	if (dp == (double *)0)
		return;

	if (asp->asAllocated)
	{
		memcpy(dp, asp->asData, sizeof(double) * asp->asAllocated);
		free(asp->asData);
	}

	memset(((char *)dp) + asp->asAllocated * sizeof(double), '\0',
	       sizeof(double) * (allocCount - asp->asAllocated));

	asp->asAllocated = allocCount;
	asp->asData = dp;
}


void
arrayFreeAllocation(ArrayStructure *asp)
{
	if (asp->asAllocated && asp->asData)
	{
		asp->asAllocated = 0;
		free(asp->asData);
		asp->asData = (double *)0;
	}
}


ArrayStructure	*
arrayAllocateNew(void)
{
	ArrayStructure	*asp;

	if ((asp = (ArrayStructure *)malloc(sizeof(ArrayStructure)))
	    == (ArrayStructure *)0)
		return asp;

	asp->asAllocated = 0;

	return asp;
}


ArrayAccess	*
arrayAllocateNewAccess(void)
{
	return (ArrayAccess *)calloc(1, sizeof(ArrayAccess));
}


double	*
arrayGetEvaluationPointer(ArrayStructure *asp, double offset)
{
	int	ioff;

	ioff = (int)floor(offset);

	arrayCheckAllocation(asp, ioff);

	if (ioff < 0 || ioff >= asp->asAllocated)
	{
		asp->asErrorReturn = 0.0;
		return &asp->asErrorReturn;
	}

	return asp->asData + ioff;
}


double
arrayEvaluate(ArrayStructure *asp, double offset)
{
	return *(arrayGetEvaluationPointer(asp, offset));
}
