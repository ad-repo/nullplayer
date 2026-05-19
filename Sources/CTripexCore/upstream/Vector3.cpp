#include "Platform.h"
#include "Vector3.h"

Vector3 Vector3::Cross(const Vector3& v) const
{
	float result_x = (y * v.z) - (z * v.y);
	float result_y = (z * v.x) - (x * v.z);
	float result_z = (x * v.y) - (y * v.x);
	return Vector3(result_x, result_y, result_z);
}

float Vector3::GetRoll(float tightness) const
{
	float pos = fabsf(GetPitch() / (PI / 2.0f));
	float roll_t = (pos - (1.0f - tightness)) / tightness;
	float roll = Clamp< float >(roll_t, 0.0f, 1.0f) * (PI / 2.0f);
	if (fabsf(GetYaw()) > (PI / 2.0f))
	{
		roll = -roll;
	}
	return roll;
}

Vector3 Vector3::operator*(const Matrix44& m) const
{
	Vector3 result;
	result.x = (x * m[0][0]) + (y * m[0][1]) + (z * m[0][2]) + m[0][3];
	result.y = (x * m[1][0]) + (y * m[1][1]) + (z * m[1][2]) + m[1][3];
	result.z = (x * m[2][0]) + (y * m[2][1]) + (z * m[2][2]) + m[2][3];
	return result;
}

Vector3& Vector3::operator*=(const Matrix44& m)
{
	*this = *this * m;
	return *this;
}
