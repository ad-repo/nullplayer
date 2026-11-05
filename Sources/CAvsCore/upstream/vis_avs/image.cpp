#include "image.h"

#ifdef _WIN32
#include <windows.h>
#endif

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ASSERT(x)                 // don't include assert.h
#define STBI_MAX_DIMENSIONS (1 << 16)  // ~65.000px should be enough?
#define STBI_FAILURE_USERMSG           // longer error messages
#include "../3rdparty/stb_image.h"

#define AVS_IMAGE_EXTENDED_BMP_SUPPORT

#ifdef AVS_IMAGE_EXTENDED_BMP_SUPPORT
/* stb_image cannot load RLE-encoded BMPs and other exotic variants. */
bool _fallback_load_bmp(const char* filename, AVS_Image* image) {
#ifdef _WIN32
    HBITMAP bmp = (HBITMAP)LoadImage(
        0, filename, IMAGE_BITMAP, 0, 0, LR_LOADFROMFILE | LR_CREATEDIBSECTION);
    if (!bmp) {
        return false;
    }
    DIBSECTION dib;
    BITMAPINFO bmp_info;
    GetObject(bmp, sizeof(dib), &dib);
    HDC bmpdc = CreateCompatibleDC(NULL);

    image->w = dib.dsBmih.biWidth;
    image->h = dib.dsBmih.biHeight;

    bmp_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmp_info.bmiHeader.biWidth = image->w;
    bmp_info.bmiHeader.biHeight = -image->h;
    bmp_info.bmiHeader.biPlanes = 1;
    bmp_info.bmiHeader.biBitCount = 32;
    bmp_info.bmiHeader.biCompression = BI_RGB;
    bmp_info.bmiHeader.biSizeImage = image->w * image->h * sizeof(uint32_t);
    bmp_info.bmiHeader.biXPelsPerMeter = 0;
    bmp_info.bmiHeader.biYPelsPerMeter = 0;
    bmp_info.bmiHeader.biClrUsed = 0xffffff;
    bmp_info.bmiHeader.biClrImportant = 0xffffff;

    image->data = new uint32_t[image->w * image->h];
    GetDIBits(bmpdc, bmp, 0, image->h, image->data, &bmp_info, DIB_RGB_COLORS);

    DeleteDC(bmpdc);
    DeleteObject(bmp);
    return true;
#else
    // TODO [feature]: Load exotic BMP formats with some other library if not on Win32.
    return false;
#endif
}
#endif

AVS_Image* image_load(const char* filename, AVS_Pixel_Format pixel_format) {
    unsigned char* stb_image;
    int channels;
    // Always ask for 4 channels. If the image is grayscale, let stbi do the conversion
    // to RGB.
    int channels_wanted = 4;

    AVS_Image* image = (AVS_Image*)calloc(1, sizeof(AVS_Image));
    stb_image = stbi_load(filename, &image->w, &image->h, &channels, channels_wanted);

    if (stb_image != NULL) {
        image->error = NULL;
        image->pixel_format = pixel_format;
        image->pixel_size = pixel_size(pixel_format);
        image->data = malloc(image->w * image->h * pixel_size(pixel_format));
        switch (pixel_format) {
            default:
            case AVS_PIXEL_RGB0_8: {
                pixel_rgb0_8* image_data = (pixel_rgb0_8*)image->data;
                for (int i = 0; i < image->w * image->h; i++) {
                    image_data[i] = (stb_image[i * channels_wanted] << 16 & 0xff0000)
                                    | (stb_image[i * channels_wanted + 1] << 8 & 0xff00)
                                    | (stb_image[i * channels_wanted + 2] & 0xff);
                }
                break;
            }
                /*
                case AVS_PIXEL_RGB0_16: {
                    pixel_rgb0_16* image_data = (pixel_rgb0_16*)image->data;
                    for (int i = 0; i < image->w * image->h; i++) {
                        image_data[i] =
                            (stb_image[i * channels_wanted] << 40 & 0xff0000000000)
                            | (stb_image[i * channels_wanted + 1] << 24 & 0xff000000)
                            | (stb_image[i * channels_wanted + 2] << 8 & 0xff00);
                    }
                    break;
                }
                */
        }
        stbi_image_free(stb_image);
    } else {
        image->error = stbi_failure_reason();
#ifdef AVS_IMAGE_EXTENDED_BMP_SUPPORT
        if (strstr(image->error, "BMP") != NULL) {
            if (!_fallback_load_bmp(filename, image)) {
                image->error = "BMP load failed (fallback)";
            }
        }
#endif
    }
    return image;
}

void image_free(AVS_Image* image) {
    free(image->data);
    free(image);
}
