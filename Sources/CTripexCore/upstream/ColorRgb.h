#pragma once

#include "Platform.h"
#include <wtypes.h>
#include "Misc.h"

struct WideColorRgb;

struct ColorRgb
{
	uint8 b, g, r, a;

	ColorRgb();
	ColorRgb(float br);
	ColorRgb(uint8 new_r, uint8 new_g, uint8 new_b, uint8 new_a = 255);

	static ColorRgb White();
	static ColorRgb Black();
	static ColorRgb Grey(int g);

	WideColorRgb operator+(const WideColorRgb& c) const;
	WideColorRgb operator-(const WideColorRgb& c) const;
	WideColorRgb operator*(float n) const;
	WideColorRgb operator/(float n) const;

	static ColorRgb Blend(const ColorRgb& c1, const ColorRgb& c2, float fBlend);// { return (ColorRgb)((c1 * (1.0f - fBlend)) + (c2 * fBlend)); }
};

ColorRgb operator*(float n, const ColorRgb& c);

#include "ColorRgb.inl"
