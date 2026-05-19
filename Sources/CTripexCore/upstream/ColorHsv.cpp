#include "ColorHsv.h"

void ColorHsv::Set(const ColorRgb& c, float default_hue, float default_sat)
{
	// sat = 0, hue doesn't matter (grey) (min = max)
	// light = 0, sat + hue doesn't matter (black) (min = max = 0)

	int min_component = std::min(c.r, std::min(c.g, c.b));
	int max_component = std::max(c.r, std::max(c.g, c.b));
	float range = max_component - min_component;

	// lightness
	value = max_component / 255.0f;

	// saturation
	if (max_component == 0) saturation = default_sat;
	else saturation = range / max_component;

	// hue
	if (max_component == min_component)
	{
		hue = default_hue;
	}
	else
	{
		float range_recip = 1.0f / range;

		float diff_r = (max_component - c.r) * range_recip;
		float diff_g = (max_component - c.g) * range_recip;
		float diff_b = (max_component - c.b) * range_recip;

		if (min_component == c.r)		hue = 1.0f - diff_g + diff_r;
		else if (min_component == c.r)	hue = 3.0f - diff_b + diff_g;
		else					hue = 5.0f - diff_r + diff_b;

		hue = -PI + (hue * (PI / 3.0f));
	}
}

WideColorRgb ColorHsv::ToWideColorRgb() const
{
	ColorHsv c = *this;
	c.CorrectRange();

	float pos = (c.hue + PI) / (PI / 3.0f);
	float spread = c.saturation * c.value * 255.0f;
	float min = c.value * 255.0f - spread;

	float r = min + Clamp< float >(-1 + fabsf(pos - 3.0f), 0.0f, 1.0f) * spread;
	float g = min + Clamp< float >(+2 - fabsf(pos - 2.0f), 0.0f, 1.0f) * spread;
	float b = min + Clamp< float >(+2 - fabsf(pos - 4.0f), 0.0f, 1.0f) * spread;
	return WideColorRgb((int32)r, (int32)g, (int32)b);
}

void ColorHsv::CorrectRange()
{
	hue = Wrap(hue, -PI, +PI);
	saturation = Clamp< float >(saturation, 0.0f, 1.0f);
	value = Clamp< float >(value, 0.0f, 1.0f);
}
