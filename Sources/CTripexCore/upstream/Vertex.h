#pragma once

#include "Vector3.h"
#include "ColorRgb.h"
#include "Point.h"

struct Vertex
{
	static const int MAX_TEXTURES = 1;

	Vector3 position;
	Vector3 normal;
	ColorRgb diffuse;
	ColorRgb specular;
	Point<float> tex_coord[MAX_TEXTURES];

	Vertex();
};

struct VertexTL // Transformed and lit vertex
{
	static const int MAX_TEXTURES = 1;

	Vector3 position;
	float rhw{};
	ColorRgb diffuse;
	ColorRgb specular;
	Point<float> tex_coords[MAX_TEXTURES];

	VertexTL();
};
