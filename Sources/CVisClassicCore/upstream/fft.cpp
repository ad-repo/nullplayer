/*
  LICENSE
  -------
Copyright 2005-2013 Nullsoft, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, 
are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer. 

  * Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution. 

  * Neither the name of Nullsoft nor the names of its contributors may be used to 
    endorse or promote products derived from this software without specific prior written permission. 
 
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR 
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND 
FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR 
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT 
OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#include <math.h>
#include <memory.h>
#include "fft.h"

#define PI 3.141592653589793238462643383279502884197169399f

#define SafeDeleteArray(x) { if (x) { delete [] x; x = 0; } }

/*****************************************************************************/

int m_samples_in;
int NFREQ;

void InitEnvelopeTable(float power);
void InitEqualizeTable(const bool mode);
void InitBitRevTable();
void InitCosSinTable();

FFT::FFT() : m_samples_in(0), NFREQ(0), bitrevtable(0), envelope(0),
                    equalize(0), temp1(0), temp2(0), cossintable(0)
{
}

/*****************************************************************************/

FFT::~FFT()
{
	CleanUp();
}

/*****************************************************************************/

void FFT::Init(const int samples_in, const int samples_out, const int bEqualize, const float envelope_power, const bool mode)
{
	// samples_in: # of waveform samples you'll feed into the FFT
	// samples_out: # of frequency samples you want out; MUST BE A POWER OF 2.
	// bEqualize: set to 1 if you want the magnitude of the basses and trebles
	//   to be roughly equalized; 0 to leave them untouched.
	// envelope_power: set to -1 to disable the envelope; otherwise, specify
	//   the envelope power you want here.  See InitEnvelopeTable for more info.

	CleanUp();

	m_samples_in = samples_in;
	NFREQ = samples_out * 2;

	InitBitRevTable();
	InitCosSinTable();
	if (envelope_power > 0)
		InitEnvelopeTable(envelope_power);
	if (bEqualize)
		InitEqualizeTable(mode);
	temp1 = new float[NFREQ];
	temp2 = new float[NFREQ];
}

/*****************************************************************************/

void FFT::CleanUp()
{
	SafeDeleteArray(envelope);
	SafeDeleteArray(equalize);
	SafeDeleteArray(bitrevtable);
	SafeDeleteArray(cossintable);
	SafeDeleteArray(temp1);
	SafeDeleteArray(temp2);
}

/*****************************************************************************/

void FFT::InitEqualizeTable(const bool mode)
{
	// Setup a log table
	// the part of a log curve to use is from 1 to <log base>
	// a bit of an adjustment is added to 1 to account for the sharp drop off at the low end
	// inverse half is (<base> - 1) / <elements>
	// equalize table will have values from > ~0 to <= 1

	equalize = new float[NFREQ / 2];
	// equalize on natural log (brown noise will have a flat spectrum graph)
	//float inv_half_nfreq = 1.70828f / (float)(NFREQ / 2);
	//for(int i = 0; i < NFREQ / 2; i++)
		//equalize[i] = logf(1.01f + (float)(i + 1) * inv_half_nfreq);

	// equalize on log base 10 (pink noise will have a flat spectrum graph)
	//float inv_half_nfreq = 8.96f / (float)(NFREQ / 2);
	//for(int i = 0; i < NFREQ / 2; i++)
		//equalize[i] = log10(1.04f + (float)(i + 1) * inv_half_nfreq);

	// equalize on log base 10 (pink noise will have a flat spectrum graph)
	float bias = 0.04f;
	for(int i = 0; i < NFREQ / 2; i++) {
		const float inv_half_nfreq = (9.0f - bias) / (float)(NFREQ / 2);
		equalize[i] = log10f(1.0f + bias + (float)(i + 1) * inv_half_nfreq);
		//if(bias > 0.0001f)
			bias /= 1.0025f;
	}
}

/*****************************************************************************/

void FFT::InitEnvelopeTable(float power)
{
    // this precomputation is for multiplying the waveform sample 
    // by a bell-curve-shaped envelope, so we don't see the ugly 
    // frequency response (oscillations) of a square filter.

    // a power of 1.0 will compute the FFT with exactly one convolution.
    // a power of 2.0 is like doing it twice; the resulting frequency
    //   output will be smoothed out and the peaks will be "fatter".
    // a power of 0.5 is closer to not using an envelope, and you start
    //   to get the frequency response of the square filter as 'power'
    //   approaches zero; the peaks get tighter and more precise, but
    //   you also see small oscillations around their bases.

    float mult = 1.0f/(float)m_samples_in * 6.2831853f;

    envelope = new float[m_samples_in];

    if (power==1.0f)
        for (int i=0; i<m_samples_in; i++)
            envelope[i] = 0.5f + 0.5f*sinf(i*mult - 1.5707963268f);
    else
        for (int i=0; i<m_samples_in; i++)
            envelope[i] = powf(0.5f + 0.5f*sinf(i*mult - 1.5707963268f), power);
}

/*****************************************************************************/

void FFT::InitBitRevTable() 
{
    bitrevtable = new int[NFREQ];

    for (int i=0; i<NFREQ; i++) 
        bitrevtable[i] = i;

    for (int i=0,j=0; i < NFREQ; i++) 
    {
        if (j > i) 
        {
            const int temp = bitrevtable[i]; 
            bitrevtable[i] = bitrevtable[j]; 
            bitrevtable[j] = temp;
        }
        
        int m = NFREQ >> 1;
        
        while (m >= 1 && j >= m) 
        {
            j -= m;
            m >>= 1;
        }

        j += m;
    }
}

/*****************************************************************************/

void FFT::InitCosSinTable()
{
    int dftsize = 2;
    int tabsize = 0;
    while (dftsize <= NFREQ) 
    {
        ++tabsize;
        dftsize <<= 1;
    }

    cossintable = new float[tabsize][2];

    dftsize = 2;
    int i = 0;
    while (dftsize <= NFREQ) 
    {
        float theta = (float)(-2.0f*PI/(float)dftsize);
        cossintable[i][0] = (float)cosf(theta);
        cossintable[i][1] = (float)sinf(theta);
        ++i;
        dftsize <<= 1;
    }
}

/*****************************************************************************/

void FFT::time_to_frequency_domain(const float *in_wavedata, float *out_spectraldata)
{
    // Converts time-domain samples from in_wavedata[]
    //   into frequency-domain samples in out_spectraldata[].
    // The array lengths are the two parameters to Init().
    
    // The last sample of the output data will represent the frequency
    //   that is 1/4th of the input sampling rate.  For example,
    //   if the input wave data is sampled at 44,100 Hz, then the last 
    //   sample of the spectral data output will represent the frequency
    //   11,025 Hz.  The first sample will be 0 Hz; the frequencies of 
    //   the rest of the samples vary linearly in between.
    // Note that since human hearing is limited to the range 200 - 20,000
    //   Hz.  200 is a low bass hum; 20,000 is an ear-piercing high shriek.
    // Each time the frequency doubles, that sounds like going up an octave.
    //   That means that the difference between 200 and 300 Hz is FAR more
    //   than the difference between 5000 and 5100, for example!
    // So, when trying to analyze bass, you'll want to look at (probably)
    //   the 200-800 Hz range; whereas for treble, you'll want the 1,400 -
    //   11,025 Hz range.
    // If you want to get 3 bands, try it this way:
    //   a) 11,025 / 200 = 55.125
    //   b) to get the number of octaves between 200 and 11,025 Hz, solve for n:
    //          2^n = 55.125
    //          n = log 55.125 / log 2
    //          n = 5.785
    //   c) so each band should represent 5.785/3 = 1.928 octaves; the ranges are:
    //          1) 200 - 200*2^1.928                    or  200  - 761   Hz
    //          2) 200*2^1.928 - 200*2^(1.928*2)        or  761  - 2897  Hz
    //          3) 200*2^(1.928*2) - 200*2^(1.928*3)    or  2897 - 11025 Hz

    // A simple sine-wave-based envelope is convolved with the waveform
    //   data before doing the FFT, to emeliorate the bad frequency response
    //   of a square (i.e. nonexistent) filter.

    // You might want to slightly damp (blur) the input if your signal isn't
    //   of a very high quality, to reduce high-frequency noise that would
    //   otherwise show up in the output.

    // code should be smart enough to call Init before this function
    //if (!bitrevtable) return;
    //if (!temp1) return;
    //if (!temp2) return;
    //if (!cossintable) return;

    // 1. set up input to the fft
    if (envelope)
    {
        for (int i=0; i<NFREQ; i++) 
        {
            int idx = bitrevtable[i];
            if (idx < m_samples_in)
                temp1[i] = in_wavedata[idx] * envelope[idx];
            else
                temp1[i] = 0;
        }
    }
    else
    {
        for (int i=0; i<NFREQ; i++) 
        {
            int idx = bitrevtable[i];
            if (idx < m_samples_in)
                temp1[i] = in_wavedata[idx];// * envelope[idx];
            else
                temp1[i] = 0;
        }
    }
    memset(temp2, 0, sizeof(float)*NFREQ);
    
    // 2. perform FFT
    float *real = temp1;
    float *imag = temp2;
    int dftsize = 2;
    int t = 0;
    while (dftsize <= NFREQ) 
    {
        float wpr = cossintable[t][0];
        float wpi = cossintable[t][1];
        float wr = 1.0f;
        float wi = 0.0f;
        int hdftsize = dftsize >> 1;

        for (int m = 0; m < hdftsize; m+=1) 
        {
            for (int i = m; i < NFREQ; i+=dftsize) 
            {
                const int j = i + hdftsize;
                const float tempr = wr*real[j] - wi*imag[j];
                const float tempi = wr*imag[j] + wi*real[j];
                real[j] = real[i] - tempr;
                imag[j] = imag[i] - tempi;
                real[i] += tempr;
                imag[i] += tempi;
            }

            const float wtemp = wr;
            wr = wr*wpr - wi*wpi;
            wi = wi*wpr + wtemp*wpi;
        }

        dftsize <<= 1;
        ++t;
    }

    // 3. take the magnitude & equalize it (on a log10 scale) for output
#ifdef _DEBUG
    if (equalize)
		for (int i=0; i<NFREQ/2; i++)
		{
			float f = sqrtf(temp1[i]*temp1[i] + temp2[i]*temp2[i]);
            out_spectraldata[i] = equalize[i] * f;
		}
    else
        for (int i=0; i<NFREQ/2; i++) 
            out_spectraldata[i] = sqrtf(temp1[i]*temp1[i] + temp2[i]*temp2[i]);
#else
    if (equalize)
        for (int i=0; i<NFREQ/2; i++) 
            out_spectraldata[i] = equalize[i] * sqrtf(temp1[i]*temp1[i] + temp2[i]*temp2[i]);
    else
        for (int i=0; i<NFREQ/2; i++) 
            out_spectraldata[i] = sqrtf(temp1[i]*temp1[i] + temp2[i]*temp2[i]);
#endif
}

/*****************************************************************************/