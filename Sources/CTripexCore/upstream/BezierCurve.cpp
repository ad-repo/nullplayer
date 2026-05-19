#include "Platform.h"
#include "BezierCurve.h"

BezierCurve::BezierCurve()
{
}

BezierCurve::~BezierCurve()
{
}

BezierCurve::BezierCurve(int num_points)
{
	Create(num_points);
}

void BezierCurve::Create(int num_points)
{
	points.clear();

	points.resize(num_points);
	coefficients.resize(num_points);

	for(int i = 0; i < num_points; i++)
	{
		coefficients[i] = Binomial(num_points - 1, i);
	}
}

void BezierCurve::Clear()
{
	points.clear();
	coefficients.clear();
}

Vector3 &BezierCurve::GetPoint(int index)
{
	assert(index >= 0 && index < points.size());
	return points[index];
}

Vector3 &BezierCurve::operator[](int idx)
{
	return GetPoint(idx);
}

int BezierCurve::Binomial(int level, int index)
{
	assert(index >= 0 && index <= level && level >= 0);
	if (index == 0 || index == level)
	{
		return 1;
	}
	else
	{
		return Binomial(level - 1, index - 1) + Binomial(level - 1, index);
	}
}

Vector3 BezierCurve::Calculate(float pos)
{
	assert(pos >= 0 && pos <= 1);

	Vector3 v(0, 0, 0);
	for(int i = 0; i < points.size(); i++)
	{
		v += (float)(coefficients[i] * pow(pos, i) * pow(1 - pos, (points.size() - 1) - i)) * points[i];
	}
	return v;
}
