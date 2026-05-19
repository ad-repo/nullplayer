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
#include "Vertex.h"
#include "Face.h"
#include <OpenGL/gl3.h>
#include <stddef.h>
#include <vector>

// Image decoding is split into a separate translation unit so the
// CoreGraphics / ImageIO headers don't collide with Tripex's `Point` /
// `Rect` class templates (MacTypes.h declares C structs of the same names).
extern "C" {
    // Returns 0 on success and fills width/height/rgba (caller frees via free()).
    // Returns -1 on failure; *error_msg points to a static C string description.
    int TripexPort_DecodeImageRGBA(const void* data, unsigned int data_size,
                                   int* out_width, int* out_height,
                                   unsigned char** out_rgba,
                                   const char** out_error);
}

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
    // D3D9 front-face = CW. Match that so Tripex's geometry isn't all
    // back-face culled when culling is enabled per RenderState.
    glFrontFace(GL_CW);
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

Error* RendererOpenGL::CreateTextureFromImage(const void* data, uint32 data_size,
                                              std::shared_ptr<Texture>& out_texture)
{
    if (!data || data_size == 0) {
        return new Error("RendererOpenGL::CreateTextureFromImage: empty data");
    }

    int w = 0, h = 0;
    unsigned char* rgba = nullptr;
    const char* err_msg = nullptr;
    if (TripexPort_DecodeImageRGBA(data, data_size, &w, &h, &rgba, &err_msg) != 0) {
        return new Error(err_msg ? err_msg : "CreateTextureFromImage: decode failed");
    }

    auto tex = std::make_shared<OpenGLTexture>(w, h, TextureFormat::X8R8G8B8, TextureFlags::Filter);
    glBindTexture(GL_TEXTURE_2D, (GLuint)tex->gl_id);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, (GLsizei)w, (GLsizei)h, 0,
                 GL_RGBA, GL_UNSIGNED_BYTE, rgba);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glBindTexture(GL_TEXTURE_2D, 0);
    free(rgba);

    out_texture = tex;
    return nullptr;
}

// ------------------------------------------------------------------
// Shader pair: emulates D3D9 fixed-function with VertexTL inputs.
//
// VertexTL is screen-space (pre-transformed). We map (x,y) ∈ [0..width] ×
// [0..height] to NDC, ignore the depth (use as-is, scaled), and pass
// rhw through as a w-divide hint. Diffuse + specular are passed as RGBA;
// fragment shader multiplies by texture (if enabled) and adds specular.
// ------------------------------------------------------------------

static const char* kVertexShaderSrc = R"(
#version 150 core
in vec3  in_position;
in float in_rhw;
in vec4  in_diffuse;
in vec4  in_specular;
in vec2  in_texcoord;

uniform vec2 u_viewport;

out vec4 v_diffuse;
out vec4 v_specular;
out vec2 v_texcoord;

void main() {
    float x = (in_position.x / u_viewport.x) * 2.0 - 1.0;
    float y = 1.0 - (in_position.y / u_viewport.y) * 2.0;
    float z = in_position.z;
    gl_Position = vec4(x, y, z, 1.0);
    v_diffuse  = in_diffuse;
    v_specular = in_specular;
    v_texcoord = in_texcoord;
}
)";

static const char* kFragmentShaderSrc = R"(
#version 150 core
in vec4 v_diffuse;
in vec4 v_specular;
in vec2 v_texcoord;

uniform sampler2D u_tex;
uniform int       u_enable_tex;

out vec4 frag_color;

void main() {
    vec4 base = v_diffuse;
    if (u_enable_tex != 0) {
        base = base * texture(u_tex, v_texcoord);
    }
    frag_color = vec4(base.rgb + v_specular.rgb, base.a);
}
)";

#include <stdio.h>

static unsigned int CompileShader(unsigned int kind, const char* src)
{
    GLuint sh = glCreateShader(kind);
    glShaderSource(sh, 1, &src, nullptr);
    glCompileShader(sh);
    GLint ok = GL_FALSE;
    glGetShaderiv(sh, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        GLint log_len = 0;
        glGetShaderiv(sh, GL_INFO_LOG_LENGTH, &log_len);
        std::vector<char> log(log_len > 0 ? log_len : 1, 0);
        glGetShaderInfoLog(sh, (GLsizei)log.size(), nullptr, log.data());
        fprintf(stderr, "[Tripex] shader compile failed (kind=%u):\n%s\n", kind, log.data());
        glDeleteShader(sh);
        return 0;
    }
    return sh;
}

bool RendererOpenGL::EnsurePipeline()
{
    if (program_ != 0) return true;

    GLuint vs = CompileShader(GL_VERTEX_SHADER, kVertexShaderSrc);
    GLuint fs = CompileShader(GL_FRAGMENT_SHADER, kFragmentShaderSrc);
    if (!vs || !fs) {
        if (vs) glDeleteShader(vs);
        if (fs) glDeleteShader(fs);
        return false;
    }

    GLuint prog = glCreateProgram();
    glAttachShader(prog, vs);
    glAttachShader(prog, fs);
    glBindAttribLocation(prog, 0, "in_position");
    glBindAttribLocation(prog, 1, "in_rhw");
    glBindAttribLocation(prog, 2, "in_diffuse");
    glBindAttribLocation(prog, 3, "in_specular");
    glBindAttribLocation(prog, 4, "in_texcoord");
    glLinkProgram(prog);
    glDeleteShader(vs);
    glDeleteShader(fs);

    GLint ok = GL_FALSE;
    glGetProgramiv(prog, GL_LINK_STATUS, &ok);
    if (!ok) {
        GLint log_len = 0;
        glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &log_len);
        std::vector<char> log(log_len > 0 ? log_len : 1, 0);
        glGetProgramInfoLog(prog, (GLsizei)log.size(), nullptr, log.data());
        fprintf(stderr, "[Tripex] program link failed:\n%s\n", log.data());
        glDeleteProgram(prog);
        return false;
    }

    program_ = (unsigned int)prog;
    uni_viewport_   = glGetUniformLocation(prog, "u_viewport");
    uni_tex_        = glGetUniformLocation(prog, "u_tex");
    uni_enable_tex_ = glGetUniformLocation(prog, "u_enable_tex");

    GLuint vao = 0, vbo = 0, ibo = 0;
    glGenVertexArrays(1, &vao);
    glGenBuffers(1, &vbo);
    glGenBuffers(1, &ibo);
    vao_ = (unsigned int)vao;
    vbo_ = (unsigned int)vbo;
    ibo_ = (unsigned int)ibo;

    glBindVertexArray(vao);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);

    const GLsizei stride = sizeof(VertexTL);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride,
                          (const void*)offsetof(VertexTL, position));
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 1, GL_FLOAT, GL_FALSE, stride,
                          (const void*)offsetof(VertexTL, rhw));
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 4, GL_UNSIGNED_BYTE, GL_TRUE, stride,
                          (const void*)offsetof(VertexTL, diffuse));
    glEnableVertexAttribArray(3);
    glVertexAttribPointer(3, 4, GL_UNSIGNED_BYTE, GL_TRUE, stride,
                          (const void*)offsetof(VertexTL, specular));
    glEnableVertexAttribArray(4);
    glVertexAttribPointer(4, 2, GL_FLOAT, GL_FALSE, stride,
                          (const void*)offsetof(VertexTL, tex_coords));

    glBindVertexArray(0);

    // 1×1 white default texture. macOS GL3 driver validates the
    // fragment shader's `sampler2D u_tex` binding even when our
    // `u_enable_tex` branch skips the sample — so we always keep
    // something real bound to texture unit 0.
    GLuint white = 0;
    glGenTextures(1, &white);
    const uint8_t white_pixel[4] = { 255, 255, 255, 255 };
    glBindTexture(GL_TEXTURE_2D, white);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, white_pixel);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glBindTexture(GL_TEXTURE_2D, 0);
    default_white_ = (unsigned int)white;

    return true;
}

static void ApplyBlendMode(BlendMode mode)
{
    switch (mode) {
        case BlendMode::NoOp:
            glEnable(GL_BLEND);
            glBlendFunc(GL_ZERO, GL_ONE);
            break;
        case BlendMode::Replace:
            glDisable(GL_BLEND);
            break;
        case BlendMode::Add:
            glEnable(GL_BLEND);
            glBlendFunc(GL_ONE, GL_ONE);
            break;
        case BlendMode::Tint:
            glEnable(GL_BLEND);
            glBlendFunc(GL_DST_COLOR, GL_ONE);
            break;
        case BlendMode::OverlayBackground:
            glEnable(GL_BLEND);
            glBlendFunc(GL_ZERO, GL_ONE_MINUS_SRC_ALPHA);
            break;
        case BlendMode::OverlayForeground:
            glEnable(GL_BLEND);
            glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
            break;
    }
}

static void ApplyDepthMode(DepthMode mode)
{
    switch (mode) {
        case DepthMode::Disable:
            glDisable(GL_DEPTH_TEST);
            glDepthMask(GL_FALSE);
            break;
        case DepthMode::Normal:
            glEnable(GL_DEPTH_TEST);
            glDepthFunc(GL_LEQUAL);
            glDepthMask(GL_TRUE);
            break;
        case DepthMode::Stencil:
            glEnable(GL_DEPTH_TEST);
            glDepthFunc(GL_EQUAL);
            glDepthMask(GL_FALSE);
            break;
    }
}

Error* RendererOpenGL::DrawIndexedPrimitive(const RenderState& render_state,
                                            size_t num_vertices,
                                            const VertexTL* vertices,
                                            size_t num_faces,
                                            const Face* faces)
{
    if (!num_vertices || !num_faces || !vertices || !faces) return nullptr;
    if (!EnsurePipeline()) return new Error("RendererOpenGL: pipeline init failed");

    glUseProgram((GLuint)program_);
    glUniform2f((GLint)uni_viewport_, (float)width_, (float)height_);

    // Texture binding (single stage; matches RenderState::NUM_TEXTURE_STAGES).
    const TextureStage& stage = render_state.texture_stages[0];
    if (stage.texture) {
        OpenGLTexture* gt = static_cast<OpenGLTexture*>(stage.texture);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, (GLuint)gt->gl_id);
        GLint wrap_u = (stage.address_u == TextureAddress::Wrap) ? GL_REPEAT : GL_CLAMP_TO_EDGE;
        GLint wrap_v = (stage.address_v == TextureAddress::Wrap) ? GL_REPEAT : GL_CLAMP_TO_EDGE;
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, wrap_u);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, wrap_v);
        glUniform1i((GLint)uni_tex_, 0);
        glUniform1i((GLint)uni_enable_tex_, 1);
    } else {
        // Bind 1×1 white so the sampler validates; the shader branches
        // texture-sampling off via u_enable_tex.
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, (GLuint)default_white_);
        glUniform1i((GLint)uni_tex_, 0);
        glUniform1i((GLint)uni_enable_tex_, 0);
    }

    if (render_state.enable_culling) {
        glEnable(GL_CULL_FACE);
        glCullFace(GL_BACK);
    } else {
        glDisable(GL_CULL_FACE);
    }
    ApplyBlendMode(render_state.blend_mode);
    ApplyDepthMode(render_state.depth_mode);

    glBindVertexArray((GLuint)vao_);
    glBindBuffer(GL_ARRAY_BUFFER, (GLuint)vbo_);
    glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)(num_vertices * sizeof(VertexTL)),
                 vertices, GL_STREAM_DRAW);

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, (GLuint)ibo_);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, (GLsizeiptr)(num_faces * sizeof(Face)),
                 faces, GL_STREAM_DRAW);

    glDrawElements(GL_TRIANGLES, (GLsizei)(num_faces * 3), GL_UNSIGNED_SHORT, nullptr);

    glBindVertexArray(0);
    glUseProgram(0);
    return nullptr;
}
