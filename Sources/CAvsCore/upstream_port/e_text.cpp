// NullPlayer: AVS Render / Text on CoreText. Behaviour follows upstream's Win32 r_text.cpp
// (BSD, Nullsoft): the word timing, beat and blank logic, the clip-colour buffer, the
// outline and shadow passes and the legacy layout; GDI's DrawText becomes CoreText (text_coretext.cpp).

#include "e_text.h"

#include "text_coretext.h"
#include "util.h"
#include "vis_avs/avs_eelif.h"
#include "vis_avs/blend.h"

#include <strings.h>

#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

constexpr Parameter Text_Info::parameters[];

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

#define PUT_INT(y)                     \
    data[pos] = (y) & 255;             \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

namespace {
// GDI DrawText alignment flags, as the legacy format stores them.
constexpr int DT_LEFT = 0, DT_CENTER = 1, DT_RIGHT = 2;
constexpr int DT_TOP = 0, DT_VCENTER = 4, DT_BOTTOM = 8;
constexpr int NONANTIALIASED_QUALITY = 3;
constexpr int FW_BOLD_FROM = 600;  // GDI draws lfWeight >= FW_SEMIBOLD as bold

int32_t get_i32(const uint8_t* p) {
    return (int32_t)(p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24));
}

void put_i32(uint8_t* p, int32_t v) {
    for (int i = 0; i < 4; i++) {
        p[i] = (v >> (8 * i)) & 0xFF;
    }
}

int h_align_to_dt(int64_t a) { return a == HPOS_LEFT ? DT_LEFT : a == HPOS_RIGHT ? DT_RIGHT : DT_CENTER; }
int v_align_to_dt(int64_t a) { return a == VPOS_TOP ? DT_TOP : a == VPOS_BOTTOM ? DT_BOTTOM : DT_VCENTER; }
int64_t dt_to_h_align(int dt) { return dt == DT_LEFT ? HPOS_LEFT : dt == DT_RIGHT ? HPOS_RIGHT : HPOS_CENTER; }
int64_t dt_to_v_align(int dt) { return dt == DT_TOP ? VPOS_TOP : dt == DT_BOTTOM ? VPOS_BOTTOM : VPOS_CENTER; }

int count_separators(const std::string& text) {
    int n = 0;
    for (char c : text) {
        n += c == ';';
    }
    return n;
}

}  // namespace

E_Text::E_Text(AVS_Instance* avs) : Configurable_Effect(avs) {
    memset(this->choosefont, 0, sizeof(this->choosefont));
    memset(this->logfont, 0, sizeof(this->logfont));
    put_i32(this->choosefont, TEXT_CHOOSEFONT_SIZE);  // lStructSize
}

E_Text::E_Text(const E_Text& other)
    : Configurable_Effect(other),
      current_word(other.current_word),
      frames(other.frames),
      beat_frames(other.beat_frames),
      odd_even(other.odd_even),
      random_placed(other.random_placed),
      random_x(other.random_x),
      random_y(other.random_y),
      clip_color(other.clip_color) {
    // The drawn-word cache (buffer, drawn_key) starts empty: the clone redraws on its first frame.
    memcpy(this->choosefont, other.choosefont, sizeof(this->choosefont));
    memcpy(this->logfont, other.logfont, sizeof(this->logfont));
}

E_Text::~E_Text() { free(this->buffer); }

// Word n of the text with its $(…) fields expanded, as r_text.cpp's getWord.
std::string E_Text::word(int n) const {
    const std::string& text = this->config.text;
    size_t p = 0;
    for (int w = 0; w < n && p < text.size(); p++) {
        w += text[p] == ';';
    }
    std::string out;
    while (p < text.size() && text[p] != ';' && out.size() < 255) {
        const char* s = text.c_str() + p;
        const char* end = nullptr;
        if ((!strncasecmp(s, "$(playpos", 9) || !strncasecmp(s, "$(playlen", 9))
            && (end = strchr(s + 9, ')'))) {
            // No Winamp frontend: the position and length read 0.
            int digits = s[9] == '.' ? min(atoi(s + 10), 3) : 0;
            out += "0:00";
            if (digits > 0) {
                out += "." + std::string(digits, '0');
            }
        } else if (!strncasecmp(s, "$(title", 7) && (end = strchr(s + 7, ')'))) {
            // No Winamp frontend: no title.
        } else if (!strncasecmp(s, "$(reg", 5) && isdigit(s[5]) && isdigit(s[6])
                   && (end = strchr(s + 7, ')'))) {
            int reg = (s[5] - '0') * 10 + (s[6] - '0');
            std::string format = "%";
            const char* f = s + 7;
            if (*f == ':') {
                for (f++; format.size() < 16 && (isdigit(*f) || *f == '.'); f++) {
                    format += *f;
                }
            }
            format += "f";
            char value[128];
            snprintf(value, sizeof(value), format.c_str(), NSEEL_getglobalregs()[reg]);
            out += value;
        } else {
            out += text[p++];
            continue;
        }
        p = end + 1 - text.c_str();
    }
    return out.substr(0, 255);
}

// The font the parameters and the saved LOGFONT describe. Font Size keeps the saved
// lfHeight's sign: an em height when negative, a cell height when positive.
AvsTextFont E_Text::font() const {
    int32_t lf_height = get_i32(this->logfont);
    auto size = (int32_t)this->config.font_size;
    return {this->config.font.c_str(),
            lf_height > 0 ? size : -size,
            this->config.bold,
            this->config.italic,
            this->logfont[26] != NONANTIALIASED_QUALITY};
}

// Redraws the buffer when anything it shows changed. Returns false when no buffer exists.
bool E_Text::draw_word(const std::string& word, int w, int h) {
    int h_align = this->random_placed ? DT_LEFT : h_align_to_dt(this->config.h_align);
    int v_align = this->random_placed ? DT_TOP : v_align_to_dt(this->config.v_align);
    int shift_x = this->random_placed ? this->random_x : (int)this->config.shift_x;
    int shift_y = this->random_placed ? this->random_y : (int)this->config.shift_y;
    char key[512];
    snprintf(key,
             sizeof(key),
             "%dx%d %d %d %d %d %06llx %06llx %d %d %lld %s %lld %d %d %d %d|",
             w,
             h,
             h_align,
             v_align,
             shift_x,
             shift_y,
             (unsigned long long)this->config.color,
             (unsigned long long)this->config.outline_color,
             this->config.outline,
             this->config.shadow,
             (long long)this->config.outline_size,
             this->config.font.c_str(),
             (long long)this->config.font_size,
             this->config.bold,
             this->config.italic,
             (int)this->logfont[26],
             (int)this->clip_color);
    std::string full_key = key + word;
    if (this->buffer && full_key == this->drawn_key) {
        return true;
    }
    if (!this->buffer || this->buffer_w != w || this->buffer_h != h) {
        free(this->buffer);
        this->buffer = (uint32_t*)malloc((size_t)w * h * sizeof(uint32_t));
        if (!this->buffer) {
            return false;
        }
        this->buffer_w = w;
        this->buffer_h = h;
    }
    this->drawn_key = full_key;
    for (int i = 0; i < w * h; i++) {
        this->buffer[i] = this->clip_color;
    }
    if (word.empty()) {
        return true;
    }

    AvsTextFont font = this->font();
    AvsTextMetrics line = avs_text_measure(font, word.c_str());
    // DrawText(DT_SINGLELINE | DT_NOCLIP) in the screen rectangle shifted by percent.
    double left = (int)((float)shift_x * (float)w / 100.0F);
    double top = (int)((float)shift_y * (float)h / 100.0F);
    double height = line.ascent + line.descent;
    double x = h_align == DT_LEFT    ? left
               : h_align == DT_RIGHT ? left + w - line.width
                                     : left + (w - line.width) / 2;
    double y = v_align == DT_TOP      ? top
               : v_align == DT_BOTTOM ? top + h - height
                                      : top + (h - height) / 2;
    auto draw_at = [&](int dx, int dy, uint64_t color) {
        avs_text_draw(this->buffer, w, h, font, word.c_str(), x + dx, y + dy, (uint32_t)color);
    };
    int s = (int)this->config.outline_size;
    if (this->config.outline) {
        const int ring[8][2] = {{-1, -1}, {0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}};
        for (auto& o : ring) {
            draw_at(o[0] * s, o[1] * s, this->config.outline_color);
        }
    } else if (this->config.shadow) {
        draw_at(s, s, this->config.outline_color);
    }
    draw_at(0, 0, this->config.color);
    for (int i = 0; i < w * h; i++) {
        this->buffer[i] &= 0xFFFFFF;
    }
    return true;
}

int E_Text::render(char[2][2][576], int is_beat, int* framebuffer, int*, int w, int h) {
    if (is_beat & 0x80000000) {
        return 0;
    }
    int words = count_separators(this->config.text) + 1;
    bool on_beat = this->config.on_beat;
    bool timed_out = !on_beat && this->frames >= this->config.speed;
    bool beat_starts = on_beat && is_beat && !this->beat_frames;
    if (timed_out || beat_starts) {
        if (!(this->config.insert_blanks && !(this->odd_even % 2))) {
            this->current_word = this->config.random_word
                                     ? rand() % words
                                     : (this->current_word + 1) % words;
        }
        this->odd_even = (this->odd_even + 1) % 2;
    }
    if (beat_starts) {
        this->beat_frames = (int)this->config.on_beat_duration;
    }
    std::string shown = this->word(this->current_word);
    if (this->config.insert_blanks && !this->odd_even) {
        shown.clear();
    }

    uint32_t color = this->config.color & 0xFFFFFF;
    uint32_t outline_color = this->config.outline_color & 0xFFFFFF;
    for (uint32_t candidate : {0u, 8u, 10u}) {
        if (candidate != color && candidate != outline_color) {
            this->clip_color = candidate;
            break;
        }
    }

    if (timed_out
        || (on_beat && is_beat && this->beat_frames == this->config.on_beat_duration)) {
        this->frames = 0;
        this->random_placed = this->config.random_position && w && h;
        if (this->random_placed) {
            // Keep the word on screen: a random top-left within what it leaves free.
            AvsTextMetrics line = avs_text_measure(this->font(), shown.c_str());
            int range_x = (int)(((float)(w - line.width) / (float)w) * 100.0F);
            int range_y = (int)(((float)(h - (line.ascent + line.descent)) / (float)h) * 100.0F);
            this->random_x = range_x > 0 ? rand() % range_x : 0;
            this->random_y = range_y > 0 ? rand() % range_y : 0;
        }
    }

    bool visible = !(on_beat && !this->beat_frames);
    if (visible && this->draw_word(shown, w, h)) {
        auto* out = (uint32_t*)framebuffer;
        for (int i = 0; i < w * h; i++) {
            uint32_t px = this->buffer[i];
            if (px == this->clip_color) {
                continue;
            }
            switch (this->config.blend_mode) {
                case BLEND_SIMPLE_ADDITIVE: blend_add_1px(&px, &out[i], &out[i]); break;
                case BLEND_SIMPLE_5050: blend_5050_1px(&px, &out[i], &out[i]); break;
                default: out[i] = px; break;
            }
        }
    }

    if (!on_beat) {
        this->frames++;
    }
    if (on_beat && this->beat_frames) {
        this->beat_frames--;
    }
    return 0;
}

void E_Text::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    int32_t blend = 0, blend_avg = 0;
    auto next = [&](int32_t fallback) {
        if (len - pos < 4) {
            return fallback;
        }
        int32_t v = GET_INT();
        pos += 4;
        return v;
    };
    this->enabled = next(1);
    this->config.color = (uint32_t)next(0xFFFFFF);
    blend = next(0);
    blend_avg = next(0);
    this->config.blend_mode = blend       ? BLEND_SIMPLE_ADDITIVE
                              : blend_avg ? BLEND_SIMPLE_5050
                                          : BLEND_SIMPLE_REPLACE;
    this->config.on_beat = next(0);
    this->config.insert_blanks = next(0);
    this->config.random_position = next(0);
    this->config.v_align = dt_to_v_align(next(DT_VCENTER));
    this->config.h_align = dt_to_h_align(next(DT_CENTER));
    this->config.on_beat_duration = next(15);
    this->config.speed = next(15);
    if (len - pos >= TEXT_CHOOSEFONT_SIZE) {
        memcpy(this->choosefont, data + pos, TEXT_CHOOSEFONT_SIZE);
        pos += TEXT_CHOOSEFONT_SIZE;
    }
    if (len - pos >= TEXT_LOGFONT_SIZE) {
        memcpy(this->logfont, data + pos, TEXT_LOGFONT_SIZE);
        pos += TEXT_LOGFONT_SIZE;
    }
    const char* face = (const char*)this->logfont + TEXT_LOGFONT_FACE_START;
    this->config.font = std::string(face, strnlen(face, TEXT_LOGFONT_FACE_SIZE));
    int32_t lf_height = get_i32(this->logfont);
    this->config.font_size = lf_height < 0 ? -(int64_t)lf_height : lf_height;
    this->config.bold = get_i32(this->logfont + 16) >= FW_BOLD_FROM;
    this->config.italic = this->logfont[20] != 0;
    int32_t size = next(0);
    this->config.text.clear();
    if (size > 0 && len - pos >= size) {
        this->config.text = std::string((const char*)data + pos, strnlen((const char*)data + pos, size));
        pos += size;
    }
    this->config.outline = next(0);
    this->config.outline_color = (uint32_t)next(0);
    this->config.shift_x = next(0);
    this->config.shift_y = next(0);
    this->config.outline_size = next(1);
    this->config.random_word = next(0);
    this->config.shadow = next(0);
    this->random_placed = false;
    this->drawn_key.clear();
}

int E_Text::save_legacy(unsigned char* data) {
    // Carry the font parameters back into the saved LOGFONT, touching only fields that
    // changed so an unedited preset saves the bytes it loaded.
    int32_t lf_height = get_i32(this->logfont);
    if ((lf_height < 0 ? -(int64_t)lf_height : lf_height) != this->config.font_size) {
        put_i32(this->logfont,
                lf_height > 0 ? (int32_t)this->config.font_size
                              : -(int32_t)this->config.font_size);
    }
    if ((get_i32(this->logfont + 16) >= FW_BOLD_FROM) != this->config.bold) {
        put_i32(this->logfont + 16, this->config.bold ? 700 : 400);
    }
    if ((this->logfont[20] != 0) != this->config.italic) {
        this->logfont[20] = this->config.italic;
    }
    char* face = (char*)this->logfont + TEXT_LOGFONT_FACE_START;
    if (this->config.font != std::string(face, strnlen(face, TEXT_LOGFONT_FACE_SIZE))) {
        memset(face, 0, TEXT_LOGFONT_FACE_SIZE);
        memcpy(face,
               this->config.font.data(),
               min(this->config.font.size(), (size_t)TEXT_LOGFONT_FACE_SIZE - 1));
    }

    int pos = 0;
    auto put = [&](int32_t v) {
        PUT_INT(v);
        pos += 4;
    };
    put(this->enabled);
    put((int32_t)this->config.color);
    put(this->config.blend_mode == BLEND_SIMPLE_ADDITIVE);
    put(this->config.blend_mode == BLEND_SIMPLE_5050);
    put(this->config.on_beat);
    put(this->config.insert_blanks);
    put(this->config.random_position);
    put(v_align_to_dt(this->config.v_align));
    put(h_align_to_dt(this->config.h_align));
    put((int32_t)this->config.on_beat_duration);
    put((int32_t)this->config.speed);
    memcpy(data + pos, this->choosefont, TEXT_CHOOSEFONT_SIZE);
    pos += TEXT_CHOOSEFONT_SIZE;
    memcpy(data + pos, this->logfont, TEXT_LOGFONT_SIZE);
    pos += TEXT_LOGFONT_SIZE;
    if (this->config.text.empty()) {
        put(0);
    } else {
        int32_t size = (int32_t)this->config.text.size() + 1;
        put(size);
        memcpy(data + pos, this->config.text.c_str(), size);
        pos += size;
    }
    put(this->config.outline);
    put((int32_t)this->config.outline_color);
    put((int32_t)this->config.shift_x);
    put((int32_t)this->config.shift_y);
    put((int32_t)this->config.outline_size);
    put(this->config.random_word);
    put(this->config.shadow);
    return pos;
}

Effect_Info* create_Text_Info() { return new Text_Info(); }
Effect* create_Text(AVS_Instance* avs) { return new E_Text(avs); }
void set_Text_desc(char* desc) { E_Text::set_desc(desc); }
