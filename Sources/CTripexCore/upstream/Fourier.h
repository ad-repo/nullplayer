#pragma once

#include <memory>

class Fourier
{
public:
	const int num_samples;
	const int log_num_samples;

	Fourier(int num_samples);
	~Fourier();

	void Update(const short int* samples);
	float GetAmplitude(int index) const;

private:
	struct Complex
	{
	public:
		float real;
		float imag;

		Complex();
		Complex(float real, float imag);

		Complex operator*(const Complex& c) const;
		Complex operator+(const Complex& c) const;
		Complex operator-(const Complex& c) const;

		float Length() const;
	};

	std::unique_ptr<float[]> scales;
	std::unique_ptr<uint16[]> lookup;
	std::unique_ptr<Complex[]> transforms;
	std::unique_ptr<Complex[]> coeffs;
	std::unique_ptr<float[]> amplitudes;
};

#include "Fourier.inl"
