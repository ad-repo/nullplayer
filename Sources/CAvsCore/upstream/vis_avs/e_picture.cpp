/*
  LICENSE
  -------
Copyright 2005 Nullsoft, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.

  * Neither the name of Nullsoft nor the names of its contributors may be used to
    endorse or promote products derived from this software without specific prior
    written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/
#include "e_picture.h"

#include "blend.h"
#include "files.h"
#include "image.h"
#include "instance.h"
#include "math.h"

// #include "../platform.h"

#include <cstdlib>

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

constexpr Parameter Picture_Info::parameters[];
std::vector<const char*> E_Picture::file_list;

void Picture_Info::on_file_change(Effect* component,
                                  const Parameter*,
                                  const std::vector<int64_t>&) {
    ((E_Picture*)component)->load_image();
}

void Picture_Info::on_fit_change(Effect* component,
                                 const Parameter*,
                                 const std::vector<int64_t>&) {
    ((E_Picture*)component)->load_image();
}

const char* const* Picture_Info::image_files(int64_t* length_out) {
    *length_out = E_Picture::file_list.size();
    return E_Picture::file_list.data();
}

E_Picture::E_Picture(AVS_Instance* avs)
    : Configurable_Effect(avs),
      width(0),
      height(0),
      on_beat_cooldown(0),
      image_data(nullptr),
      image_lock(lock_init()) {
    if (E_Picture::file_list.empty()) {
        this->find_image_files();
    }
}

E_Picture::~E_Picture() {
    delete[] this->image_data;
    if (E_Picture::instance_count() == 1) {
        E_Picture::clear_image_files();
    }
}

static void add_file_callback(const char* file, void*) {
    size_t filename_length = strnlen(file, MAX_PATH);
    char* filename = (char*)calloc(filename_length + 1, sizeof(char));
    strncpy(filename, file, filename_length + 1);
    E_Picture::file_list.push_back(filename);
}

void E_Picture::find_image_files() {
    E_Picture::clear_image_files();
    const size_t num_extensions = 5;
    const char* extensions[num_extensions] = {".bmp", ".png", ".jpg", ".jpeg", ".gif"};
    find_files_by_extensions(this->avs->base_path.c_str(),
                             extensions,
                             num_extensions,
                             add_file_callback,
                             nullptr,
                             0,
                             /*recursive*/ false,
                             /*background*/ false);
}

void E_Picture::clear_image_files() {
    for (auto file : E_Picture::file_list) {
        free((/*mutable*/ char*)file);
    }
    E_Picture::file_list.clear();
}

void E_Picture::load_image() {
    if (this->config.image.empty()) {
        return;
    }
    char file_path[MAX_PATH];
    snprintf(file_path,
             MAX_PATH,
             "%s/%s",
             this->avs->base_path.c_str(),
             this->config.image.c_str());
    AVS_Image* tmp_image = image_load(file_path);
    if (tmp_image->data == nullptr || tmp_image->w == 0 || tmp_image->h == 0
        || tmp_image->error != nullptr) {
        this->config.error_msg = tmp_image->error;
        image_free(tmp_image);
        return;
    }

    int32_t x_start = 0;
    int32_t x_end = this->width;
    int32_t onscreen_width = this->width;
    int32_t y_start = 0;
    int32_t y_end = this->height;
    int32_t onscreen_height = this->height;
    if (this->config.fit == PICTURE_FIT_WIDTH) {
        onscreen_height = tmp_image->h * this->width / tmp_image->w;
        y_start = (this->height / 2) - (onscreen_height / 2);
        y_end = (this->height / 2) + (onscreen_height / 2);
    } else if (this->config.fit == PICTURE_FIT_HEIGHT) {
        onscreen_width = tmp_image->w * this->height / tmp_image->h;
        x_start = (this->width / 2) - (onscreen_width / 2);
        x_end = (this->width / 2) + (onscreen_width / 2);
    }
    lock_lock(this->image_lock);
    delete[] this->image_data;
    this->image_data =
        (pixel_rgb0_8*)new uint8_t[this->width * this->height * sizeof(pixel_rgb0_8)];
    auto tmp_image_data = (pixel_rgb0_8*)tmp_image->data;
    for (int32_t y = 0; y < this->height; y++) {
        int32_t source_y = (y - y_start) * tmp_image->h / onscreen_height;
        for (int32_t x = 0; x < this->width; x++) {
            if (x < x_start || x >= x_end || y < y_start || y >= y_end) {
                this->image_data[x + y * this->width] = 0;
            } else {
                int32_t source_x = (x - x_start) * tmp_image->w / onscreen_width;
                this->image_data[x + y * this->width] =
                    tmp_image_data[source_x + source_y * tmp_image->w];
            }
        }
    }
    this->config.error_msg = "";
    lock_unlock(this->image_lock);
    image_free(tmp_image);
}

int E_Picture::render(char[2][2][576],
                      int is_beat,
                      int* framebuffer,
                      int*,
                      int w,
                      int h) {
    if (this->image_data == nullptr || this->width != w || this->height != h) {
        this->width = w;
        this->height = h;
        this->load_image();
    }
    if (this->image_data == nullptr) {
        return 0;
    }
    if (is_beat & 0x80000000) {
        return 0;
    }

    if (is_beat) {
        this->on_beat_cooldown = (int32_t)this->config.on_beat_duration;
    } else if (on_beat_cooldown > 0) {
        on_beat_cooldown--;
    }

    auto dest = (uint32_t*)framebuffer;
    lock_lock(this->image_lock);
    if (this->config.blend_mode == BLEND_SIMPLE_ADDITIVE
        || (this->config.on_beat_additive && (is_beat || this->on_beat_cooldown > 0))) {
        blend_add(this->image_data, dest, dest, w, h);
    } else if (this->config.blend_mode == BLEND_SIMPLE_5050) {
        blend_5050(this->image_data, dest, dest, w, h);
    } else {
        blend_replace(this->image_data, dest, w, h);
    }
    lock_unlock(this->image_lock);

    return 0;
}

void E_Picture::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = GET_INT();
        pos += 4;
    }
    this->config.blend_mode = BLEND_SIMPLE_REPLACE;
    if (len - pos >= 4) {
        if (GET_INT()) {
            this->config.blend_mode = BLEND_SIMPLE_ADDITIVE;
        }
        pos += 4;
    }
    if (len - pos >= 4) {
        if (GET_INT()) {
            this->config.blend_mode = BLEND_SIMPLE_5050;
        }
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_additive = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.on_beat_duration = GET_INT();
        pos += 4;
    }

    auto str_data = (char*)data;
    pos += (int)E_Picture::string_nt_load_legacy(
        &str_data[pos], this->config.image, len - pos);

    bool keep_aspect_ratio = false;
    bool fit_height = false;
    if (len - pos >= 4) {
        keep_aspect_ratio = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        fit_height = GET_INT();
        pos += 4;
    }
    if (keep_aspect_ratio) {
        if (fit_height) {
            this->config.fit = PICTURE_FIT_HEIGHT;
        } else {
            this->config.fit = PICTURE_FIT_WIDTH;
        }
    } else {
        this->config.fit = PICTURE_FIT_STRETCH;
    }

    if (!this->config.image.empty()) {
        this->load_image();
    }
}

int E_Picture::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT(this->enabled);
    pos += 4;
    bool blend_additive = this->config.blend_mode == BLEND_SIMPLE_ADDITIVE;
    PUT_INT(blend_additive);
    pos += 4;
    bool blend_5050 = this->config.blend_mode == BLEND_SIMPLE_5050;
    PUT_INT(blend_5050);
    pos += 4;
    PUT_INT(this->config.on_beat_additive);
    pos += 4;
    PUT_INT(this->config.on_beat_duration);
    pos += 4;
    auto str_data = (char*)data;
    pos += (int)E_Picture::string_nt_save_legacy(
        this->config.image, &str_data[pos], LEGACY_SAVE_PATH_LEN);
    bool keep_aspect_ratio = this->config.fit != PICTURE_FIT_STRETCH;
    PUT_INT(keep_aspect_ratio);
    pos += 4;
    bool fit_height = this->config.fit == PICTURE_FIT_HEIGHT;
    PUT_INT(fit_height);
    pos += 4;
    return pos;
}

Effect_Info* create_Picture_Info() { return new Picture_Info(); }
Effect* create_Picture(AVS_Instance* avs) { return new E_Picture(avs); }
void set_Picture_desc(char* desc) { E_Picture::set_desc(desc); }
