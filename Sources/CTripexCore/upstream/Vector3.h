#pragma once

#include "Misc.h"

class Matrix44;

class Vector3
{
public:
	float x, y, z;

	// Constructors
	Vector3();
	Vector3(float x, float y, float z);

	// Origin( ):
	static Vector3 Origin();

	// Polar( ):
	static Vector3 Polar(float length, float pitch, float yaw);

	// Set( ):
	void Set(float x, float y, float z);

	// operator+( )/operator+=( ):
	Vector3 operator+() const;
	Vector3 operator+(const Vector3& v) const;
	Vector3& operator+=(const Vector3& v);

	// operator-( )/operator-=( ):
	Vector3 operator-() const;
	Vector3 operator-(const Vector3& v) const;
	Vector3& operator-=(const Vector3& v);

	// operator*( )/operator*=( ):
	Vector3 operator*(float value) const;
	Vector3 operator*(const Matrix44& m) const;
	Vector3& operator*=(float value);
	Vector3& operator*=(const Matrix44& m);

	// operator/( ):
	Vector3 operator/(float value) const;
	Vector3& operator/=(float value);

	// Dot( ):
	float Dot(const Vector3& v) const;

	// Length( ):
	float Length() const;

	// Normal( )/Normalize( ):
	Vector3 Normal(float length = 1.0f) const;
	void Normalize(float length = 1.0f);

	// Cross( ):
	Vector3 Cross(const Vector3& v) const;

	// GetYaw( )/GetPitch( )/GetRoll( ):
	float GetYaw() const;
	float GetPitch() const;
	float GetRoll(float tightness = 0.1f) const;
};

#include "Vector3.inl"
