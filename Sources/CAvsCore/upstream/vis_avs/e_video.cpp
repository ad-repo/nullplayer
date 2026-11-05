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
#include "e_video.h"

#include "blend.h"
#include "files.h"
#include "instance.h"

#include <stdlib.h>

constexpr Parameter Video_Info::parameters[];
std::vector<std::string> E_Video::filenames;
const char** E_Video::c_filenames;

void Video_Info::on_file_change(Effect* component,
                                const Parameter*,
                                const std::vector<int64_t>&) {
    E_Video* video = (E_Video*)component;
    video->load_file();
}

const char* const* Video_Info::video_files(int64_t* length_out) {
    *length_out = E_Video::filenames.size();
    auto new_list = (const char**)malloc(E_Video::filenames.size() * sizeof(char*));
    for (size_t i = 0; i < E_Video::filenames.size(); i++) {
        new_list[i] = E_Video::filenames[i].c_str();
    }
    auto old_list = E_Video::c_filenames;
    E_Video::c_filenames = new_list;
    free(old_list);
    return E_Video::c_filenames;
}

E_Video::E_Video(AVS_Instance* avs)
    : Configurable_Effect(avs),
      video(nullptr),
      loaded(false),
      frame_index(0),
      last_time(0),
      video_file_lock(lock_init()) {
    this->find_video_files();
}

E_Video::~E_Video() { close_file(); }

static void add_file_callback(const char* file, void* data) {
    E_Video::filenames.emplace_back(file);
}

void E_Video::find_video_files() {
    E_Video::clear_video_files();
    const int num_extensions = 10;
    const char* extensions[num_extensions] = {
        ".avi",
        ".mp4",
        ".mkv",
        ".mpeg4",
        ".mov",
        ".webm",
        ".mpg",
        ".divx",
        ".m2ts",
        ".wmv",
    };
    find_files_by_extensions(this->avs->base_path.c_str(),
                             extensions,
                             num_extensions,
                             add_file_callback,
                             this,
                             sizeof(*this),
                             /*recursive*/ false,
                             /*background*/ false);
}

void E_Video::clear_video_files() { E_Video::filenames.clear(); }

void E_Video::load_file() {
    if (this->config.filename.empty()) {
        return;
    }
    char filepath[MAX_PATH];
    lock_lock(this->video_file_lock);

    if (this->loaded) {
        close_file();
    }

    sprintf(
        filepath, "%s/%s", this->avs->base_path.c_str(), this->config.filename.c_str());

    this->video = new AVS_Video(filepath, 32, 0);
    if (this->video != NULL && this->video->error == NULL) {
        this->loaded = true;
    } else {
        log_warn("Failed to load video file: %s, Reason: %s",
                 this->config.filename.c_str(),
                 this->video->error);
    }
    lock_unlock(this->video_file_lock);
}

void E_Video::close_file() {
    if (this->loaded) {
        lock_lock(this->video_file_lock);
        this->loaded = false;
        delete this->video;
        lock_unlock(this->video_file_lock);
    }
}

int E_Video::render(char[2][2][576],
                    int is_beat,
                    int* framebuffer,
                    int* fbout,
                    int w,
                    int h) {
    int i, j;
    int persist_count = 0;

    if (!this->loaded || !this->enabled || this->video->length <= 0
        || is_beat & 0x80000000) {
        return 0;
    }

    if ((this->last_time + this->config.playback_speed) <= (int64_t)timer_ms()) {
        this->frame_index += 1;
        if (this->frame_index >= this->video->length) {
            this->frame_index = 0;
        }
        this->last_time = timer_ms();
    }
    lock_lock(this->video_file_lock);
    auto frame = this->video->get_frame(this->frame_index,
                                        w,
                                        h,
                                        AVS_PIXEL_RGB0_8,
                                        (AVS_Video::Scale)this->config.resampling_mode);
    if (frame == NULL || frame->data == NULL) {
        return 0;
    }
    auto copy_success = this->video->copy(frame, fbout, AVS_PIXEL_RGB0_8);
    lock_unlock(this->video_file_lock);
    if (!copy_success) {
        return 0;
    }

    if (is_beat) {
        persist_count = this->config.on_beat_persist;
    } else if (persist_count > 0) {
        persist_count--;
    }

    auto src = (uint32_t*)fbout;
    auto dest = (uint32_t*)framebuffer;
    if (this->config.blend_mode == VIDEO_BLEND_ADD
        || (this->config.blend_mode == VIDEO_BLEND_FIFTY_FIFTY_ONBEAT_ADD
            && (is_beat || persist_count > 0))) {
        blend_add(src, dest, dest, w, h);
    } else if (this->config.blend_mode == VIDEO_BLEND_FIFTY_FIFTY
               || this->config.blend_mode == VIDEO_BLEND_FIFTY_FIFTY_ONBEAT_ADD) {
        blend_5050(src, dest, dest, w, h);
    } else {  // VIDEO_BLEND_REPLACE
        blend_replace(src, dest, w, h);
    }
    return 0;
}

void E_Video::on_load() { this->load_file(); }

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))
void E_Video::load_legacy(unsigned char* data, int len) {
    int32_t blend_add = 0;
    int32_t blend_5050 = 0;
    int32_t blend_5050_onbeat_add = 0;
    int32_t pos = 0;
    if (len - pos >= 4) {
        this->enabled = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        blend_add = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        blend_5050 = GET_INT();
        pos += 4;
    }
    char* str_data = (char*)data;
    pos +=
        Effect::string_nt_load_legacy(&str_data[pos], this->config.filename, MAX_PATH);
    if (len - pos >= 4) {
        blend_5050_onbeat_add = GET_INT();
        pos += 4;
    }
    if (blend_add > 0) {
        this->config.blend_mode = VIDEO_BLEND_ADD;
    } else if (blend_5050_onbeat_add > 0) {
        this->config.blend_mode = VIDEO_BLEND_FIFTY_FIFTY_ONBEAT_ADD;
    } else if (blend_5050 > 0) {
        this->config.blend_mode = VIDEO_BLEND_FIFTY_FIFTY;
    } else {
        this->config.blend_mode = VIDEO_BLEND_REPLACE;
    }
    if (len - pos >= 4) {
        this->config.on_beat_persist = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.playback_speed = GET_INT();
        pos += 4;
    }

    this->load_file();
}

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255
int E_Video::save_legacy(unsigned char* data) {
    int32_t pos = 0;
    PUT_INT(this->enabled);
    pos += 4;
    PUT_INT(this->config.blend_mode == VIDEO_BLEND_ADD ? 1 : 0);
    pos += 4;
    PUT_INT(this->config.blend_mode == VIDEO_BLEND_FIFTY_FIFTY ? 1 : 0);
    pos += 4;
    char* str_data = (char*)data;
    pos +=
        Effect::string_nt_save_legacy(this->config.filename, &str_data[pos], MAX_PATH);
    PUT_INT(this->config.blend_mode == VIDEO_BLEND_FIFTY_FIFTY_ONBEAT_ADD ? 1 : 0);
    pos += 4;
    PUT_INT(this->config.on_beat_persist);
    pos += 4;
    PUT_INT(this->config.playback_speed);
    pos += 4;
    return pos;
}

Effect_Info* create_Video_Info() { return new Video_Info(); }
Effect* create_Video(AVS_Instance* avs) { return new E_Video(avs); }
void set_Video_desc(char* desc) { E_Video::set_desc(desc); }
