#pragma once

#include "Renderer.h"
#include "ColorRgb.h"
#include <memory>

class Canvas
{
public:
	static const int texture_w = 256;
	static const int texture_h = 256;

	const int num_textures_x;
	const int num_textures_y;
	const int stride;

	ColorRgb color;
	ColorRgb palette[256];

	Canvas(int width, int height);
	Error* Create(Renderer& renderer);
	uint8* GetDataPtr();
	Error* UploadTextures(Renderer& renderer);
	Texture* GetTexture(int x, int y);
	Error* Render(Renderer& renderer, const RenderState& render_state);

private:
	std::unique_ptr<uint8[]> data;
	std::vector<std::shared_ptr<Texture>> textures;
};
