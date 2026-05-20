#include "Platform.h"
#include "Camera.h"

Camera::Camera()
{
	flags.set(F_SCREEN_TRANSFORM);

	screen_x = 0.0f;
	screen_y = 0.0f;
	scale = 0.0f;
	position = Vector3::Origin();
	pitch = 0.0f;
	yaw = 0.0f;
	roll = 0.0f;
	perspective = 150.0f;
	tightness = 0.1f;
}

Matrix44 Camera::GetTransform() const
{
	return Matrix44::Translate(-position) * Matrix44::Rotate(-yaw, -pitch, -roll);
}

void Camera::SetDir(const Vector3& dir)
{
	pitch = dir.GetPitch();
	yaw = dir.GetYaw();
	roll = dir.GetRoll(tightness);
}

void Camera::SetTarget(const Vector3& target)
{
	SetDir(target - position);
}
