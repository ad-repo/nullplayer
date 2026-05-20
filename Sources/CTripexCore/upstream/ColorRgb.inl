#include "ColorRgb.h"
#include "WideColorRgb.h"

inline ColorRgb::ColorRgb()
	: r(0), g(0), b(0), a(255)
{
}

inline ColorRgb::ColorRgb(float br)
{
	uint8 value = (uint8)(Clamp<float>(br, 0.0f, 1.0f) * 255.9f);
	r = g = b = value;
	a = 255;
}

inline ColorRgb::ColorRgb(uint8 new_r, uint8 new_g, uint8 new_b, uint8 new_a)
{
	r = new_r;
	g = new_g;
	b = new_b;
	a = new_a;
}

inline ColorRgb ColorRgb::White()
{
	return ColorRgb(255, 255, 255);
}

inline ColorRgb ColorRgb::Black()
{
	return ColorRgb(0, 0, 0);
}

inline ColorRgb ColorRgb::Grey(int g)
{
	uint8 value = (uint8)Clamp<int>(g, 0, 255);
	return ColorRgb(value, value, value, 255);
}

inline WideColorRgb ColorRgb::operator+(const WideColorRgb& c) const
{
	return WideColorRgb(r, g, b, a) + c;
}

inline WideColorRgb ColorRgb::operator-(const WideColorRgb& c) const
{
	return WideColorRgb(r, g, b, a) - c;
}

inline WideColorRgb ColorRgb::operator*(float n) const
{
	return WideColorRgb(r, g, b, a) * n;
}

inline WideColorRgb ColorRgb::operator/(float n) const
{
	return WideColorRgb(r, g, b, a) / n;
}

inline ColorRgb ColorRgb::Blend(const ColorRgb& c1, const ColorRgb& c2, float fBlend)
{
	int r = c1.r + (c2.r - c1.r) * fBlend;
	int g = c1.g + (c2.g - c1.g) * fBlend;
	int b = c1.b + (c2.b - c1.b) * fBlend;
	return ColorRgb(r, g, b);
}

inline ColorRgb operator*(float n, const ColorRgb& c)
{
	return c * n;
}
