#pragma once

#include "Vector3.h"
#include <bitset>

class Camera
{
public:
	enum
	{
		F_SCREEN_TRANSFORM,
		F_LAST,
	};

	std::bitset<F_LAST> flags;

	float screen_x, screen_y;
	float scale;

	float perspective;
	float tightness;

	Vector3 position;
	float pitch, yaw, roll;

	Camera();
	void SetDir(const Vector3& dir);
	void SetTarget(const Vector3& target);
	Matrix44 GetTransform() const;
};
