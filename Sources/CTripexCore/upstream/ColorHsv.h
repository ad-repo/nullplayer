#pragma once

#include <math.h>
#include "ColorRgb.h"
#include "Misc.h"

struct ColorHsv
{
	float hue, saturation, value;

	ColorHsv();
	ColorHsv(float h, float s, float v);

	void Set(float h, float s, float v);
	void Set(const ColorRgb& c, float default_hue = 0.0f, float default_saturation = 0.0f);

	void CorrectRange();
	WideColorRgb ToWideColorRgb() const;
};

inline ColorHsv::ColorHsv()
	: ColorHsv(0.0f, 0.0f, 0.0f)
{
}

inline ColorHsv::ColorHsv(float h, float s, float v)
{
	Set(h, s, v);
}

inline void ColorHsv::Set(float fH, float fS, float fV)
{
	hue = fH;
	saturation = fS;
	value = fV;
}
