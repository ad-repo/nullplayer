#include "Matrix44.h"
#include <assert.h>

inline Vector3::Vector3()
{
	x = y = z = 0;
}

inline Vector3::Vector3(float x, float y, float z)
{
	Set(x, y, z);
}

inline Vector3 Vector3::Origin()
{
	return Vector3(0.0f, 0.0f, 0.0f);
}

inline Vector3 Vector3::Polar(float length, float pitch, float yaw)
{
	return Vector3(0, 0, length) * Matrix44::Rotate(pitch, yaw);
}

inline void Vector3::Set(float new_x, float new_y, float new_z)
{
	x = new_x;
	y = new_y;
	z = new_z;
}

inline Vector3 Vector3::operator+() const
{
	return Vector3(+x, +y, +z);
}

inline Vector3 Vector3::operator+(const Vector3& v) const
{
	return Vector3(x + v.x, y + v.y, z + v.z);
}

inline Vector3 Vector3::operator-() const
{
	return Vector3(-x, -y, -z);
}

inline Vector3 Vector3::operator-(const Vector3& v) const
{
	return Vector3(x - v.x, y - v.y, z - v.z);
}

inline Vector3 Vector3::operator*(float value) const
{
	return Vector3(x * value, y * value, z * value);
}

inline Vector3 operator*(float fValue, const Vector3& v)
{
	return v * fValue;
}

inline Vector3 Vector3::operator/(float value) const
{
	return operator*(1.0f / value);
}

inline Vector3& Vector3::operator+=(const Vector3& v)
{
	x += v.x;
	y += v.y;
	z += v.z;
	return *this;
}

inline Vector3& Vector3::operator-=(const Vector3& v)
{
	x -= v.x;
	y -= v.y;
	z -= v.z;
	return *this;
}

inline Vector3& Vector3::operator*=(float value)
{
	x *= value;
	y *= value;
	z *= value;
	return *this;
}

inline Vector3& Vector3::operator/=(float value)
{
	return operator*=(1.0f / value);
}

inline float Vector3::Dot(const Vector3& v) const
{
	return (x * v.x) + (y * v.y) + (z * v.z);
}

inline float Vector3::Length() const
{
	return sqrtf(Dot(*this));
}

inline Vector3 Vector3::Normal(float length) const
{
	return operator*(length / Length());
}

inline void Vector3::Normalize(float length)
{
	operator*=(length / Length());
}

inline float Vector3::GetYaw() const
{
	return atan2f(x, z);
}

inline float Vector3::GetPitch() const
{
	return -atan2f(y, sqrtf(x * x + z * z));
}

