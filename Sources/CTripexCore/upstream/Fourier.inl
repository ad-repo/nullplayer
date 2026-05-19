#include "Fourier.h"
#include <math.h>

inline Fourier::Complex::Complex()
{
	real = 0.0f;
	imag = 0.0f;
}

inline Fourier::Complex::Complex(float real, float imag)
{
	this->real = real;
	this->imag = imag;
}

inline Fourier::Complex Fourier::Complex::operator*(const Complex& other) const
{
	Complex result;
	result.real = (real * other.real) - (imag * other.imag);
	result.imag = (real * other.imag) + (imag * other.real);
	return result;
}

inline Fourier::Complex Fourier::Complex::operator+(const Complex& c) const
{
	return Complex(real + c.real, imag + c.imag);
}

inline Fourier::Complex Fourier::Complex::operator-(const Complex& c) const
{
	return Complex(real - c.real, imag - c.imag);
}

inline float Fourier::Complex::Length() const
{
	return sqrtf(real * real + imag * imag);
}


