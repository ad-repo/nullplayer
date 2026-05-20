#include "GeometryBuffer.h"

void GeometryBuffer::Clear()
{
	vertices.clear();
	faces.clear();
}

void GeometryBuffer::AddSprite(const Point<int>& pos, const Rect<int>& src, ColorRgb diffuse, ColorRgb specular)
{
	AddSprite(pos, src, diffuse, specular, vertices, faces);
}

void GeometryBuffer::AddSprite(const Point<int>& pos, const Rect<int>& src, ColorRgb diffuse, ColorRgb specular, std::vector<VertexTL>& vertices, std::vector<Face>& faces)
{
	uint16_t first_vertex = (uint16_t)vertices.size();
	vertices.resize(vertices.size() + 4);

	const float mult = 1.0f / 256.0f;

	Point<float> p2((src.left * mult), (src.top * mult));

	float w = (float)(src.right - src.left);
	float h = (float)(src.bottom - src.top);
	float tex_w = w * mult;
	float tex_h = h * mult;
	for (int i = 0; i < 4; i++)
	{
		VertexTL& vertex = vertices[first_vertex + i];
		vertex.position = Vector3(pos.x - 0.5f, pos.y - 0.5f, 0.1f);
		vertex.tex_coords[0] = p2;
		if (i == 1 || i == 2)
		{
			vertex.position.x += w;
			vertex.tex_coords[0].x += tex_w;
		}
		if (i == 2 || i == 3)
		{
			vertex.position.y += h;
			vertex.tex_coords[0].y += tex_h;
		}
		vertex.rhw = 1.0f;
		vertex.specular = specular;
		vertex.diffuse = diffuse;
	}

	faces.push_back(Face(first_vertex + 0, first_vertex + 1, first_vertex + 3));
	faces.push_back(Face(first_vertex + 1, first_vertex + 2, first_vertex + 3));
}
