#pragma once

class Matrix44
{
public:
	// NOTE: matrix values are stored at (x,y) positions, not (r,c)
	float elements[4][4];

	Matrix44();
	void SetRow(int row, float v0, float v1, float v2, float v3);

	static Matrix44 Identity();

	static Matrix44 Translate(const Vector3& v);
	static Matrix44 Translate(float x, float y, float z);

	static Matrix44 Scale(float x, float y, float z);

	static Matrix44 Rotate(float yaw, float pitch);
	static Matrix44 Rotate(float yaw, float pitch, float roll);
	static Matrix44 Rotate(float ang, const Vector3& v);
	static Matrix44 RotateAroundX(float pitch);
	static Matrix44 RotateAroundY(float yaw);
	static Matrix44 RotateAroundZ(float roll);

	float* operator[ ](int pos);
	const float* operator[ ](int pos) const;

	Matrix44 operator*(const Matrix44& m) const;
	Matrix44& operator*=(const Matrix44& m);
};

#include "Matrix44.inl"
