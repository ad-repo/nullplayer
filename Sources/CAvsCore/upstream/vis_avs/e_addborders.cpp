/* Reconstructed from scratch. Original APE by Goebish (https://github.com/goebish) */
#include "e_addborders.h"

#include "pixel_format.h"

constexpr Parameter AddBorders_Info::parameters[];

E_AddBorders::E_AddBorders(AVS_Instance* avs) : Configurable_Effect(avs) {}
E_AddBorders::~E_AddBorders() {}

int E_AddBorders::render(char visdata[2][2][576],
                         int is_beat,
                         int* framebuffer,
                         int* fbout,
                         int w,
                         int h) {
    (void)visdata;
    (void)is_beat;
    (void)fbout;
    int framesize;
    int border_height_px;
    int border_width_px;
    int i;
    int k;

    if (this->enabled) {
        framesize = w * (h + -1);
        border_height_px = (h * this->config.size) / 100;
        border_width_px = (w * this->config.size) / 100;
        if (border_width_px < 1) {
            border_width_px = 1;
        }
        if (border_height_px < 1) {
            border_height_px = 1;
        }
        for (i = 0; i < border_height_px; i = i + 1) {
            for (k = 0; k < w; k = k + 1) {
                framebuffer[k + i * w] = (pixel_rgb0_8)this->config.color;
            }
            for (k = framesize; k < w + framesize; k = k + 1) {
                framebuffer[k - i * w] = (pixel_rgb0_8)this->config.color;
            }
        }
        for (i = 0; i < border_width_px; i = i + 1) {
            for (k = 0; k < h; k = k + 1) {
                framebuffer[w * k + i] = (pixel_rgb0_8)this->config.color;
                framebuffer[w * k + ((w + -1) - i)] = (pixel_rgb0_8)this->config.color;
            }
        }
    }
    return 0;
}

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))
void E_AddBorders::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = GET_INT();
    } else {
        this->enabled = false;
    }
    pos += 4;
    if (len - pos >= 4) {
        this->config.color = GET_INT();
    } else {
        this->config.color = 0;
    }
    pos += 4;
    if (len - pos >= 4) {
        this->set_int(this->info.parameters[1].handle, GET_INT());
    } else {
        this->config.size = this->info.parameters[1].int_min;
    }
}

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;             \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255
int E_AddBorders::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT((uint32_t)this->enabled);
    pos += 4;
    PUT_INT((uint32_t)this->config.color);
    pos += 4;
    PUT_INT((int32_t)this->config.size);
    return 12;
}

Effect_Info* create_AddBorders_Info() { return new AddBorders_Info(); }
Effect* create_AddBorders(AVS_Instance* avs) { return new E_AddBorders(avs); }
void set_AddBorders_desc(char* desc) { E_AddBorders::set_desc(desc); }
