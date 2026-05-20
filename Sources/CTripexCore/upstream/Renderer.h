#pragma once

#include "Error.h"
#include "Vertex.h"
#include "Face.h"
#include "Texture.h"
#include "GeometryBuffer.h"
#include <memory>

enum class TextureAddress
{
	Clamp,
	Wrap
};

struct TextureStage
{
	Texture* texture;
	TextureAddress address_u;
	TextureAddress address_v;

	TextureStage();
};

enum class BlendMode
{
	NoOp,              // src = 0, dst = 1
	Replace,           // src = 1, dst = 0
	Add,               // src = 1, dst = 1
	Tint,              // src = dst, dst = 1
	OverlayBackground, // src = 0, dst = 1 - src
	OverlayForeground, // src = 1, dst = 1 - src
};

enum class DepthMode
{
	Disable,           // Do not write to z buffer
	Normal,            // Normal comparison values to z buffer 
	Stencil,           // Write when equal to existing values
};

struct RenderState
{
	static const int NUM_TEXTURE_STAGES = 1;

	bool enable_culling;
	bool enable_shading;
	bool enable_specular;
	BlendMode blend_mode;
	DepthMode depth_mode;

	TextureStage texture_stages[NUM_TEXTURE_STAGES];

	RenderState();
};

class Renderer
{
public:
	virtual Error* BeginFrame() = 0;
	virtual Error* EndFrame() = 0;

	int GetWidth() const;
	int GetHeight() const;

	virtual Rect<int> GetViewportRect() const = 0;
	virtual Rect<float> GetClipRect() const = 0;

	virtual Error* CreateTexture(int width, int height, TextureFormat format, const void* data, uint32 data_size, uint32 data_stride, const ColorRgb* palette, TextureFlags flags, std::shared_ptr<Texture> &out_texture) = 0;
	virtual Error* CreateTextureFromImage(const void* data, uint32 data_size, std::shared_ptr<Texture>& out_texture) = 0;

	Error* DrawIndexedPrimitive(const RenderState& render_state, const std::vector<VertexTL>& vertices, const std::vector<Face>& faces);
	Error* DrawIndexedPrimitive(const RenderState& render_state, const GeometryBuffer& geometry_buffer);

	virtual Error* DrawIndexedPrimitive(const RenderState& render_state, size_t num_vertices, const VertexTL* vertices, size_t num_faces, const Face* faces) = 0;

	Error* DrawSprite(const RenderState& render_state, const Point<int>& p, const Rect<int>& spr, ColorRgb diffuse = ColorRgb::White(), ColorRgb specular = ColorRgb::Black());
};
