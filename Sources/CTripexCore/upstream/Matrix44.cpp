#include "Platform.h"
#include "Vector3.h"
#include "Matrix44.h"

Matrix44::Matrix44()
	: elements
	{
		{ 1.0f, 0.0f, 0.0f, 0.0f },
		{ 0.0f, 1.0f, 0.0f, 0.0f },
		{ 0.0f, 0.0f, 1.0f, 0.0f },
		{ 0.0f, 0.0f, 0.0f, 1.0f }
	}
{
}

Matrix44 Matrix44::Identity()
{
	return Matrix44();
}

Matrix44 Matrix44::Translate(float x, float y, float z)
{
	Matrix44 m;
	m.SetRow(0, 1.0f, 0.0f, 0.0f, 0.0f);
	m.SetRow(1, 0.0f, 1.0f, 0.0f, 0.0f);
	m.SetRow(2, 0.0f, 0.0f, 1.0f, 0.0f);
	m.SetRow(3, x, y, z, 1.0f);
	return m;
}

Matrix44 Matrix44::Scale(float x, float y, float z)
{
	Matrix44 m;
	m.SetRow(0, x, 0.0f, 0.0f, 0.0f);
	m.SetRow(1, 0.0f, y, 0.0f, 0.0f);
	m.SetRow(2, 0.0f, 0.0f, z, 0.0f);
	m.SetRow(3, 0.0f, 0.0f, 0.0f, 1.0f);
	return m;
}

Matrix44 Matrix44::RotateAroundX(float pitch)
{
	float cos = cosf(pitch);
	float sin = sinf(pitch);

	Matrix44 m;
	m.SetRow(0, 1.0f, 0.0f, 0.0f, 0.0f);
	m.SetRow(1, 0.0f, cos, sin, 0.0f);
	m.SetRow(2, 0.0f, -sin, cos, 0.0f);
	m.SetRow(3, 0.0f, 0.0f, 0.0f, 1.0f);
	return m;
}

Matrix44 Matrix44::RotateAroundY(float yaw)
{
	float cos = cosf(yaw), sin = sinf(yaw);

	Matrix44 m;
	m.SetRow(0, cos, 0.0f, -sin, 0.0f);
	m.SetRow(1, 0.0f, 1.0f, 0.0f, 0.0f);
	m.SetRow(2, sin, 0.0f, cos, 0.0f);
	m.SetRow(3, 0.0f, 0.0f, 0.0f, 1.0f);
	return m;
}

Matrix44 Matrix44::RotateAroundZ(float roll)
{
	float cos = cosf(roll);
	float sin = sinf(roll);

	Matrix44 m;
	m.SetRow(0, cos, sin, 0.0f, 0.0f);
	m.SetRow(1, -sin, cos, 0.0f, 0.0f);
	m.SetRow(2, 0.0f, 0.0f, 1.0f, 0.0f);
	m.SetRow(3, 0.0f, 0.0f, 0.0f, 1.0f);
	return m;
}

Matrix44 Matrix44::Rotate(float yaw, float pitch)
{
	return RotateAroundY(yaw) * RotateAroundX(pitch);
}
Matrix44 Matrix44::Rotate(float yaw, float pitch, float roll)
{
	return Rotate(yaw, pitch) * RotateAroundZ(roll);
}
Matrix44 Matrix44::Rotate(float ang, const Vector3& v)
{
	float yaw = v.GetYaw();
	float pitch = v.GetPitch();
	return (Rotate(-pitch, -yaw) * RotateAroundZ(ang)) * Rotate(pitch, yaw);
}

Matrix44 Matrix44::operator*(const Matrix44& m) const
{
	Matrix44 result;
	for (int i = 0; i < 4; i++)
	{
		for (int j = 0; j < 4; j++)
		{
			result.elements[i][j] = 0;
			for (int k = 0; k < 4; k++)
			{
				result.elements[i][j] += elements[k][j] * m.elements[i][k];
			}
		}
	}
	return result;
}
