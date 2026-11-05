#pragma once

#include "pixel_format.h"

struct AVS_Image {
    void* data;
    AVS_Pixel_Format pixel_format;
    size_t pixel_size;
    int w;
    int h;
    const char* error;
};

AVS_Image* image_load(const char* filename,
                      AVS_Pixel_Format pixel_format = AVS_PIXEL_RGB0_8);
void image_free(AVS_Image* image);
