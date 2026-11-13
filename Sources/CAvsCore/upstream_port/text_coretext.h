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

// The typographic size of one line of Windows-1252 `text`.
AvsTextMetrics avs_text_measure(const AvsTextFont& font, const char* text);

// Draws `text` into a w*h 0x00RRGGBB buffer (row 0 on top) with the top of its line box at
// (x, top), in `rgb`.
void avs_text_draw(uint32_t* buffer,
                   int w,
                   int h,
                   const AvsTextFont& font,
                   const char* text,
                   double x,
                   double top,
                   uint32_t rgb);
