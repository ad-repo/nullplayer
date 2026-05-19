#pragma once

#include "Renderer.h"

class VertexGrid
{
private:
	int scr_width, scr_height;

public:
	std::vector<VertexTL> vertices;
	std::vector<Face> faces;
	int width, height;
	int start_x, start_y;
	float pos_x, pos_y;
	bool update_edges;

	VertexGrid(int width, int height);
	Error* Render(Renderer& renderer, const RenderState& render_state);
};
