#include <math.h>

// calculate number of bins to assign, will be at least 1
// nNotAssigned - count of bins not yet assigned
// fDiv - divisor
int AssignCount(int nNotAssigned, double fDiv)
{
	const int nAssign = (int)(nNotAssigned - nNotAssigned / fDiv + 0.5);
	return ((nAssign <= 0) ? 1 : nAssign);
}

// make logarithmic table, or real close to it
// nFftSize - number of elements in frequency data
// nSampleRate - sample rate
// nLastBarCutHz - cut off frequency for last bar
// nBars - number of bars
// pnBarTable - bars array, each element will have a count of the number of FFT elements to use
void LogBarValueTable(const unsigned int nFftSize, const unsigned int nSampleRate, const unsigned int nLastBarCutHz, const unsigned int nBars, unsigned int *pnBarTable)
{
	// pre-assign each bar to draw with at least 1 element from the spec data
	for(unsigned int i = 0; i < nBars; i++)
		pnBarTable[i] = 1;
	
	// assigned 1 to each bar
	int nNotAssigned = nFftSize - nBars;
	// start with last bar
	int nLastAssign = nBars - 1;

	// now assign the rest of the spec data bars to the bars to draw
	// don't ask how I came up with this Div formula cuz it was trial & error till
	// something looked good.
		
	// now assign the rest of the spec data bars to the bars to draw
	// get the <number of spectrum bars> root of the remaining bins to assign
	const double fDiv = pow(nNotAssigned, 1.0f / (double)nBars);
		
	if(nLastBarCutHz > nSampleRate / 10000) {
		// make last bar cut off at no higher than 16000Hz since not much happens there anyway
		unsigned int nHalfSample = nSampleRate / 2;
		if(nHalfSample > nLastBarCutHz) {
			double fHighBinDiv =  (double)nHalfSample / (double)(nHalfSample - nLastBarCutHz);	// number of bins for 16000+ range
			// if last bar will start at a frequency higher than 16000
			if(1 + nNotAssigned - nNotAssigned / fDiv < nFftSize / fHighBinDiv) {
				// make last bar cover 16000+
				pnBarTable[nBars - 1] = (unsigned int)(nFftSize / fHighBinDiv);
				// not assigned is now nBars less 1 minus the number just assigned
				nNotAssigned = nFftSize - (nBars - 1);
				nNotAssigned -= pnBarTable[nBars - 1];
				// last bar is done, start with second last
				nLastAssign = nBars - 2;
			}
		}
	}

	// assign bars from high to low frequencies
	while(nNotAssigned > 0) {
		// get starting bin count to assign
		int nAssign = AssignCount(nNotAssigned, fDiv);
		// iterate bars from high (right) to low (left)
		for(int nW = nLastAssign; nW >= 0 && nNotAssigned > 0; nW--) {
			// assign the bins to a bar
			pnBarTable[nW] += nAssign;
			// update not assigned count
			nNotAssigned -= nAssign;
			//if(nNotAssigned > (int)fDiv)
			//	nAssign = nNotAssigned / fDiv;
			//else
			//	nAssign = 1;
			// get new bin count to assign
			nAssign = AssignCount(nNotAssigned, fDiv);
		}
	}
}
