#include "e_root.h"
#include "e_unknown.h"

#include "effect_library.h"
#include "pixel_format.h"

#include "../platform.h"
#include "../util.h"
#include "../uuid.h"

#include <iostream>

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255
#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter Root_Info::contributor_parameters[];
constexpr Parameter Root_Info::remix_parameters[];
constexpr Parameter Root_Info::parameters[];

std::string random_preset_name_slug() {
    static const char charset[] = "0123456789abcdefghijklmnopqrstuvwxyz";
    std::string slug;
    for (int i = 0; i < 10; i++) {
        slug += charset[rand() % (sizeof(charset) - 1)];
    }
    return slug;
}

E_Root::E_Root(AVS_Instance* avs) : Configurable_Effect(avs), buffers_saved(false) {
    this->config.date_init = current_date_str();
    this->config.name = "Untitled Preset " + random_preset_name_slug();
    this->config.id = uuid4();
}
E_Root::~E_Root() {
    for (int i = 0; i < NUM_GLOBAL_BUFFERS; i++) {
        free(this->buffers[i]);
        this->buffers[i] = nullptr;
        this->buffers_w[i] = 0;
        this->buffers_h[i] = 0;
    }
}

void E_Root::remix() {
    Root_BasedOn_Config based_on;
    based_on.id = this->config.id;
    based_on.name = this->config.name;
    based_on.date = this->config.date_last;
    based_on.contributors = this->config.contributors;
    this->config.based_on.push_back(based_on);
    this->config.id = uuid4();
    this->config.date_init = current_date_str();
}

int E_Root::render(char visdata[2][2][576],
                   int is_beat,
                   int* framebuffer,
                   int* fbout,
                   int w,
                   int h) {
    if (this->config.clear) {
        memset(framebuffer, 0, w * h * sizeof(pixel_rgb0_8));
    }
    bool swap_parity = false;
    for (auto& effect : this->children) {
        if (!effect->enabled) {
            continue;
        }
        bool swap = effect->render(visdata, is_beat, framebuffer, fbout, w, h);
        if (swap) {
            auto tmp = framebuffer;
            framebuffer = fbout;
            fbout = tmp;
            swap_parity = !swap_parity;
        }
    }
    if (swap_parity) {
        memcpy(fbout, framebuffer, w * h * sizeof(pixel_rgb0_8));
    }
    return 0;
}

void E_Root::render_with_context(RenderContext& ctx) {
    if (this->config.clear) {
        memset(ctx.framebuffers[0].data, 0, ctx.w * ctx.h * sizeof(pixel_rgb0_8));
    }
    char visdata[2][2][576];
    ctx.audio.to_legacy_visdata(visdata);
    for (auto& effect : this->children) {
        if (!effect->enabled) {
            continue;
        }
        bool swap = effect->render(visdata,
                                   ctx.audio.is_beat,
                                   (int32_t*)ctx.framebuffers[0].data,
                                   (int32_t*)ctx.framebuffers[1].data,
                                   ctx.w,
                                   ctx.h);
        if (swap) {
            ctx.swap_framebuffers();
        }
    }
    ctx.copy_secondary_to_output_framebuffer_if_needed();
}

void E_Root::load_legacy(unsigned char* data, int len) {
    int32_t pos = 0;
    if (len >= 1) {
        this->config.clear = data[pos++];
    }
    while (pos < len) {
        int legacy_effect_id = GET_INT();
        char legacy_effect_ape_id[LEGACY_APE_ID_LENGTH + 1];
        legacy_effect_ape_id[0] = '\0';
        pos += 4;
        if (legacy_effect_id >= DLLRENDERBASE) {
            if (pos + LEGACY_APE_ID_LENGTH > len) {
                break;
            }
            memcpy(legacy_effect_ape_id, data + pos, LEGACY_APE_ID_LENGTH);
            legacy_effect_ape_id[LEGACY_APE_ID_LENGTH] = '\0';
            pos += LEGACY_APE_ID_LENGTH;
        }
        if (pos + 4 > len) {
            break;
        }
        int l_len = GET_INT();
        pos += 4;
        if (pos + l_len > len || l_len < 0) {
            break;
        }

        Effect* new_effect =
            component_factory_legacy(legacy_effect_id, legacy_effect_ape_id, this->avs);
        new_effect->load_legacy(data + pos, l_len);
        pos += l_len;
        this->insert(new_effect, this, INSERT_CHILD);
    }
}

int E_Root::save_legacy(unsigned char* data) {
    size_t pos = 0;
    data[pos++] = this->config.clear;

    for (auto& effect : this->children) {
        if (effect == nullptr) {
            log_warn("NULL effect child in Root (%d children). This shouldn't happen.",
                     this->children.size());
            continue;
        }
        int32_t legacy_effect_id = effect->get_legacy_id();
        if (legacy_effect_id == Unknown_Info::legacy_id) {
            auto unknown = (E_Unknown*)effect;
            if (!unknown->legacy_ape_id[0]) {
                PUT_INT(unknown->legacy_id);
                pos += 4;
            } else {
                PUT_INT(DLLRENDERBASE);
                pos += 4;
                memcpy(data + pos, unknown->legacy_ape_id, LEGACY_APE_ID_LENGTH);
                pos += LEGACY_APE_ID_LENGTH;
            }
        } else {
            if (legacy_effect_id == -1) {
                PUT_INT(DLLRENDERBASE);
                pos += 4;
                // +1 so strncpy below doesn't complain
                char ape_id_buf[LEGACY_APE_ID_LENGTH + 1];
                memset(ape_id_buf, 0, LEGACY_APE_ID_LENGTH + 1);
                strncpy(ape_id_buf, effect->get_legacy_ape_id(), LEGACY_APE_ID_LENGTH);
                memcpy(data + pos, ape_id_buf, LEGACY_APE_ID_LENGTH);
                pos += LEGACY_APE_ID_LENGTH;
            } else {
                PUT_INT(legacy_effect_id);
                pos += 4;
            }
        }

        int t = effect->save_legacy(data + pos + 4);
        PUT_INT(t);
        pos += 4 + t;
    }
    return (int)pos;
}

Effect_Info* create_Root_Info() { return new Root_Info(); }
Effect* create_Root(AVS_Instance* avs) { return new E_Root(avs); }
void set_Root_desc(char* desc) { E_Root::set_desc(desc); }
