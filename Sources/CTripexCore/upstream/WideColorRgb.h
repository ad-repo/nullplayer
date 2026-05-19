#pragma once

struct ColorRgb;

struct WideColorRgb
{
	int b, g, r, a;

	// Constructors:
	WideColorRgb();
	WideColorRgb(int new_r, int new_g, int new_b, int new_a = 255);
	WideColorRgb(const ColorRgb& other);

	// const operators
	WideColorRgb operator+(const WideColorRgb& c) const;
	WideColorRgb operator-(const WideColorRgb& c) const;
	WideColorRgb operator*(float n) const;
	WideColorRgb operator/(float n) const;
	operator ColorRgb() const;

	// operators
	WideColorRgb& operator+=(const WideColorRgb& c);
	WideColorRgb& operator-=(const WideColorRgb& c);
	WideColorRgb& operator*=(float n);
	WideColorRgb& operator/=(float n);

	// other
	int GetMaxComponent() const;
	int GetMinComponent() const;
	static WideColorRgb Blend(const WideColorRgb& c1, const WideColorRgb& c2, float fBlend);
};

WideColorRgb operator*(float n, const WideColorRgb& c);

#include "WideColorRgb.inl"
