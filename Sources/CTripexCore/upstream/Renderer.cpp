#include "Renderer.h"
#include <assert.h>

////// TextureStage //////

TextureStage::TextureStage()
{
	texture = nullptr;
	address_u = TextureAddress::Wrap;
	address_v = TextureAddress::Wrap;
};

////// RenderState //////

RenderState::RenderState()
{
	enable_culling = true;
	enable_shading = true;
	enable_specular = false;
	depth_mode = DepthMode::Normal;
	blend_mode = BlendMode::Replace;
}

////// Renderer //////

int Renderer::GetWidth() const
{
	return GetViewportRect().GetWidth();
}

int Renderer::GetHeight() const
{
	return GetViewportRect().GetHeight();
}

Error* Renderer::DrawIndexedPrimitive(const RenderState& render_state, const std::vector<VertexTL>& vertices, const std::vector<Face>& faces)
{
	Error* error = DrawIndexedPrimitive(render_state, (uint32_t)vertices.size(), vertices.data(), (uint32_t)faces.size(), faces.data());
	return TraceError(error);
}

Error* Renderer::DrawIndexedPrimitive(const RenderState& render_state, const GeometryBuffer& geometry_buffer)
{
	Error* error = DrawIndexedPrimitive(render_state, (uint32_t)geometry_buffer.vertices.size(), geometry_buffer.vertices.data(), (uint32_t)geometry_buffer.faces.size(), geometry_buffer.faces.data());
	return TraceError(error);
}

Error* Renderer::DrawSprite(const RenderState& render_state, const Point<int>& p, const Rect<int>& spr, ColorRgb diffuse, ColorRgb specular)
{
	GeometryBuffer geometry_buffer;
	geometry_buffer.AddSprite(p, spr, diffuse, specular);
	return DrawIndexedPrimitive(render_state, geometry_buffer);
}
