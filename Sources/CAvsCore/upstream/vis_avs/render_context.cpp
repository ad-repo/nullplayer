#include "render_context.h"

#include <algorithm>  // std::swap
#include <cstdlib>
#include <cstring>

Buffer::Buffer(size_t w, size_t h, AVS_Pixel_Format pixel_format, void* external_buffer)
    : w(w), h(h), pixel_format(pixel_format), data(external_buffer) {
    if (this->data == nullptr) {
        this->data = malloc(w * h * pixel_size(this->pixel_format));
    } else {
        this->owns_data = false;
    }
}

Buffer::~Buffer() {
    if (this->owns_data) {
        free(this->data);
    }
}

Buffer::Buffer(const Buffer& other)
    : w(other.w),
      h(other.h),
      pixel_format(other.pixel_format),
      data(malloc(other.w * other.h * pixel_size(other.pixel_format))) {
    memcpy(this->data, other.data, other.w * other.h * pixel_size(other.pixel_format));
}

Buffer& Buffer::operator=(const Buffer& other) {
    if (this == &other) {
        return *this;
    }
    if (this->owns_data) {
        free(this->data);
        this->data = malloc(other.w * other.h * pixel_size(other.pixel_format));
    }
    // TODO [bug][feature]: Else, resize incoming framebuffer to target if of
    //                      different size/format and this framebuffer is not owned.
    memcpy(this->data, other.data, other.w * other.h * pixel_size(this->pixel_format));
    this->w = other.w;
    this->h = other.h;
    this->pixel_format = other.pixel_format;
    return *this;
}

Buffer::Buffer(Buffer&& other) noexcept : data(nullptr) { this->swap(other); }

Buffer& Buffer::operator=(Buffer&& other) noexcept {
    this->swap(other);
    return *this;
}

// A C++ idiom for copy-c'tor- & copy-assignment deduplication:
// Define the copy-assignment operator in terms of a temporary copy and a swap of the
// members. The advantage is that swap() is simple, and reusable for move-c'tor and
// move-assignment as well.
// https://stackoverflow.com/a/3279550
void Buffer::swap(Buffer& other) {
    std::swap(this->w, other.w);
    std::swap(this->h, other.h);
    std::swap(this->pixel_format, other.pixel_format);
    std::swap(this->data, other.data);
    std::swap(this->owns_data, other.owns_data);
}

RenderContext::RenderContext(size_t w,
                             size_t h,
                             AVS_Pixel_Format pixel_format,
                             std::array<Buffer, 8>& global_buffers,
                             Audio& audio,
                             void* external_buffer)
    : w(w),
      h(h),
      pixel_format(pixel_format),
      framebuffers{Buffer(w, h, pixel_format, external_buffer),
                   Buffer(w, h, pixel_format)},
      global_buffers(global_buffers),
      audio(audio) {}

void RenderContext::swap_framebuffers() {
    std::swap(this->framebuffers[0], this->framebuffers[1]);
    this->needs_final_fb_copy = !this->needs_final_fb_copy;
}

void RenderContext::copy_secondary_to_output_framebuffer_if_needed() {
    if (this->needs_final_fb_copy) {
        // In the swapped state the final effect rendered to the secondary
        // buffer, so the output pointer is in framebuffers[1], the other one.
        // Swap the buffers one last time & then copy the contents of the
        // last-used buffer to the one with the output pointer. The final swap is
        // needed so that the output pointer is in framebuffers[0] again. For the
        // next frame the previous contents of the secondary buffer are never
        // considered and can be left as-is.
        this->swap_framebuffers();
        this->framebuffers[0] = this->framebuffers[1];
    }
}
