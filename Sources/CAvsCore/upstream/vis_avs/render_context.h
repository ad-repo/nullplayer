#pragma once

#include "audio.h"
#include "pixel_format.h"

#include <array>

struct Buffer {
    size_t w = 0;
    size_t h = 0;
    AVS_Pixel_Format pixel_format = AVS_PIXEL_RGB0_8;
    void* data = nullptr;

    Buffer(size_t w,
           size_t h,
           AVS_Pixel_Format pixel_format,
           void* external_buffer = nullptr);
    ~Buffer();
    Buffer(const Buffer& other);
    Buffer& operator=(const Buffer& other);
    Buffer(Buffer&& other) noexcept;
    Buffer& operator=(Buffer&& other) noexcept;

   private:
    void swap(Buffer& other);
    /**
     * Does this buffer manage its own memory or does it refer to memory from the
     * outside.
     */
    bool owns_data = true;
};

struct RenderContext {
    Buffer framebuffers[2];
    size_t w = 0;
    size_t h = 0;
    AVS_Pixel_Format pixel_format = AVS_PIXEL_RGB0_8;
    std::array<Buffer, 8>& global_buffers;
    Audio& audio;
    bool is_preinit = false;
    bool needs_final_fb_copy = false;

    RenderContext(size_t w,
                  size_t h,
                  AVS_Pixel_Format pixel_format,
                  std::array<Buffer, 8>& global_buffers,
                  Audio& audio,
                  void* external_buffer = nullptr);
    void swap_framebuffers();
    void copy_secondary_to_output_framebuffer_if_needed();
};
