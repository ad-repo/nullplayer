#pragma once

#include "Renderer.h"
#include "Texture.h"
#include <memory>

// macOS GL 3.2 core profile is supplied by the host process (NullPlayer's
// VisualizationGLView creates the context). We do not include any GL
// headers from this header to keep the upstream/upstream_port interface
// header-clean — the .cpp pulls in <OpenGL/gl3.h>.

class OpenGLTexture : public Texture {
public:
    unsigned int gl_id; // GLuint

    OpenGLTexture(int width, int height, TextureFormat format, TextureFlags flags);
    ~OpenGLTexture() override;
    void SetDirty() override;
    Error* GetPixelData(std::vector<uint8>& buffer) const override;
};

class RendererOpenGL : public Renderer {
public:
    RendererOpenGL(int width, int height);
    ~RendererOpenGL();

    Error* BeginFrame() override;
    Error* EndFrame() override;

    Rect<int>   GetViewportRect() const override;
    Rect<float> GetClipRect() const override;

    Error* CreateTexture(int width, int height, TextureFormat format,
                         const void* data, uint32 data_size, uint32 data_stride,
                         const ColorRgb* palette, TextureFlags flags,
                         std::shared_ptr<Texture>& out_texture) override;

    Error* CreateTextureFromImage(const void* data, uint32 data_size,
                                  std::shared_ptr<Texture>& out_texture) override;

    Error* DrawIndexedPrimitive(const RenderState& render_state,
                                size_t num_vertices, const VertexTL* vertices,
                                size_t num_faces, const Face* faces) override;

    void Resize(int width, int height);

private:
    int width_;
    int height_;
};
