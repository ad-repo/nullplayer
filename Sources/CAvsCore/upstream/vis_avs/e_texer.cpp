#include "e_texer.h"

#include "blend.h"
#include "files.h"
#include "image.h"
#include "instance.h"
#include "pixel_format.h"

#include "../util.h"  // ssizeof32()

#include <emmintrin.h>  // SSE2 SIMD intrinsics

// IMAGE_DATA_ROW_EXPAND depends on the stepping of the SIMD-enabled render method.
// Currently 4 pixels are processed at once, so we are at most 3 pixels outside of the
// image. In the future this might be (8 - 1) if the method is upgraded to use 256-bit
// registers and instructions.
#define IMAGE_DATA_ROW_EXPAND (4 - 1)

constexpr Parameter Texer_Info::parameters[];
int E_Texer::instance_count = 0;
std::vector<std::string> E_Texer::filenames;
const char** E_Texer::c_filenames;

void Texer_Info::on_file_change(Effect* component,
                                const Parameter*,
                                const std::vector<int64_t>&) {
    E_Texer* texer = (E_Texer*)component;
    texer->load_image();
}

const char* const* Texer_Info::image_files(int64_t* length_out) {
    *length_out = E_Texer::filenames.size();
    auto new_list = (const char**)malloc(E_Texer::filenames.size() * sizeof(char*));
    for (size_t i = 0; i < E_Texer::filenames.size(); i++) {
        new_list[i] = E_Texer::filenames[i].c_str();
    }
    auto old_list = E_Texer::c_filenames;
    E_Texer::c_filenames = new_list;
    free(old_list);
    return E_Texer::c_filenames;
}

E_Texer::E_Texer(AVS_Instance* avs)
    : Configurable_Effect(avs), image_data(NULL), image_lock(lock_init()) {
    this->instance_count++;
    this->find_image_files();
}

E_Texer::~E_Texer() {
    this->instance_count--;
    if (this->instance_count <= 0) {
        this->clear_image_files();
    }
    lock_destroy(this->image_lock);
}

static void add_file_callback(const char* file, void* data) {
    ((E_Texer*)data)->filenames.push_back(file);
}

void E_Texer::find_image_files() {
    this->clear_image_files();
    this->filenames.push_back("(default image)");
    const int num_extensions = 5;
    char* extensions[num_extensions] = {".bmp", ".png", ".jpg", ".jpeg", ".gif"};
    find_files_by_extensions(this->avs->base_path.c_str(),
                             extensions,
                             num_extensions,
                             add_file_callback,
                             this,
                             sizeof(*this),
                             /*recursive*/ false,
                             /*background*/ false);
}

void E_Texer::clear_image_files() { this->filenames.clear(); }

bool E_Texer::load_image() {
    if (this->config.image.empty()) {
        return true;
    }
    char filename[MAX_PATH];
    int printed = snprintf(filename,
                           MAX_PATH,
                           "%s/%s",
                           this->avs->base_path.c_str(),
                           this->config.image.c_str());
    if (printed >= MAX_PATH) {
        filename[MAX_PATH - 1] = '\0';
    }
    AVS_Image* tmp_image = image_load(filename);
    if (tmp_image->data == NULL || tmp_image->w == 0 || tmp_image->h == 0
        || tmp_image->error != NULL) {
        image_free(tmp_image);
        return false;
    }

    lock_lock(this->image_lock);
    this->image_data_width = tmp_image->w + IMAGE_DATA_ROW_EXPAND * 2;
    this->image_width = tmp_image->w;
    this->image_width_half = this->image_width / 2;
    this->image_width_other_half = this->image_width - this->image_width_half;
    this->image_height = tmp_image->h;
    this->image_height_half = this->image_height / 2;
    this->image_height_other_half = this->image_height - this->image_height_half;

    delete[] this->image_data;
    this->image_data = new pixel_rgb0_8[this->image_data_width * this->image_height];
    if (this->image_data == NULL) {
        lock_unlock(this->image_lock);
        return false;
    }
    for (int y = 0; y < this->image_height; y++) {
        int x = 0;
        // Prepend each row by black pixels, so that we can render 4 pixels at once and
        // not worry about overshooting the right framebuffer edge.
        // This only works because Texer only does additive blend. With any other
        // blendmode, should it be supported in the future, this would no longer work.
        for (; x < IMAGE_DATA_ROW_EXPAND; x++) {
            this->image_data[x + y * this->image_data_width] = 0;
        }
        for (; x < this->image_width + IMAGE_DATA_ROW_EXPAND; x++) {
            this->image_data[x + y * this->image_data_width] =
                ((pixel_rgb0_8*)
                     tmp_image->data)[x - IMAGE_DATA_ROW_EXPAND + y * tmp_image->w];
        }
        // Expand each row by black pixels, so that we can render 4 pixels at once and
        // don't need to worry about overshooting the image width.
        for (; x < this->image_data_width; x++) {
            this->image_data[x + y * this->image_data_width] = 0;
        }
        // By always blindly adding 3 pixels we waste a bit of memory at the cost of
        // cleaner code.
    }
    lock_unlock(this->image_lock);
    image_free(tmp_image);

    return true;
}

int E_Texer::render(char[2][2][576], int, int* framebuffer, int* fbout, int w, int h) {
    if (this->image_data == NULL) {
        return 0;
    }
    if (this->config.add_to_input) {
        memcpy(fbout, framebuffer, w * h * sizeof(uint32_t));
    } else {
        memset(fbout, 0, w * h * sizeof(uint32_t));
    }
    lock_lock(this->image_lock);
    int p = 0;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            if ((framebuffer[x + y * w] & AVS_PIXEL_COLOR_MASK_RGB0_8) != 0) {
                this->render_particle_sse2(framebuffer, fbout, x, y, w, h);
                p++;
                if (p >= this->config.num_particles) {
                    lock_unlock(this->image_lock);
                    return 1;
                }
            }
        }
    }
    lock_unlock(this->image_lock);
    return 1;
}

inline void E_Texer::render_particle(int* framebuffer,
                                     int* fbout,
                                     int x,
                                     int y,
                                     int w,
                                     int h) {
    int fb_start_x = x - this->image_width_half;
    int fb_start_y = y - this->image_height_half;
    int fb_end_x = x + this->image_width_other_half;
    int fb_end_y = y + this->image_height_other_half;
    int image_start_x = -min(0, fb_start_x);
    int image_start_y = -min(0, fb_start_y);
    int image_end_x = this->image_width + min(0, w - fb_end_x);
    int image_end_y = this->image_height + min(0, h - fb_end_y);
    fb_start_x = max(0, fb_start_x);
    fb_start_y = max(0, fb_start_y);
    // a sane default value, but unused
    pixel_rgb0_8 mask = AVS_PIXEL_COLOR_MASK_RGB0_8;
    if (this->config.colorize) {
        mask = framebuffer[x + y * w];
    }
    for (int iy = image_start_y, fby = fb_start_y; iy < image_end_y; iy++, fby++) {
        for (int ix = image_start_x, fbx = fb_start_x; ix < image_end_x; ix++, fbx++) {
            pixel_rgb0_8* dest_pixel = &this->image_data[ix + IMAGE_DATA_ROW_EXPAND
                                                         + iy * this->image_data_width];
            if (this->config.colorize) {
                blend_multiply_1px(&mask, dest_pixel, dest_pixel);
            }
            auto out = (uint32_t*)&fbout[fbx + fby * w];
            blend_add_1px(dest_pixel, out, out);
        }
    }
}

inline void E_Texer::render_particle_sse2(int* framebuffer,
                                          int* fbout,
                                          int x,
                                          int y,
                                          int w,
                                          int h) {
    int fb_start_x = x - this->image_width_half;
    int fb_start_y = y - this->image_height_half;
    int fb_end_x = x + this->image_width_other_half;
    int fb_end_y = y + this->image_height_other_half;
    int image_start_x = -min(0, fb_start_x) + IMAGE_DATA_ROW_EXPAND;
    int image_start_y = -min(0, fb_start_y);
    int image_end_x = this->image_width + min(0, w - fb_end_x) + IMAGE_DATA_ROW_EXPAND;
    int image_end_y = this->image_height + min(0, h - fb_end_y);
    fb_start_x = max(0, fb_start_x);
    fb_start_y = max(0, fb_start_y);
    /* Don't overshoot the framebuffer row if we start close to the right edge. This can
     * happen because we always process the texer 4 pixels at once, and might not start
     * on a multiple-by-four column index.
     *
     * To prevent that, round `fb_start_x` down to a multiple of four. The framebuffer's
     * width is required to be a multiple of four, so this guarantees that we stay
     * within bounds. Setting the least significant two bits to zero accomplishes this.
     *
     * Before that, to offset the shift in the framebuffer index, we also have to start
     * rendering the texer image 0 to 3 pixels before the actual image, depending on
     * how many pixels we rounded `fb_start_x` down by. For that, we added 3 pixels of
     * black on both sides of the image in `load_image()`. Subtracting the least
     * significant two bits of `fb_start_x` from `image_start_x` accomplishes this.
     */
    image_start_x -= fb_start_x & 0b11;
    fb_start_x &= ~0b11;
    __m128i four_source_px;
    __m128i four_dest_px;
    __m128i two_16bit_px1;
    __m128i two_16bit_px2;
    __m128i zero = _mm_setzero_si128();
    __m128i mask = _mm_set1_epi32(-1);  // unused default value
    if (this->config.colorize) {
        mask = _mm_set1_epi32(framebuffer[x + y * w]);
        mask = _mm_unpacklo_epi8(mask, zero);
        for (int iy = image_start_y, fby = fb_start_y; iy < image_end_y; iy++, fby++) {
            for (int ix = image_start_x, fbx = fb_start_x; ix < image_end_x;
                 ix += 4, fbx += 4) {
                four_source_px = _mm_loadu_si128(
                    (__m128i*)&this->image_data[ix + iy * this->image_data_width]);
                two_16bit_px1 = _mm_unpacklo_epi8(four_source_px, zero);
                two_16bit_px2 = _mm_unpackhi_epi8(four_source_px, zero);
                two_16bit_px1 = _mm_mullo_epi16(two_16bit_px1, mask);
                two_16bit_px1 = _mm_srli_epi16(two_16bit_px1, 8);
                two_16bit_px2 = _mm_mullo_epi16(two_16bit_px2, mask);
                two_16bit_px2 = _mm_srli_epi16(two_16bit_px2, 8);
                four_source_px = _mm_packus_epi16(two_16bit_px1, two_16bit_px2);
                four_dest_px = _mm_loadu_si128((__m128i*)&fbout[fbx + fby * w]);
                four_dest_px = _mm_adds_epu8(four_dest_px, four_source_px);
                _mm_store_si128((__m128i*)&fbout[fbx + fby * w], four_dest_px);
            }
        }
    } else {
        for (int iy = image_start_y, fby = fb_start_y; iy < image_end_y; iy++, fby++) {
            for (int ix = image_start_x, fbx = fb_start_x; ix < image_end_x;
                 ix += 4, fbx += 4) {
                four_source_px = _mm_loadu_si128(
                    (__m128i*)&this->image_data[ix + iy * this->image_data_width]);
                four_dest_px = _mm_loadu_si128((__m128i*)&fbout[fbx + fby * w]);
                four_dest_px = _mm_adds_epu8(four_dest_px, four_source_px);
                _mm_store_si128((__m128i*)&fbout[fbx + fby * w], four_dest_px);
            }
        }
    }
}

void E_Texer::on_load() { this->load_image(); }

/* The legacy save format has a few holes:
 *     16 bytes [unused]
 *    260 bytes image filename
 *      1 byte input/output modes
 *               - input mode in first nibble ("1" and "2" bit),
 *               - output mode in second nibble ("4" and "8" bit)
 *      3 bytes [padding]
 *      4 bytes [unused]
 */
void E_Texer::load_legacy(unsigned char* data, int len) {
    int pos = sizeof(uint32_t) * 4;
    if (len - pos >= LEGACY_SAVE_PATH_LEN) {
        this->string_nt_load_legacy(
            (char*)&data[16], this->config.image, LEGACY_SAVE_PATH_LEN);
        if (!this->config.image.empty()) {
            this->load_image();
        }
    }
    pos += LEGACY_SAVE_PATH_LEN;
    if (len - pos >= ssizeof32(uint32_t)) {
        int32_t input_output = *(uint32_t*)&data[pos];
        this->config.add_to_input = (input_output & 0b11) == 2;
        this->config.colorize = (input_output & 0b1100) == 8;
    }
    pos += sizeof(uint32_t);
    if (len - pos >= ssizeof32(uint32_t)) {
        this->config.num_particles = *(uint32_t*)&data[pos];
    }
}

int E_Texer::save_legacy(unsigned char* data) {
    int pos = 0;
    memset(data, pos, 16);  // unused
    pos += 16;
    uint32_t str_len = 0;
    if (!this->config.image.empty()) {
        str_len = string_nt_save_legacy(
            this->config.image, (char*)&data[pos], LEGACY_SAVE_PATH_LEN);
    }
    memset(&data[pos + str_len], '\0', LEGACY_SAVE_PATH_LEN - str_len);
    pos += LEGACY_SAVE_PATH_LEN;
    *(uint32_t*)&data[pos] = (uint32_t)((this->config.add_to_input ? 2 : 1)
                                        | (this->config.colorize ? 8 : 4));
    pos += sizeof(uint32_t);
    *(uint32_t*)&data[pos] = this->config.num_particles;
    pos += sizeof(uint32_t);
    memset(&data[pos], 0, sizeof(uint32_t));  // unused
    pos += sizeof(uint32_t);
    return pos;
}

Effect_Info* create_Texer_Info() { return new Texer_Info(); }
Effect* create_Texer(AVS_Instance* avs) { return new E_Texer(avs); }
void set_Texer_desc(char* desc) { E_Texer::set_desc(desc); }
