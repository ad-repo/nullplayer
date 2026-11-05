/*
Reconstructed by decompiling the original colormap.ape v1.3 binary.
Credits:
  Steven Wittens (a.k.a. "Unconed" -> https://acko.net), for the original Colormap,
  & the Ghidra authors.

Most of the code deals with handling the UI interactions (all the Win32 UI API calls
were thankfully plainly visible in the decompiled binary), and the actual mapping
code is fairly straightforward.

The original implementation used MMX asm, which has been updated to using SSE2/SSSE3
intrinsics. The code could further be sped up by leveraging the "gather" instructions
available with Intel's AVX2 extension (ca. 2014 and later CPU models) to load colors by
index from the baked map.
*/
#include "e_colormap.h"

#include "blend.h"

#include <algorithm>  // std::sort & std::reverse for map colors
#include <cstdio>
#include <time.h>

// Integer range-mapping macros. Avoid truncation by multiplying first.
// Map point A from one value range to another.
// Get distance from A to B (in B-range) by mapping A to B.
#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))
#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 0xff;             \
    data[pos + 1] = ((y) >> 8) & 0xff;  \
    data[pos + 2] = ((y) >> 16) & 0xff; \
    data[pos + 3] = ((y) >> 24) & 0xff
#define CLAMP(x, lower, upper) \
    ((x) < (lower) ? (lower) : ((x) > (upper) ? (upper) : (x)))
#define CLAMPU(x, upper) ((x) > (upper) ? (upper) : (x))

constexpr Parameter ColorMap_Info::map_color_params[];
constexpr Parameter ColorMap_Info::map_params[];
constexpr Parameter ColorMap_Info::parameters[];
Handles ColorMap_Map_Color::id_factory;
Handles ColorMap_Map::id_factory;

void bake_full_map(Effect* component,
                   const Parameter*,
                   const std::vector<int64_t>& parameter_path) {
    E_ColorMap* colormap = (E_ColorMap*)component;
    colormap->bake_full_map(parameter_path[0]);
}
// TODO [clean]: Unused. Is it not necessary to (re)bake the map on map change?
void on_current_map_change(Effect* component,
                           const Parameter*,
                           const std::vector<int64_t>&) {
    E_ColorMap* colormap = (E_ColorMap*)component;
    colormap->bake_full_map(colormap->config.current_map);
}
void on_map_colors_change(Effect* component,
                          const Parameter*,
                          const std::vector<int64_t>& parameter_path,
                          int64_t,
                          int64_t) {
    bake_full_map(component, NULL, parameter_path);
}
void on_map_cycle_mode_change(Effect* component,
                              const Parameter*,
                              const std::vector<int64_t>&) {
    E_ColorMap* colormap = (E_ColorMap*)component;
    if (colormap->config.map_cycle_mode == 0) {
        colormap->config.next_map = colormap->config.current_map;
    } else {
        colormap->change_animation_step = 0;
    }
}

void flip_map(Effect* component,
              const Parameter*,
              const std::vector<int64_t>& parameter_path) {
    ((E_ColorMap*)component)->flip_map(CLAMP(parameter_path[0], 0, INT64_MAX));
}
void clear_map(Effect* component,
               const Parameter*,
               const std::vector<int64_t>& parameter_path) {
    ((E_ColorMap*)component)->clear_map(CLAMP(parameter_path[0], 0, INT64_MAX));
}
void save_map(Effect* component,
              const Parameter*,
              const std::vector<int64_t>& parameter_path) {
    ((E_ColorMap*)component)->save_map(CLAMP(parameter_path[0], 0, INT64_MAX));
}
void load_map(Effect* component,
              const Parameter*,
              const std::vector<int64_t>& parameter_path) {
    ((E_ColorMap*)component)->load_map(CLAMP(parameter_path[0], 0, INT64_MAX));
}

E_ColorMap::E_ColorMap(AVS_Instance* avs)
    : Configurable_Effect(avs),
      change_animation_step(COLORMAP_MAP_CYCLE_ANIMATION_STEPS) {
    for (size_t i = 0; i < COLORMAP_NUM_MAPS; i++) {
        this->bake_full_map(i);
    }
}

int E_ColorMap::get_new_id() { return this->next_id++; }

void E_ColorMap::flip_map(size_t map_index) {
    std::reverse(this->config.maps[map_index].colors.begin(),
                 this->config.maps[map_index].colors.end());
    for (auto& map_color : this->config.maps[map_index].colors) {
        map_color.position = NUM_COLOR_VALUES - 1 - map_color.position;
    }
    this->bake_full_map(map_index);
}
void E_ColorMap::clear_map(size_t map_index) {
    this->config.maps[map_index].colors.clear();
    this->config.maps[map_index].colors.emplace_back(0, 0x000000);
    this->config.maps[map_index].colors.emplace_back(255, 0xffffff);
    this->bake_full_map(map_index);
}

bool compare_colors(const ColorMap_Map_Color& color1,
                    const ColorMap_Map_Color& color2) {
    int diff = color1.position - color2.position;
    if (diff == 0) {
        // TODO [bugfix,feature]: If color positions are the same, the brighter color
        // gets sorted higher. This is somewhat arbitrary. We should try and sort by
        // previous position, so that when dragging a color, it does not flip until its
        // position actually becomes less than the other.
        diff = color1.color - color2.color;
    }
    return diff < 0;
}

void E_ColorMap::bake_full_map(size_t map_index) {
    unsigned int cache_index = 0;
    unsigned int color_index = 0;
    if (this->config.maps[map_index].colors.empty()) {
        return;
    }
    std::sort(this->config.maps[map_index].colors.begin(),
              this->config.maps[map_index].colors.end(),
              compare_colors);
    ColorMap_Map_Color& first = this->config.maps[map_index].colors[0];
    for (; cache_index < first.position; cache_index++) {
        this->config.maps[map_index].baked_map[cache_index] = first.color;
    }
    for (; color_index < this->config.maps[map_index].colors.size() - 1;
         color_index++) {
        ColorMap_Map_Color& from = this->config.maps[map_index].colors[color_index];
        ColorMap_Map_Color& to = this->config.maps[map_index].colors[color_index + 1];
        for (; cache_index < to.position; cache_index++) {
            int rel_i = cache_index - from.position;
            int w = to.position - from.position;
            int lerp = NUM_COLOR_VALUES * (float)rel_i / (float)w;
            uint32_t from_color = (uint32_t)(from.color & AVS_PIXEL_COLOR_MASK_RGB0_8);
            uint32_t to_color = (uint32_t)(to.color & AVS_PIXEL_COLOR_MASK_RGB0_8);
            blend_adjustable_1px(
                &from_color,
                &to_color,
                (uint32_t*)&this->config.maps[map_index].baked_map[cache_index],
                lerp);
        }
    }
    ColorMap_Map_Color& last = this->config.maps[map_index].colors[color_index];
    for (; cache_index < NUM_COLOR_VALUES; cache_index++) {
        this->config.maps[map_index].baked_map[cache_index] = last.color;
    }
}

bool E_ColorMap::any_maps_enabled() {
    bool any_maps_enabled = false;
    for (unsigned int i = 0; i < COLORMAP_NUM_MAPS; i++) {
        if (this->config.maps[i].enabled) {
            any_maps_enabled = true;
            break;
        }
    }
    return any_maps_enabled;
}

std::vector<uint64_t>& E_ColorMap::animate_map_frame(int is_beat) {
    this->config.next_map %= COLORMAP_NUM_MAPS;
    if (this->config.map_cycle_mode == COLORMAP_MAP_CYCLE_NONE
        || this->config.disable_map_change) {
        this->change_animation_step = 0;
        return this->config.maps[this->config.current_map].baked_map;
    } else {
        this->change_animation_step += this->config.map_cycle_speed;
        this->change_animation_step =
            min(this->change_animation_step, COLORMAP_MAP_CYCLE_ANIMATION_STEPS);
        if (is_beat
            && (!this->config.dont_skip_fast_beats
                || this->change_animation_step == COLORMAP_MAP_CYCLE_ANIMATION_STEPS)) {
            if (this->any_maps_enabled()) {
                do {
                    if (this->config.map_cycle_mode == COLORMAP_MAP_CYCLE_BEAT_RANDOM) {
                        this->config.next_map = rand() % COLORMAP_NUM_MAPS;
                    } else {
                        this->config.next_map =
                            (this->config.next_map + 1) % COLORMAP_NUM_MAPS;
                    }
                } while (!this->config.maps[this->config.next_map].enabled);
            }
            this->change_animation_step = 0;
        }
        if (this->change_animation_step == 0) {
            this->reset_tween_map();
        } else if (this->change_animation_step == COLORMAP_MAP_CYCLE_ANIMATION_STEPS) {
            this->config.current_map = this->config.next_map;
            this->reset_tween_map();
        } else {
            if (this->config.current_map != this->config.next_map) {
                this->animation_step();
            } else {
                this->reset_tween_map();
            }
        }
        return this->tween_map;
    }
}

inline void E_ColorMap::animation_step() {
    for (unsigned int i = 0; i < NUM_COLOR_VALUES; i++) {
        blend_adjustable_1px(
            (uint32_t*)&this->config.maps[this->config.current_map].baked_map[i],
            (uint32_t*)&this->config.maps[this->config.next_map].baked_map[i],
            (uint32_t*)&this->tween_map[i],
            this->change_animation_step);
    }
}

inline void E_ColorMap::animation_step_sse2() {
    for (unsigned int i = 0; i < NUM_COLOR_VALUES; i += 4) {
        // __m128i four_current_values =
        // _mm_loadu_si128((__m128i*)&(this->config.maps[this->config.current_map].baked_map[i]));
        // __m128i four_next_values =
        // _mm_loadu_si128((__m128i*)&(this->config.maps[this->config.next_map].baked_map[i]));
        // __m128i blend_lerp = _mm_set1_epi8((uint8_t)this->change_animation_step);
        /* TODO */
    }
}

inline void E_ColorMap::reset_tween_map() {
    this->tween_map = this->config.maps[this->config.current_map].baked_map;
}

inline int E_ColorMap::get_key(int color) {
    int r, g, b;
    switch (this->config.color_key) {
        case COLORMAP_COLOR_KEY_RED: return color >> 16 & 0xff;
        case COLORMAP_COLOR_KEY_GREEN: return color >> 8 & 0xff;
        case COLORMAP_COLOR_KEY_BLUE: return color & 0xff;
        case COLORMAP_COLOR_KEY_RGB_SUM_HALF:
            return min(
                ((color >> 16 & 0xff) + (color >> 8 & 0xff) + (color & 0xff)) / 2,
                NUM_COLOR_VALUES - 1);
        case COLORMAP_COLOR_KEY_MAX:
            r = color >> 16 & 0xff;
            g = color >> 8 & 0xff;
            b = color & 0xff;
            r = max(r, g);
            return max(r, b);
        default:
        case COLORMAP_COLOR_KEY_RGB_AVERAGE:
            return ((color >> 16 & 0xff) + (color >> 8 & 0xff) + (color & 0xff)) / 3;
    }
}

void E_ColorMap::blend(std::vector<uint64_t>& blend_map,
                       uint32_t* framebuffer,
                       int w,
                       int h) {
    uint32_t four_px_colors[4];
    int four_keys[4];
    switch (this->config.blendmode) {
        case COLORMAP_BLENDMODE_REPLACE:
            for (int i = 0; i < w * h; i += 4) {
                for (int k = 0; k < 4; k++) {
                    four_keys[k] = this->get_key(framebuffer[i + k]);
                    blend_replace_1px(&blend_map[four_keys[k]], &framebuffer[i + k]);
                }
            }
            break;
        case COLORMAP_BLENDMODE_ADDITIVE:
            for (int i = 0; i < w * h; i += 4) {
                for (int k = 0; k < 4; k++) {
                    four_keys[k] = this->get_key(framebuffer[i + k]);
                    four_px_colors[k] = blend_map[four_keys[k]];
                    blend_add_1px(
                        &four_px_colors[k], &framebuffer[i + k], &framebuffer[i + k]);
                }
            }
            break;
        case COLORMAP_BLENDMODE_MAXIMUM:
            for (int i = 0; i < w * h; i += 4) {
                for (int k = 0; k < 4; k++) {
                    four_keys[k] = this->get_key(framebuffer[i + k]);
                    four_px_colors[k] = blend_map[four_keys[k]];
                    blend_maximum_1px(
                        &four_px_colors[k], &framebuffer[i + k], &framebuffer[i + k]);
                }
            }
            break;
        case COLORMAP_BLENDMODE_MINIMUM:
            for (int i = 0; i < w * h; i += 4) {
                for (int k = 0; k < 4; k++) {
                    four_keys[k] = this->get_key(framebuffer[i + k]);
                    four_px_colors[k] = blend_map[four_keys[k]];
                    blend_minimum_1px(
                        &four_px_colors[k], &framebuffer[i + k], &framebuffer[i + k]);
                }
            }
            break;
        case COLORMAP_BLENDMODE_5050:
            for (int i = 0; i < w * h; i += 4) {
                for (int k = 0; k < 4; k++) {
                    four_keys[k] = this->get_key(framebuffer[i + k]);
                    four_px_colors[k] = blend_map[four_keys[k]];
                    blend_5050_1px(
                        &four_px_colors[k], &framebuffer[i + k], &framebuffer[i + k]);
                }
            }
            break;
        case COLORMAP_BLENDMODE_SUB1:
            for (int i = 0; i < w * h; i += 4) {
                for (int k = 0; k < 4; k++) {
                    four_keys[k] = this->get_key(framebuffer[i + k]);
                    four_px_colors[k] = blend_map[four_keys[k]];
                    blend_sub_src1_from_src2_1px(
                        &four_px_colors[k], &framebuffer[i + k], &framebuffer[i + k]);
                }
            }
            break;
        case COLORMAP_BLENDMODE_SUB2:
            for (int i = 0; i < w * h; i += 4) {
                for (int k = 0; k < 4; k++) {
                    four_keys[k] = this->get_key(framebuffer[i + k]);
                    four_px_colors[k] = blend_map[four_keys[k]];
                    blend_sub_src2_from_src1_1px(
                        &framebuffer[i + k], &four_px_colors[k], &four_px_colors[k]);
                }
            }
            break;
        case COLORMAP_BLENDMODE_MULTIPLY:
            for (int i = 0; i < w * h; i += 4) {
                for (int k = 0; k < 4; k++) {
                    four_keys[k] = this->get_key(framebuffer[i + k]);
                    four_px_colors[k] = blend_map[four_keys[k]];
                    blend_multiply_1px(
                        &four_px_colors[k], &framebuffer[i + k], &framebuffer[i + k]);
                }
            }
            break;
        case COLORMAP_BLENDMODE_XOR:
            for (int i = 0; i < w * h; i += 4) {
                for (int k = 0; k < 4; k++) {
                    four_keys[k] = this->get_key(framebuffer[i + k]);
                    four_px_colors[k] = blend_map[four_keys[k]];
                    blend_xor_1px(
                        &four_px_colors[k], &framebuffer[i + k], &framebuffer[i + k]);
                }
            }
            break;
        case COLORMAP_BLENDMODE_ADJUSTABLE:
            for (int i = 0; i < w * h; i += 4) {
                for (int k = 0; k < 4; k++) {
                    four_keys[k] = this->get_key(framebuffer[i + k]);
                    four_px_colors[k] = blend_map[four_keys[k]];
                    blend_adjustable_1px(&four_px_colors[k],
                                         &framebuffer[i + k],
                                         &framebuffer[i + k],
                                         this->config.adjustable_alpha);
                }
            }
            break;
    }
}

inline __m128i E_ColorMap::get_key_ssse3(__m128i color4) {
    // Gather uint8s from certain source locations. (0xff => dest will be zero.) Collect
    // the respective channels into the pixel's lower 8bits.
    __m128i gather_red = _mm_set_epi32(0xffffff0e, 0xffffff0a, 0xffffff06, 0xffffff02);
    __m128i gather_green =
        _mm_set_epi32(0xffffff0d, 0xffffff09, 0xffffff05, 0xffffff01);
    __m128i gather_blue = _mm_set_epi32(0xffffff0c, 0xffffff08, 0xffffff04, 0xffffff00);
    __m128i max_channel_value = _mm_set1_epi32(NUM_COLOR_VALUES - 1);
    __m128i r, g;
    __m128 color4f;
    switch (this->config.color_key) {
        case COLORMAP_COLOR_KEY_RED: return _mm_shuffle_epi8(color4, gather_red);
        case COLORMAP_COLOR_KEY_GREEN: return _mm_shuffle_epi8(color4, gather_green);
        case COLORMAP_COLOR_KEY_BLUE: return _mm_shuffle_epi8(color4, gather_blue);
        case COLORMAP_COLOR_KEY_RGB_SUM_HALF:
            r = _mm_shuffle_epi8(color4, gather_red);
            g = _mm_shuffle_epi8(color4, gather_green);
            color4 = _mm_shuffle_epi8(color4, gather_blue);
            color4 = _mm_add_epi32(color4, r);
            // Correct average, round up on odd sum, i.e.: (a+b+c + 1) >> 1:
            // color4 = _mm_avg_epu16(color4, g);
            // Original Colormap behavior, round down on .5, i.e. (a+b+c) >> 1:
            color4 = _mm_add_epi32(color4, g);
            color4 = _mm_srli_epi32(color4, 1);
            return _mm_min_epi32(color4, max_channel_value);
        case COLORMAP_COLOR_KEY_MAX:
            r = _mm_shuffle_epi8(color4, gather_red);
            g = _mm_shuffle_epi8(color4, gather_green);
            color4 = _mm_shuffle_epi8(color4, gather_blue);
            color4 = _mm_max_epu8(color4, r);
            return _mm_max_epu8(color4, g);
        default:
        case COLORMAP_COLOR_KEY_RGB_AVERAGE:
            r = _mm_shuffle_epi8(color4, gather_red);
            g = _mm_shuffle_epi8(color4, gather_green);
            color4 = _mm_shuffle_epi8(color4, gather_blue);
            color4 = _mm_add_epi16(color4, r);
            color4 = _mm_add_epi16(color4, g);
            // For inputs up to 255 * 3, float32 division returns the same results as
            // integer division
            color4f = _mm_cvtepi32_ps(color4);
            color4f = _mm_div_ps(color4f, _mm_set1_ps(3.0f));
            return _mm_cvtps_epi32(color4f);
    }
}

void E_ColorMap::blend_ssse3(std::vector<uint64_t>& blend_map,
                             uint32_t* framebuffer,
                             int w,
                             int h) {
    __m128i framebuffer_4px;
    int four_keys[4];
    __m128i colors_4px;
    __m128i extend_lo_p8_to_p16 =
        _mm_set_epi32(0xff07ff06, 0xff05ff04, 0xff03ff02, 0xff01ff00);
    __m128i extend_hi_p8_to_p16 =
        _mm_set_epi32(0xff0fff0e, 0xff0dff0c, 0xff0bff0a, 0xff09ff08);
    __m128i framebuffer_2_px[2];
    __m128i colors_2_px[2];
    switch (this->config.blendmode) {
        case COLORMAP_BLENDMODE_REPLACE:
            for (int i = 0; i < w * h; i += 4) {
                framebuffer_4px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
                _mm_store_si128((__m128i*)four_keys,
                                this->get_key_ssse3(framebuffer_4px));
                for (int k = 0; k < 4; k++) {
                    framebuffer[i + k] = blend_map[four_keys[k]];
                }
            }
            break;
        case COLORMAP_BLENDMODE_ADDITIVE:
            for (int i = 0; i < w * h; i += 4) {
                framebuffer_4px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
                _mm_store_si128((__m128i*)four_keys,
                                this->get_key_ssse3(framebuffer_4px));
                colors_4px = _mm_set_epi32(blend_map[four_keys[3]],
                                           blend_map[four_keys[2]],
                                           blend_map[four_keys[1]],
                                           blend_map[four_keys[0]]);
                framebuffer_4px = _mm_adds_epu8(framebuffer_4px, colors_4px);
                _mm_store_si128((__m128i*)&framebuffer[i], framebuffer_4px);
            }
            break;
        case COLORMAP_BLENDMODE_MAXIMUM:
            for (int i = 0; i < w * h; i += 4) {
                framebuffer_4px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
                _mm_store_si128((__m128i*)four_keys,
                                this->get_key_ssse3(framebuffer_4px));
                colors_4px = _mm_set_epi32(blend_map[four_keys[3]],
                                           blend_map[four_keys[2]],
                                           blend_map[four_keys[1]],
                                           blend_map[four_keys[0]]);
                framebuffer_4px = _mm_max_epu8(framebuffer_4px, colors_4px);
                _mm_store_si128((__m128i*)&framebuffer[i], framebuffer_4px);
            }
            break;
        case COLORMAP_BLENDMODE_MINIMUM:
            for (int i = 0; i < w * h; i += 4) {
                framebuffer_4px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
                _mm_store_si128((__m128i*)four_keys,
                                this->get_key_ssse3(framebuffer_4px));
                colors_4px = _mm_set_epi32(blend_map[four_keys[3]],
                                           blend_map[four_keys[2]],
                                           blend_map[four_keys[1]],
                                           blend_map[four_keys[0]]);
                framebuffer_4px = _mm_min_epu8(framebuffer_4px, colors_4px);
                _mm_store_si128((__m128i*)&framebuffer[i], framebuffer_4px);
            }
            break;
        case COLORMAP_BLENDMODE_5050:
            for (int i = 0; i < w * h; i += 4) {
                framebuffer_4px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
                _mm_store_si128((__m128i*)four_keys,
                                this->get_key_ssse3(framebuffer_4px));
                colors_4px = _mm_set_epi32(blend_map[four_keys[3]],
                                           blend_map[four_keys[2]],
                                           blend_map[four_keys[1]],
                                           blend_map[four_keys[0]]);
                framebuffer_4px = _mm_avg_epu8(framebuffer_4px, colors_4px);
                _mm_store_si128((__m128i*)&framebuffer[i], framebuffer_4px);
            }
            break;
        case COLORMAP_BLENDMODE_SUB1:
            for (int i = 0; i < w * h; i += 4) {
                framebuffer_4px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
                _mm_store_si128((__m128i*)four_keys,
                                this->get_key_ssse3(framebuffer_4px));
                colors_4px = _mm_set_epi32(blend_map[four_keys[3]],
                                           blend_map[four_keys[2]],
                                           blend_map[four_keys[1]],
                                           blend_map[four_keys[0]]);
                framebuffer_4px = _mm_subs_epu8(framebuffer_4px, colors_4px);
                _mm_store_si128((__m128i*)&framebuffer[i], framebuffer_4px);
            }
            break;
        case COLORMAP_BLENDMODE_SUB2:
            for (int i = 0; i < w * h; i += 4) {
                framebuffer_4px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
                _mm_store_si128((__m128i*)four_keys,
                                this->get_key_ssse3(framebuffer_4px));
                colors_4px = _mm_set_epi32(blend_map[four_keys[3]],
                                           blend_map[four_keys[2]],
                                           blend_map[four_keys[1]],
                                           blend_map[four_keys[0]]);
                framebuffer_4px = _mm_subs_epu8(colors_4px, framebuffer_4px);
                _mm_store_si128((__m128i*)&framebuffer[i], framebuffer_4px);
            }
            break;
        case COLORMAP_BLENDMODE_MULTIPLY:
            for (int i = 0; i < w * h; i += 4) {
                framebuffer_4px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
                _mm_store_si128((__m128i*)four_keys,
                                this->get_key_ssse3(framebuffer_4px));
                colors_4px = _mm_set_epi32(blend_map[four_keys[3]],
                                           blend_map[four_keys[2]],
                                           blend_map[four_keys[1]],
                                           blend_map[four_keys[0]]);
                // Unfortunately intel CPUs do not have a packed unsigned 8bit multiply.
                // So the calculation becomes a matter of extending both sides of the
                // multiplication to 16 bits, which doubles the size, resulting in 2
                // packed 128bit values.
                framebuffer_2_px[0] =
                    _mm_shuffle_epi8(framebuffer_4px, extend_lo_p8_to_p16);
                framebuffer_2_px[1] =
                    _mm_shuffle_epi8(framebuffer_4px, extend_hi_p8_to_p16);
                colors_2_px[0] = _mm_shuffle_epi8(colors_4px, extend_lo_p8_to_p16);
                colors_2_px[1] = _mm_shuffle_epi8(colors_4px, extend_hi_p8_to_p16);
                // We can then packed-multiply the half-filled 16bit (only the lower 8
                // bits are non-zero) values. Thus we are interested only in the lower
                // 16 bits of the 32bit result.
                framebuffer_2_px[0] =
                    _mm_mullo_epi16(framebuffer_2_px[0], colors_2_px[0]);
                framebuffer_2_px[1] =
                    _mm_mullo_epi16(framebuffer_2_px[1], colors_2_px[1]);
                // Divide by 256 again, to normalize. This loses accuracy, because
                // 0xff * 0xff => 0xfe, but it's the way Multiply works throughout AVS.
                framebuffer_2_px[0] = _mm_srli_epi16(framebuffer_2_px[0], 8);
                framebuffer_2_px[1] = _mm_srli_epi16(framebuffer_2_px[1], 8);
                // Pack the expanded 16bit values back into 8bit values.
                framebuffer_4px =
                    _mm_packus_epi16(framebuffer_2_px[0], framebuffer_2_px[1]);
                _mm_store_si128((__m128i*)&framebuffer[i], framebuffer_4px);
            }
            break;
        case COLORMAP_BLENDMODE_XOR:
            for (int i = 0; i < w * h; i += 4) {
                framebuffer_4px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
                _mm_store_si128((__m128i*)four_keys,
                                this->get_key_ssse3(framebuffer_4px));
                colors_4px = _mm_set_epi32(blend_map[four_keys[3]],
                                           blend_map[four_keys[2]],
                                           blend_map[four_keys[1]],
                                           blend_map[four_keys[0]]);
                framebuffer_4px = _mm_xor_si128(framebuffer_4px, colors_4px);
                _mm_store_si128((__m128i*)&framebuffer[i], framebuffer_4px);
            }
            break;
        case COLORMAP_BLENDMODE_ADJUSTABLE:
            __m128i v = _mm_set1_epi16((unsigned char)this->config.adjustable_alpha);
            __m128i i_v = _mm_set1_epi16(COLORMAP_ADJUSTABLE_BLEND_MAX
                                         - this->config.adjustable_alpha);
            for (int i = 0; i < w * h; i += 4) {
                framebuffer_4px = _mm_loadu_si128((__m128i*)&framebuffer[i]);
                _mm_store_si128((__m128i*)four_keys,
                                this->get_key_ssse3(framebuffer_4px));
                colors_4px = _mm_set_epi32(blend_map[four_keys[3]],
                                           blend_map[four_keys[2]],
                                           blend_map[four_keys[1]],
                                           blend_map[four_keys[0]]);
                // See Multiply blend case for details. This is basically the same
                // thing, except that each side gets multiplied with v and 1-v
                // respectively and then added together.
                framebuffer_2_px[0] =
                    _mm_shuffle_epi8(framebuffer_4px, extend_lo_p8_to_p16);
                framebuffer_2_px[1] =
                    _mm_shuffle_epi8(framebuffer_4px, extend_hi_p8_to_p16);
                colors_2_px[0] = _mm_shuffle_epi8(colors_4px, extend_lo_p8_to_p16);
                colors_2_px[1] = _mm_shuffle_epi8(colors_4px, extend_hi_p8_to_p16);
                framebuffer_2_px[0] = _mm_mullo_epi16(framebuffer_2_px[0], i_v);
                framebuffer_2_px[1] = _mm_mullo_epi16(framebuffer_2_px[1], i_v);
                colors_2_px[0] = _mm_mullo_epi16(colors_2_px[0], v);
                colors_2_px[1] = _mm_mullo_epi16(colors_2_px[1], v);
                framebuffer_2_px[0] =
                    _mm_adds_epu16(framebuffer_2_px[0], colors_2_px[0]);
                framebuffer_2_px[1] =
                    _mm_adds_epu16(framebuffer_2_px[1], colors_2_px[1]);
                framebuffer_2_px[0] = _mm_srli_epi16(framebuffer_2_px[0], 8);
                framebuffer_2_px[1] = _mm_srli_epi16(framebuffer_2_px[1], 8);
                framebuffer_4px =
                    _mm_packus_epi16(framebuffer_2_px[0], framebuffer_2_px[1]);
                _mm_store_si128((__m128i*)&framebuffer[i], framebuffer_4px);
            }
            break;
    }
}

int E_ColorMap::render(char[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int*,
                       int w,
                       int h) {
    auto blend_map = this->animate_map_frame(is_beat);
    this->blend_ssse3(blend_map, (uint32_t*)framebuffer, w, h);
    // this->blend(blend_map, (uint32_t*)framebuffer, w, h);
    return 0;
}

void E_ColorMap::on_load() {
    for (size_t map_index = 0; map_index < this->config.maps.size(); map_index++) {
        this->bake_full_map(map_index);
    }
}

void E_ColorMap::save_map(size_t map_index) {
    FILE* file = fopen(this->config.maps[map_index].filepath.c_str(), "wb");
    if (file == NULL) {
        return;
    }
    fwrite("CLM1", 4, 1, file);
    uint32_t colors_length =
        CLAMPU(this->config.maps[map_index].colors.size(), COLORMAP_MAX_COLORS);
    fwrite(&colors_length, sizeof(uint32_t), 1, file);
    for (uint32_t i = 0; i < colors_length; i++) {
        auto const& color = this->config.maps[map_index].colors[i];
        fwrite((uint32_t*)&color.position, sizeof(uint32_t), 1, file);
        fwrite((uint32_t*)&color.color, sizeof(uint32_t), 1, file);
        fwrite((uint32_t*)&color.color_id, sizeof(uint32_t), 1, file);
    }
    fclose(file);
}
void E_ColorMap::load_map(size_t map_index) {
    unsigned char* contents;
    size_t filesize;
    size_t bytes_read;
    uint32_t length;
    int colors_offset;
    FILE* file = fopen(this->config.maps[map_index].filepath.c_str(), "rb");
    if (file == NULL) {
        return;
    }
    fseek(file, 0, SEEK_END);
    filesize = min(ftell(file), COLORMAP_MAP_FILESIZE_MAX);
    contents = new unsigned char[filesize];
    fseek(file, 0, SEEK_SET);
    bytes_read = fread(contents, 1, filesize, file);
    if (!bytes_read) {
        delete[] contents;
        return;
    }
    fclose(file);
    if (strncmp((char*)contents, "CLM1", 4) != 0) {
        delete[] contents;
        return;
    }
    length = *(uint32_t*)(contents + 4);
    colors_offset = 4 /*CLM1*/ + 4 /*length*/;
    if (length > COLORMAP_MAX_COLORS
        || length != ((bytes_read - colors_offset) / COLORMAP_MAP_COLOR_CONFIG_SIZE)) {
        length = (bytes_read - colors_offset) / COLORMAP_MAP_COLOR_CONFIG_SIZE;
    }
    this->load_map_colors(contents, bytes_read, colors_offset, map_index, length);
    delete[] contents;
}

size_t E_ColorMap::load_map_header(unsigned char* data,
                                   int len,
                                   size_t map_index,
                                   int pos) {
    if (len - pos < (int)COLORMAP_SAVE_MAP_HEADER_SIZE) {
        return false;
    }
    this->config.maps[map_index].enabled = GET_INT();
    pos += 4;
    size_t length = GET_INT();
    pos += 4;
    this->config.maps[map_index].map_id = this->get_new_id();
    pos += 4;
    this->config.maps[map_index].filepath = std::string(
        (const char*)&data[pos], (size_t)(COLORMAP_MAP_FILENAME_MAXLEN - 1));
    return length;
}

bool E_ColorMap::load_map_colors(unsigned char* data,
                                 int len,
                                 int pos,
                                 size_t map_index,
                                 uint32_t map_length) {
    unsigned int i;
    this->config.maps[map_index].colors.clear();
    for (i = 0; i < map_length; i++) {
        if ((len - pos) < (int32_t)COLORMAP_MAP_COLOR_CONFIG_SIZE) {
            return false;
        }
        int64_t position = GET_INT();
        pos += 4;
        int64_t color = GET_INT();
        pos += 4;
        // int64_t color_id = GET_INT(); // ignore
        pos += 4;
        this->config.maps[map_index].colors.emplace_back(position, color);
    }
    this->bake_full_map(map_index);
    return true;
}

void E_ColorMap::load_legacy(unsigned char* data, int len) {
    unsigned int pos = 0;
    if (len < (int32_t)COLORMAP_BASE_CONFIG_SIZE) {
        return;
    }
    this->config.color_key = GET_INT();
    pos += 4;
    this->config.blendmode = GET_INT();
    pos += 4;
    this->config.map_cycle_mode = GET_INT();
    pos += 4;
    this->config.adjustable_alpha = data[pos];
    pos += 1;
    pos += 1;  // unused field
    this->config.dont_skip_fast_beats = data[pos] ? true : false;
    pos += 1;
    this->config.map_cycle_speed = data[pos];
    pos += 1;

    std::vector<size_t> map_lengths;
    for (size_t map_index = 0; map_index < COLORMAP_NUM_MAPS; map_index++) {
        map_lengths.push_back(this->load_map_header(data, len, map_index, pos));
        pos += COLORMAP_SAVE_MAP_HEADER_SIZE;
    }
    bool found_first_enabled_map = false;
    for (size_t map_index = 0; map_index < COLORMAP_NUM_MAPS; map_index++) {
        if (!this->load_map_colors(data, len, pos, map_index, map_lengths[map_index])) {
            break;
        }
        if (this->config.maps[map_index].enabled && !found_first_enabled_map) {
            this->config.current_map = map_index;
            found_first_enabled_map = true;
        }
        pos +=
            this->config.maps[map_index].colors.size() * COLORMAP_MAP_COLOR_CONFIG_SIZE;
    }
    if (!found_first_enabled_map) {
        this->config.current_map = 0;
    }
}

int E_ColorMap::save_legacy(unsigned char* data) {
    // memcpy(data, &this->config, COLORMAP_BASE_CONFIG_SIZE);
    int pos = 0;
    PUT_INT(this->config.color_key);
    pos += 4;
    PUT_INT(this->config.blendmode);
    pos += 4;
    PUT_INT(this->config.map_cycle_mode);
    pos += 4;
    data[pos] = (uint8_t)CLAMP(this->config.adjustable_alpha, 0, UINT8_MAX);
    pos += 1;
    data[pos] = 0;  // unused field
    pos += 1;
    data[pos] = this->config.dont_skip_fast_beats;
    pos += 1;
    data[pos] = CLAMP(this->config.map_cycle_speed, 0, UINT8_MAX);
    pos += 1;

    for (size_t map_index = 0; map_index < COLORMAP_NUM_MAPS; map_index++) {
        PUT_INT(this->config.maps[map_index].enabled);
        pos += 4;
        uint32_t tmp_size = this->config.maps[map_index].colors.size();
        PUT_INT(CLAMPU(tmp_size, UINT32_MAX));
        pos += 4;
        PUT_INT(this->config.maps[map_index].map_id);
        pos += 4;
        memset((char*)&data[pos], 0, COLORMAP_MAP_FILENAME_MAXLEN);
        auto filenamepos = this->config.maps[map_index].filepath.rfind('\\');
        if (filenamepos == std::string::npos) {
            filenamepos = 0;
        }
        auto filename = this->config.maps[map_index].filepath.substr(filenamepos);
        strncpy((char*)&data[pos], filename.c_str(), COLORMAP_MAP_FILENAME_MAXLEN - 1);
        pos += COLORMAP_MAP_FILENAME_MAXLEN;
    }
    for (size_t map_index = 0; map_index < COLORMAP_NUM_MAPS; map_index++) {
        for (unsigned int i = 0;
             i < CLAMPU(this->config.maps[map_index].colors.size(), UINT32_MAX);
             i++) {
            PUT_INT(this->config.maps[map_index].colors[i].position);
            pos += 4;
            PUT_INT(this->config.maps[map_index].colors[i].color);
            pos += 4;
            PUT_INT(this->config.maps[map_index].colors[i].color_id);
            pos += 4;
        }
    }
    return pos;
}

Effect_Info* create_ColorMap_Info() { return new ColorMap_Info(); }
Effect* create_ColorMap(AVS_Instance* avs) {
    srand(time(NULL));
    return new E_ColorMap(avs);
}
void set_ColorMap_desc(char* desc) { E_ColorMap::set_desc(desc); }
