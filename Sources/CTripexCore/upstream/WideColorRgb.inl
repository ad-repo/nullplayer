#include "WideColorRgb.h"
#include "ColorRgb.h"

inline WideColorRgb::WideColorRgb()
	: WideColorRgb(0, 0, 0, 255)
{
}

inline WideColorRgb::WideColorRgb(int new_r, int new_g, int new_b, int new_a)
	: b(new_b), g(new_g), r(new_r), a(new_a)
{
}

inline WideColorRgb::WideColorRgb(const ColorRgb& other)
	: b(other.b), g(other.g), r(other.r), a(other.a)
{
}

inline WideColorRgb WideColorRgb::operator+(const WideColorRgb& c) const
{
	return WideColorRgb(r + c.r, g + c.g, b + c.b, a);
}

inline WideColorRgb WideColorRgb::operator-(const WideColorRgb& c) const
{
	return WideColorRgb(r - c.r, g - c.g, b - c.b, a);
}

inline WideColorRgb WideColorRgb::operator*(float n) const
{
	return WideColorRgb((int)(r * n), (int)(g * n), (int)(b * n), a);
}

inline WideColorRgb WideColorRgb::operator/(float n) const
{
	return operator*(1.0f / n);
}

inline WideColorRgb::operator ColorRgb() const
{
	return ColorRgb((uint8)Clamp<int>(r, 0, 255), (uint8)Clamp<int>(g, 0, 255), (uint8)Clamp<int>(b, 0, 255), (uint8)Clamp<int>(a, 0, 255));
}

inline WideColorRgb& WideColorRgb::operator+=(const WideColorRgb& c)
{
	return operator=(operator+(c));
}

inline WideColorRgb& WideColorRgb::operator-=(const WideColorRgb& c)
{
	return operator=(operator-(c));
}

inline WideColorRgb& WideColorRgb::operator*=(float n)
{
	return operator=(operator*(n));
}

inline WideColorRgb& WideColorRgb::operator/=(float n)
{
	return operator=(operator/(n));
}

inline int WideColorRgb::GetMaxComponent() const
{
	return std::max(r, std::max(g, b));
}

inline int WideColorRgb::GetMinComponent() const
{
	return std::min(r, std::min(g, b));
}

inline WideColorRgb WideColorRgb::Blend(const WideColorRgb& c1, const WideColorRgb& c2, float fBlend)
{
	return c1 + (c2 - c1) * fBlend;
}

inline WideColorRgb operator*(float n, const WideColorRgb& c)
{
	return c * n;
}
