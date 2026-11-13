#pragma once

// NullPlayer: AVS's built-in Render / Text (legacy id 28). Upstream's library ships no
// portable Text effect (only the Win32 GDI r_text.cpp at the pinned commit), so this is a
// port of that file's behaviour onto libavs's effect framework, drawing with CoreText.

#include "vis_avs/effect.h"
#include "vis_avs/effect_common.h"
#include "vis_avs/effect_info.h"

#include "text_coretext.h"

#include <cstdint>
#include <string>

// Win32 CHOOSEFONTA and LOGFONTA as a 32-bit Winamp saved them, kept verbatim so a legacy
// save round-trips byte for byte.
#define TEXT_CHOOSEFONT_SIZE    60
#define TEXT_LOGFONT_SIZE       60
#define TEXT_LOGFONT_FACE_START 28
#define TEXT_LOGFONT_FACE_SIZE  32

struct Text_Config : public Effect_Config {
    uint64_t color = 0xffffff;
    int64_t blend_mode = BLEND_SIMPLE_REPLACE;
    bool on_beat = false;
    bool insert_blanks = false;
    bool random_position = false;
    int64_t v_align = VPOS_CENTER;
    int64_t h_align = HPOS_CENTER;
    int64_t on_beat_duration = 15;
    int64_t speed = 15;
    std::string text;
    std::string font = "Arial";
    int64_t font_size = 0;
    bool bold = false;
    bool italic = false;
    bool outline = false;
    bool shadow = false;
    uint64_t outline_color = 0;
    int64_t outline_size = 1;
    int64_t shift_x = 0;
    int64_t shift_y = 0;
    bool random_word = false;
};

struct Text_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Text";
    static constexpr char const* help =
        "Shows the words of Text, separated by ';', one at a time.\n"
        "$(regNN) or $(regNN:4.2) shows global register NN; $(title), $(playpos) and\n"
        "$(playlen) show nothing and 0:00, as Winamp's did with no song.";
    static constexpr int32_t legacy_id = 28;
    static constexpr char const* legacy_ape_id = nullptr;

    static constexpr uint32_t num_parameters = 21;
    static constexpr Parameter parameters[num_parameters] = {
        P_STRING(offsetof(Text_Config, text), "Text", "Words separated by ';'"),
        P_COLOR(offsetof(Text_Config, color), "Color"),
        P_SELECT(offsetof(Text_Config, blend_mode), "Blend Mode", blend_modes_simple),
        P_STRING(offsetof(Text_Config, font), "Font"),
        P_IRANGE(offsetof(Text_Config, font_size),
                 "Font Size",
                 0,
                 1000,
                 "Height in pixels; 0 is the default size"),
        P_BOOL(offsetof(Text_Config, bold), "Bold"),
        P_BOOL(offsetof(Text_Config, italic), "Italic"),
        P_SELECT(offsetof(Text_Config, h_align), "Horizontal Align", h_positions),
        P_SELECT(offsetof(Text_Config, v_align), "Vertical Align", v_positions),
        P_IRANGE(offsetof(Text_Config, shift_x), "Shift X", -100, 100, "Percent of width"),
        P_IRANGE(offsetof(Text_Config, shift_y), "Shift Y", -100, 100, "Percent of height"),
        P_BOOL(offsetof(Text_Config, random_position), "Random Position"),
        P_BOOL(offsetof(Text_Config, outline), "Outline"),
        P_BOOL(offsetof(Text_Config, shadow), "Shadow"),
        P_COLOR(offsetof(Text_Config, outline_color), "Outline Color"),
        P_IRANGE(offsetof(Text_Config, outline_size), "Outline Size", 1, 16),
        P_BOOL(offsetof(Text_Config, on_beat), "On Beat", "Show a word only on a beat"),
        P_IRANGE(offsetof(Text_Config, on_beat_duration),
                 "On-Beat Duration",
                 0,
                 400,
                 "Frames a word stays after a beat"),
        P_IRANGE(offsetof(Text_Config, speed), "Speed", 0, 400, "Frames per word"),
        P_BOOL(offsetof(Text_Config, insert_blanks), "Insert Blanks"),
        P_BOOL(offsetof(Text_Config, random_word), "Random Word"),
    };

    EFFECT_INFO_GETTERS;
};

class E_Text : public Configurable_Effect<Text_Info, Text_Config> {
   public:
    E_Text(AVS_Instance* avs);
    virtual ~E_Text();
    E_Text(const E_Text& other);
    E_Text& operator=(const E_Text&) = delete;
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Text* clone() { return new E_Text(*this); }

   private:
    std::string word(int n) const;
    AvsTextFont font() const;
    bool draw_word(const std::string& word, int w, int h);

    uint8_t choosefont[TEXT_CHOOSEFONT_SIZE];
    uint8_t logfont[TEXT_LOGFONT_SIZE];

    int current_word = 0;
    int frames = 0;           // frames the current word has shown (timed mode)
    int beat_frames = 0;      // frames left of the current beat (on-beat mode)
    int odd_even = 0;         // alternates word / blank with Insert Blanks
    bool random_placed = false;
    int random_x = 0;
    int random_y = 0;

    uint32_t* buffer = nullptr;  // the word drawn over clip_color, w*h
    int buffer_w = 0;
    int buffer_h = 0;
    uint32_t clip_color = 0;
    std::string drawn_key;
};
