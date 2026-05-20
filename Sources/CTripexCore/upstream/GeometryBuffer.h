#pragma once

#include "ColorRgb.h"
#include "Point.h"
#include "Rect.h"
#include "Face.h"
#include "error.h"
#include "Texture.h"
#include <vector>
#include "Vertex.h"

struct GeometryBuffer
{
	std::vector<VertexTL> vertices;
	std::vector<Face> faces;

	void Clear();
	void AddSprite(const Point<int>& pos, const Rect<int>& src, ColorRgb diffuse = ColorRgb::White(), ColorRgb specular = ColorRgb::Black());

	static void AddSprite(const Point<int>& pos, const Rect<int>& src, ColorRgb diffuse, ColorRgb specular, std::vector<VertexTL>& vertices, std::vector<Face>& faces);
};
