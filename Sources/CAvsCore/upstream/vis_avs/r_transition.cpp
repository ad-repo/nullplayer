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
#include "c_transition.h"

#include "blend.h"
#include "constants.h"
#include "render.h"

#include <math.h>
#include <stdio.h>

#define TRANSITION_PREINIT 1
#define TRANSITION_NORMAL  2
#define TRANSITION_NOTEXT  4

constexpr Parameter Transition_Info::parameters[];
constexpr char const* Transition_Info::effects[];

Transition::Transition(AVS_Instance* avs) : Configurable_Effect(avs) {
    this->enabled = false;
}

Transition::~Transition() {
    if (this->init_thread) {
        thread_join(this->init_thread, 100 /*ms*/);
        thread_destroy(this->init_thread);
        this->init_thread = nullptr;
    }
    this->reset_framebuffers();
}

uint32_t Transition::init_thread_func(void* p) {
    auto transition = (Transition*)p;
    srand(timer_us());
    if (transition->config.preinit_low_priority) {
        thread_decrease_priority(thread_current());
    }
    int* fb = (int*)calloc(transition->last_w * transition->last_h, sizeof(int));
    char last_visdata[2][2][576] = {{{0}}};
    transition->avs->root_secondary.render(
        last_visdata, (int)0x80000000, fb, fb, transition->last_w, transition->last_h);
    free(fb);

    transition->transition_flags = TRANSITION_NORMAL;
    return 0;
}

/* Replaces win32's CharPrev(), but only for ANSI mode! */
static char* prev_char(char* str, char* cur) {
    if (str >= cur) {
        return str;
    }
    return cur--;
}

static char* scanstr_back(char* str, char* toscan, char* defval) {
    char* s = str + strlen(str) - 1;
    if (strlen(str) < 1) {
        return defval;
    }
    if (strlen(toscan) < 1) {
        return defval;
    }
    while (1) {
        char* t = toscan;
        while (*t) {
            if (*t++ == *s) {
                return s;
            }
        }
        t = prev_char(str, s);
        if (t == s) {
            return defval;
        }
        s = t;
    }
}

bool Transition::transition_enabled_for(Transition_Switch switch_type) {
    switch (switch_type) {
        case TRANSITION_SWITCH_LOAD: return this->config.on_load; break;
        case TRANSITION_SWITCH_NEXT_PREV: return this->config.on_next_prev; break;
        case TRANSITION_SWITCH_RANDOM: return this->config.on_random; break;
    }
    return false;
}

bool Transition::preinit_enabled_for(Transition_Switch switch_type) {
    switch (switch_type) {
        case TRANSITION_SWITCH_LOAD: return this->config.preinit_on_load; break;
        case TRANSITION_SWITCH_NEXT_PREV:
            return this->config.preinit_on_next_prev;
            break;
        case TRANSITION_SWITCH_RANDOM: return this->config.preinit_on_random; break;
    }
    return false;
}

int Transition::load_preset(char* file,
                            Transition_Switch switch_type,
                            C_UndoItem* item) {
    if (this->init_thread) {
        if (!thread_join(this->init_thread, 0)) {
            // DDraw_SetStatusText("loading [wait]...", 1000 * 100);
            return 2;
        }
        thread_destroy(this->init_thread);
        this->init_thread = nullptr;
    }

    if (this->enabled) {
        this->enabled = false;
    }

    bool load_success = true;

    if (item) {
        if (item->size() < MAX_LEGACY_PRESET_FILESIZE_BYTES) {
            auto data = (uint8_t*)calloc(item->size(), 1);
            memcpy(data, item->get(), item->size());
            this->avs->preset_load_legacy(data, item->size(), /*with_transition*/ true);
            free(data);
            this->switch_type = switch_type;
            this->transition_flags = TRANSITION_NORMAL;
        }
    } else {
        this->last_file = file;
        if (file[0]) {
            load_success = this->avs->preset_load_file(file);
        } else {
            this->avs->clear_secondary();
        }
        if (load_success && last_w && last_h && this->preinit_enabled_for(switch_type)
            && (!this->config.preinit_only_in_fullscreen /*|| DDraw_IsFullScreen()*/)) {
            this->switch_type = switch_type;
            this->transition_flags = TRANSITION_PREINIT;
            this->init_thread = thread_create(Transition::init_thread_func, this);
            // DDraw_SetStatusText("loading...", 1000 * 100);
        } else {
            this->switch_type = switch_type;
            this->transition_flags = TRANSITION_NORMAL;
        }

        if (!load_success) {
            char s[MAX_PATH * 2];
            sprintf(
                s,
                "error loading: %s",
                this->last_file.rfind('\\') != std::string::npos
                    ? this->last_file.substr(this->last_file.rfind('\\') + 1).c_str()
                    : this->last_file.c_str());
            // DDraw_SetStatusText(s);
            this->transition_flags = TRANSITION_NORMAL | TRANSITION_NOTEXT;
        }
        // C_UndoStack::clear();
        // C_UndoStack::save_undo(this->avs, false);
        // C_UndoStack::clear_dirty();
    }

    return load_success;
}

void Transition::clean_prev_renders_if_needed() {
    if (this->prev_renders_need_cleanup) {
        this->avs->clear_secondary();
        this->prev_renders_need_cleanup = false;
    }
}

void Transition::reset_framebuffers() {
    free(this->framebuffers_primary[0]);
    this->framebuffers_primary[0] = nullptr;
    free(this->framebuffers_primary[1]);
    this->framebuffers_primary[1] = nullptr;
    free(this->framebuffers_secondary[0]);
    this->framebuffers_secondary[0] = nullptr;
    free(this->framebuffers_secondary[1]);
    this->framebuffers_secondary[1] = nullptr;
}

#define PI 3.14159265358979323846
// 264338327950288419716939937510582097494459230781640628620899862803482534211706798214808651328230664709384460955058223172535940812848...

// A global second counter, used for waiting until loading the next random preset
int g_rnd_cnt;

int Transition::render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h) {
    if (this->transition_flags || this->enabled) {
        // reset random counter if transition should start or is running (i.e. counter
        // only restarts after transition is done).
        g_rnd_cnt = 0;
    }
    if (this->transition_flags & TRANSITION_NORMAL
        || this->transition_flags & TRANSITION_NOTEXT) {
        bool notext = this->transition_flags & TRANSITION_NOTEXT;
        this->transition_flags = 0;
        if (this->transition_enabled_for(this->switch_type)) {
            this->current_effect = this->config.effect;
            if (this->current_effect == TRANSITION_RANDOM) {
                this->current_effect = (rand() % TRANSITION_NUM_EFFECTS) + 1;
            }
            this->current_keep_rendering_old_preset =
                this->config.keep_rendering_old_preset;
            this->fb_select_primary = 0;
            this->fb_select_secondary = 0;
            this->mask = 0;
            this->start_time = 0;
            this->enabled = true;
        }
        E_Root&& temp = std::move(this->avs->root);
        this->avs->root = this->avs->root_secondary;
        this->avs->root_secondary = temp;
        // TODO [bug]: Check when and how configwindow preset tree refresh will work,
        //             without calling it from here (which is inside libavs)
        /*
        extern int need_repop;
        need_repop = 1;
        PostMessage(g_hwndDlg, WM_USER + 20, 0, 0);
        */
        if (!notext && this->last_file.rfind(".aph") == this->last_file.size() - 4) {
            char buf[512];
            strncpy(
                buf,
                this->last_file.rfind('\\') != std::string::npos
                    ? this->last_file.substr(this->last_file.rfind('\\') + 1).c_str()
                    : this->last_file.c_str(),
                510);
            buf[510] = 0;
            scanstr_back(buf, ".", buf + strlen(buf))[0] = 0;
            strcat(buf, " ");
            // DDraw_SetStatusText(buf);
        }
    }

    if (!this->enabled) {
        last_w = w;
        last_h = h;
        this->reset_framebuffers();
        if (!this->init_thread && !this->avs->root_secondary.children.empty()) {
            this->prev_renders_need_cleanup = true;
        }
        return this->avs->root.render(visdata, is_beat, framebuffer, fbout, w, h);
    }

    // handle resize
    if (this->last_w != w || this->last_h != h || !this->framebuffers_primary[0]) {
        this->last_w = w;
        this->last_h = h;
        for (auto& fb : this->framebuffers_primary) {
            free(fb);
            fb = (int*)calloc(this->last_w * this->last_h, sizeof(int));
        }
        for (auto& fb : this->framebuffers_secondary) {
            free(fb);
            fb = (int*)calloc(this->last_w * this->last_h, sizeof(int));
        }
    }

    if (this->start_time == 0) {
        memcpy(this->framebuffers_primary[this->fb_select_primary],
               framebuffer,
               sizeof(int) * this->last_w * this->last_h);
        memcpy(this->framebuffers_secondary[this->fb_select_secondary],
               framebuffer,
               sizeof(int) * this->last_w * this->last_h);
    }

    // maybe there's a faster way than using 3 more buffers without screwing
    // any effect... justin ?
    if (this->current_keep_rendering_old_preset) {
        this->fb_select_secondary ^=
            this->avs->root_secondary.render(
                visdata,
                is_beat,
                this->framebuffers_secondary[this->fb_select_secondary],
                this->framebuffers_secondary[this->fb_select_secondary ^ 1],
                w,
                h)
            & 1;
    }
    this->fb_select_primary ^=
        this->avs->root.render(visdata,
                               is_beat,
                               this->framebuffers_primary[this->fb_select_primary],
                               this->framebuffers_primary[this->fb_select_primary ^ 1],
                               w,
                               h)
        & 1;

    auto p = (uint32_t*)this->framebuffers_secondary[this->fb_select_secondary];
    auto d = (uint32_t*)this->framebuffers_primary[this->fb_select_primary];
    auto dest = (uint32_t*)framebuffer;

    int64_t ttime = this->config.time_ms;
    if (ttime < 100) {
        ttime = 100;
    }
    int n;
    if (this->start_time == 0) {
        n = 0;
        this->start_time = timer_ms();
    } else {
        n = (timer_ms() - this->start_time) * 256 / ttime;
    }
    if (n >= 255) {
        n = 255;
    }

    // sintrans does a smooth sine curve from 0 to 1
    float sintrans = (float)(sin(((float)n / 255) * PI - PI / 2) / 2 + 0.5);
    switch (this->current_effect) {
        case TRANSITION_CROSS_DISSOLVE: blend_adjustable(d, p, dest, n, w, h); break;
        case TRANSITION_PUSH_LEFT_RIGHT: {
            int i = (int)(sintrans * (float)w);
            int j;
            for (j = 0; j < h; j++) {
                memcpy(framebuffer + (j * w), d + (j * w) + (w - i), i * 4);
                memcpy(framebuffer + (j * w) + i, p + (j * w), (w - i) * 4);
            }
            break;
        }
        case TRANSITION_PUSH_RIGHT_LEFT: {
            int i = (int)(sintrans * (float)w);
            int j;
            for (j = 0; j < h; j++) {
                memcpy(framebuffer + (j * w), p + (i + j * w), (w - i) * 4);
                memcpy(framebuffer + (j * w) + (w - i), d + (j * w), i * 4);
            }
            break;
        }
        case TRANSITION_PUSH_TOP_BOTTOM: {
            int i = (int)(sintrans * (float)h);
            memcpy(framebuffer, d + (h - i) * w, w * i * 4);
            memcpy(framebuffer + w * i, p, w * (h - i) * 4);
            break;
        }
        case TRANSITION_PUSH_BOTTOM_TOP: {
            int i = (int)(sintrans * (float)h);
            memcpy(framebuffer, p + i * w, w * (h - i) * 4);
            memcpy(framebuffer + w * (h - i), d, w * i * 4);
            break;
        }
        case TRANSITION_NINE_RANDOM_BLOCKS: {
            if (!(this->mask & (1 << (10 + n / 28)))) {
                int r = 0;
                if ((this->mask & 0x1ff) != 0x1ff) {
                    do {
                        r = rand() % 9;
                    } while ((1 << r) & this->mask);
                }
                this->mask |= (1 << r) | (1 << (10 + n / 28));
            }
            int j;
            int tw = w / 3, th = h / 3;
            int twr = w - 2 * tw;
            memcpy(framebuffer, p, w * h * 4);
            int i;
            for (i = 0; i < 9; i++) {
                if (this->mask & (1 << i)) {
                    int end = i / 3 * th + th;
                    if (i > 5) {
                        end = h;
                    }
                    for (j = i / 3 * th; j < end; j++) {
                        memcpy(framebuffer + (j * w) + (i % 3) * tw,
                               d + (j * w) + (i % 3) * tw,
                               (i % 3 == 2) ? twr * 4 : tw * 4);
                    }
                }
            }
            break;
        }
        case TRANSITION_SPLIT_LEFT_RIGHT_PUSH: {
            int i = (int)(sintrans * (float)w);
            int j;
            for (j = 0; j < h / 2; j++) {
                memcpy(framebuffer + (i + j * w), p + (j * w), (w - i) * 4);
                memcpy(framebuffer + (j * w), d + ((j + 1) * w) - i, i * 4);
            }
            for (j = h / 2; j < h; j++) {
                memcpy(framebuffer + (j * w), p + (i + j * w), (w - i) * 4);
                memcpy(framebuffer + (j * w) + (w - i), d + (j * w), i * 4);
            }
            break;
        }
        case TRANSITION_PUSH_LEFT_RIGHT_TO_CENTER: {
            int i = (int)(sintrans * (float)w / 2);
            int j;
            for (j = 0; j < h; j++) {
                memcpy(framebuffer + (j * w), d + ((j + 1) * w - i - w / 2), i * 4);
                memcpy(framebuffer + ((j + 1) * w - i), d + (j * w + w / 2), i * 4);
                memcpy(framebuffer + (j * w) + i, p + (j * w) + i, (w - i * 2) * 4);
            }
            break;
        }
        case TRANSITION_SQUEEZE_LEFT_RIGHT_TO_CENTER: {
            int i = (int)(sintrans * (float)w / 2);
            int j;
            for (j = 0; j < h; j++) {
                if (i) {
                    int xl = i;
                    int xp = 0;
                    int dxp = ((w / 2) << 16) / xl;
                    int* ot = framebuffer + (j * w);
                    uint32_t* it = d + (j * w);
                    while (xl--) {
                        *ot++ = it[xp >> 16];
                        xp += dxp;
                    }
                }

                if (i * 2 != w) {
                    int xl = w - i * 2;
                    int xp = 0;
                    int dxp = (w << 16) / xl;
                    int* ot = framebuffer + (j * w) + i;
                    uint32_t* it = p + (j * w);
                    while (xl--) {
                        *ot++ = it[xp >> 16];
                        xp += dxp;
                    }
                }
                if (i) {
                    int xl = i;
                    int xp = 0;
                    int dxp = ((w / 2) << 16) / xl;
                    int* ot = framebuffer + (j * w) + w - i;
                    uint32_t* it = d + (j * w) + w / 2;
                    while (xl--) {
                        *ot++ = it[xp >> 16];
                        xp += dxp;
                    }
                }
            }
            break;
        }
        case TRANSITION_WIPE_LEFT_RIGHT: {
            int i = (int)(sintrans * (float)w);
            int j;
            for (j = 0; j < h; j++) {
                memcpy(framebuffer + (i + j * w), p + (j * w) + i, (w - i) * 4);
                memcpy(framebuffer + (j * w), d + (j * w), i * 4);
            }
            break;
        }
        case TRANSITION_WIPE_RIGHT_LEFT: {
            int i = (int)(sintrans * (float)w);
            int j;
            for (j = 0; j < h; j++) {
                memcpy(framebuffer + (j * w), p + (j * w), (w - i) * 4);
                memcpy(framebuffer + (j * w) + (w - i), d + (j * w) + (w - i), i * 4);
            }
            break;
        }
        case TRANSITION_WIPE_TOP_BOTTOM: {
            int i = (int)(sintrans * (float)h);
            memcpy(framebuffer, d, w * i * 4);
            memcpy(framebuffer + w * i, p + w * i, w * (h - i) * 4);
            break;
        }
        case TRANSITION_WIPE_BOTTOM_TOP: {
            int i = (int)(sintrans * (float)h);
            memcpy(framebuffer, p, w * (h - i) * 4);
            memcpy(framebuffer + w * (h - i), d + w * (h - i), w * i * 4);
            break;
        }
        case TRANSITION_DOT_DISSOLVE: {
            int i = ((int)(sintrans * 5)) - 5;
            int j;
            int t = 0;
            int dir = 1;

            if (i < 0) {
                dir = !dir;
                i++;
                i = -i;
            }
            i = 1 << i;
            for (j = 0; j < h; j++) {
                if (t++ == i) {
                    int x = w;
                    t = 0;
                    int t2 = 0;
                    int* of = framebuffer + j * w;
                    uint32_t* p2 = (dir ? p : d) + j * w;
                    uint32_t* d2 = (dir ? d : p) + j * w;
                    while (x--) {
                        if (t2++ == i) {
                            of[0] = p2[0];
                            t2 = 0;
                        } else {
                            of[0] = d2[0];
                        }
                        p2++;
                        d2++;
                        of++;
                    }
                } else {
                    memcpy(framebuffer + j * w, (dir ? d : p) + j * w, w * sizeof(int));
                }
            }
            break;
        }
    }

    if (n == 255) {
        this->enabled = false;
        this->start_time = 0;
        this->reset_framebuffers();
        this->avs->clear_secondary();
    }
    return 0;
}

void Transition::make_legacy_config(int32_t& cfg_effect_and_keep_rendering_out,
                                    int32_t& cfg_switch_out,
                                    int32_t& cfg_preinit_out,
                                    int32_t& cfg_time_out) {
    cfg_effect_and_keep_rendering_out = (int32_t)(this->config.effect & 0x7fff);
    cfg_effect_and_keep_rendering_out |= this->config.keep_rendering_old_preset << 16;
    cfg_switch_out = this->config.on_load | (this->config.on_next_prev << 1)
                     | (this->config.on_random << 2);
    cfg_preinit_out = this->config.preinit_on_load
                      | (this->config.preinit_on_next_prev << 1)
                      | (this->config.preinit_on_random << 2)
                      | (this->config.preinit_low_priority << 5)
                      | (this->config.preinit_only_in_fullscreen << 7);
    cfg_time_out = (int32_t)(this->config.time_ms / 250);
}

void Transition::apply_legacy_config(int32_t cfg_effect_and_keep_rendering,
                                     int32_t cfg_switch,
                                     int32_t cfg_preinit,
                                     int32_t cfg_time) {
    this->config.effect = (cfg_effect_and_keep_rendering & 0x7fff);
    this->config.keep_rendering_old_preset = (cfg_effect_and_keep_rendering >> 16) & 1;
    this->config.on_load = cfg_switch & 1;
    this->config.on_next_prev = (cfg_switch >> 1) & 1;
    this->config.on_random = (cfg_switch >> 2) & 1;
    this->config.preinit_on_load = (cfg_preinit & 1);
    this->config.preinit_on_next_prev = (cfg_preinit >> 1) & 1;
    this->config.preinit_on_random = (cfg_preinit >> 2) & 1;
    this->config.preinit_low_priority = (cfg_preinit >> 5) & 1;
    this->config.preinit_only_in_fullscreen = (cfg_preinit >> 7) & 1;
    this->config.time_ms = cfg_time * 250;
}
