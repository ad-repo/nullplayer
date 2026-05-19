#include "Platform.h"
#include "Fourier.h"
#include "Misc.h"
#include <assert.h>

/*---------------------------------
* ZFft:
-----------------------------------*/

/*---------------------------------------------
* Constructor:
---------------------------------------------*/

Fourier::Fourier(int num_samples)
	: num_samples(num_samples)
	, log_num_samples(IntegerLog2(num_samples))
{
	assert(num_samples == (1 << log_num_samples));

	// precalc apodization function
	scales = std::make_unique<float[]>(num_samples);
	float fX = -1.0f;
	float fStepX = 2.0f / (num_samples - 1.0f);
	for (int i = 0; i < num_samples; i++)
	{
		scales[i] = 1.0f - (fX * fX);
		scales[i] *= scales[i];
		scales[i] *= 1.0f / (1 << 16);
		fX += fStepX;
	}

	amplitudes = std::make_unique<float[]>(num_samples);

	transforms = std::make_unique<Complex[]>(num_samples);

	coeffs = std::make_unique<Complex[]>(num_samples + 1);
	for (int i = 0; i < num_samples; i++)
	{
		float fAng = (2.0f * PI * i) / num_samples;
		coeffs[i] = Complex(cosf(fAng), -sinf(fAng));
	}

	lookup = std::make_unique<uint16[]>(num_samples);
	for (int i = 0; i < num_samples; i++)
	{
		lookup[i] = ReverseBitOrder< short int >(i);
		lookup[i] >>= ((sizeof(short int) * 8) - log_num_samples);
	}
}

Fourier::~Fourier()
{
}

void Fourier::Update(const short int* anSample)
{
	for (int i = 0; i < num_samples; i++)
	{
		transforms[lookup[i]] = Complex(anSample[i] * scales[i], 0.0f);
	}

	int coeff_step = num_samples >> 1;
	for (int level = 0; level < log_num_samples; level++)
	{
		int step = 1 << level;
		int inc = step << 1;

		const Complex* coeff = coeffs.get();
		for (int j = 0; j < step; j++)
		{
			for (int i = j; i < num_samples; i += inc)
			{
				Complex delta = (*coeff) * transforms[i + step];
				transforms[i + step] = transforms[i] - delta;
				transforms[i] = transforms[i] + delta;
			}

			coeff += coeff_step;
		}

		step <<= 1;
		coeff_step >>= 1;
	}

	for (int i = 0; i < num_samples; i++)
	{
		amplitudes[i] = transforms[i].Length() / sqrtf(256.0f);
	}
}

float Fourier::GetAmplitude(int index) const
{
	assert(index >= 0 && index < num_samples);
	return amplitudes[index];
}
