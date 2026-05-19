// Isolated translation unit for ImageIO + CoreGraphics. Kept separate from
// RendererOpenGL.cpp because MacTypes.h declares C-struct `Point` and `Rect`
// names that collide with Tripex's `Point<T>` / `Rect<T>` class templates
// when both headers are pulled into the same TU.

#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <stdlib.h>

extern "C" int TripexPort_DecodeImageRGBA(const void* data, unsigned int data_size,
                                          int* out_width, int* out_height,
                                          unsigned char** out_rgba,
                                          const char** out_error)
{
    if (!data || data_size == 0) {
        if (out_error) *out_error = "empty input";
        return -1;
    }

    CFDataRef cf_data = CFDataCreate(kCFAllocatorDefault, (const UInt8*)data, (CFIndex)data_size);
    if (!cf_data) { if (out_error) *out_error = "CFDataCreate failed"; return -1; }

    CGImageSourceRef src = CGImageSourceCreateWithData(cf_data, nullptr);
    CFRelease(cf_data);
    if (!src) { if (out_error) *out_error = "CGImageSourceCreateWithData failed"; return -1; }

    CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, nullptr);
    CFRelease(src);
    if (!img) { if (out_error) *out_error = "CGImageSourceCreateImageAtIndex failed"; return -1; }

    size_t w = CGImageGetWidth(img);
    size_t h = CGImageGetHeight(img);
    if (w == 0 || h == 0) {
        CGImageRelease(img);
        if (out_error) *out_error = "zero-dimension image";
        return -1;
    }

    unsigned char* rgba = (unsigned char*)calloc(w * h * 4, 1);
    if (!rgba) {
        CGImageRelease(img);
        if (out_error) *out_error = "calloc failed";
        return -1;
    }

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(rgba, w, h, 8, w * 4, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) {
        free(rgba);
        CGImageRelease(img);
        if (out_error) *out_error = "CGBitmapContextCreate failed";
        return -1;
    }

    CGContextSetBlendMode(ctx, kCGBlendModeCopy);
    CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), img);
    CGContextRelease(ctx);
    CGImageRelease(img);

    *out_width = (int)w;
    *out_height = (int)h;
    *out_rgba = rgba;
    if (out_error) *out_error = nullptr;
    return 0;
}
