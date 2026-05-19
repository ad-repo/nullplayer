// Chunk 3 skeleton: clears the screen and creates textures. The
// `DrawIndexedPrimitive` body and shader/VBO plumbing land in Chunk 4.
//
// Tripex's `Renderer` interface is a thin abstraction over D3D9's
// fixed-function pipeline. The OpenGL backend maps:
//   - DrawIndexedPrimitive(VertexTL*, Face*) → streaming VBO+IBO + a single
//     shader pair (position+rhw, diffuse+specular, one texture stage).
//   - CreateTexture / CreateTextureFromImage → glGenTextures/glTexImage2D.
//   - RenderState (blend/depth/cull/shade) → glBlendFunc/glDepthFunc/etc.

#include "RendererOpenGL.h"
#include "Error.h"
#include <OpenGL/gl3.h>

////// OpenGLTexture //////

OpenGLTexture::OpenGLTexture(int width, int height, TextureFormat format, TextureFlags flags)
    : Texture(width, height, format, flags)
    , gl_id(0)
{
    GLuint tex = 0;
    glGenTextures(1, &tex);
    gl_id = (unsigned int)tex;
}

OpenGLTexture::~OpenGLTexture()
{
    if (gl_id) {
        GLuint tex = (GLuint)gl_id;
        glDeleteTextures(1, &tex);
    }
}

void OpenGLTexture::SetDirty()
{
    // No-op: texture content is uploaded eagerly on creation / explicit
    // upload paths. Tripex calls SetDirty after writing to a CPU-side
    // buffer for dynamic textures — implement readback when Chunk 4
    // exercises dynamic effects.
}

Error* OpenGLTexture::GetPixelData(std::vector<uint8>& /*buffer*/) const
{
    return new Error("OpenGLTexture::GetPixelData not implemented");
}

////// RendererOpenGL //////

RendererOpenGL::RendererOpenGL(int width, int height)
    : width_(width)
    , height_(height)
{
}

RendererOpenGL::~RendererOpenGL()
{
}

void RendererOpenGL::Resize(int width, int height)
{
    width_ = width;
    height_ = height;
}

Error* RendererOpenGL::BeginFrame()
{
    glViewport(0, 0, width_, height_);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    return nullptr;
}

Error* RendererOpenGL::EndFrame()
{
    // The host (NullPlayer's VisualizationGLView) owns context flushing.
    return nullptr;
}

Rect<int> RendererOpenGL::GetViewportRect() const
{
    return Rect<int>(0, 0, width_, height_);
}

Rect<float> RendererOpenGL::GetClipRect() const
{
    return Rect<float>(-1.0f, -1.0f, 1.0f, 1.0f);
}

static GLenum GLTextureFormatFor(TextureFormat fmt)
{
    switch (fmt) {
        case TextureFormat::X8R8G8B8: return GL_BGRA;
        case TextureFormat::P8:       return GL_RED; // palette-expanded in CPU path before upload
        default:                      return GL_BGRA;
    }
}

Error* RendererOpenGL::CreateTexture(int width, int height, TextureFormat format,
                                     const void* data, uint32 /*data_size*/,
                                     uint32 /*data_stride*/,
                                     const ColorRgb* /*palette*/,
                                     TextureFlags flags,
                                     std::shared_ptr<Texture>& out_texture)
{
    auto tex = std::make_shared<OpenGLTexture>(width, height, format, flags);

    glBindTexture(GL_TEXTURE_2D, (GLuint)tex->gl_id);
    const GLenum gl_fmt = GLTextureFormatFor(format);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0,
                 gl_fmt, GL_UNSIGNED_BYTE, data);

    const GLint filter = ((int)flags & (int)TextureFlags::Filter) ? GL_LINEAR : GL_NEAREST;
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter);
    glBindTexture(GL_TEXTURE_2D, 0);

    out_texture = tex;
    return nullptr;
}

Error* RendererOpenGL::CreateTextureFromImage(const void* /*data*/, uint32 /*data_size*/,
                                              std::shared_ptr<Texture>& /*out_texture*/)
{
    // Image-format decoding (PNG/JPEG/etc.) deferred to Chunk 4; effects
    // that exercise this path will surface in QA.
    return new Error("RendererOpenGL::CreateTextureFromImage not implemented (Chunk 4)");
}

Error* RendererOpenGL::DrawIndexedPrimitive(const RenderState& /*render_state*/,
                                            size_t /*num_vertices*/,
                                            const VertexTL* /*vertices*/,
                                            size_t /*num_faces*/,
                                            const Face* /*faces*/)
{
    // Shaders + streaming VBO/IBO + RenderState translation land in Chunk 4.
    return nullptr;
}
