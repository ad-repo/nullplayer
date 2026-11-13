#pragma once

// NullPlayer: the CoreText half of the Text effect (e_text.cpp). A separate translation
// unit because CoreText's Mach headers clash with libavs's platform.h typedefs.

#include <cstdint>

struct AvsTextFont {
    const char* face;  // Windows-1252, as the legacy LOGFONT stores it
    int32_t lf_height;  // LOGFONT semantics: < 0 em height, > 0 cell height, 0 default
    bool bold;
    bool italic;
    bool antialias;
};

struct AvsTextMetrics {
    double width;
    double ascent;
    double descent;
};

// One copy of the line, offset from its position, in `rgb` (0x00RRGGBB).
struct AvsTextPass {
    int dx;
    int dy;
    uint32_t rgb;
};

// One line of Windows-1252 or UTF-8 text in a font, built once to measure and draw.
class AvsTextLine {
   public:
    AvsTextLine(const AvsTextFont& font, const char* text);
    ~AvsTextLine();
    AvsTextLine(const AvsTextLine&) = delete;
    AvsTextLine& operator=(const AvsTextLine&) = delete;

    // The line's typographic size; zero when the text could not be read.
    const AvsTextMetrics& metrics() const { return this->metrics_; }

    // Draws the line once per pass, in order, into a w*h 0x00RRGGBB buffer (row 0 on top),
    // with the top of its line box at (x, top).
    void draw(uint32_t* buffer,
              int w,
              int h,
              double x,
              double top,
              const AvsTextPass* passes,
              int pass_count) const;

   private:
    const void* line_ = nullptr;  // CTLineRef
    AvsTextMetrics metrics_ = {0, 0, 0};
    bool antialias_;
};
