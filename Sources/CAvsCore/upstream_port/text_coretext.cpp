#include "text_coretext.h"

#include <CoreText/CoreText.h>

#include <cmath>
#include <cstring>

namespace {
// The editor and JSON presets give UTF-8; legacy presets hold Windows-1252 bytes, which are
// rarely valid UTF-8. ponytail: a 1252 string that happens to be valid UTF-8 reads as UTF-8;
// convert at the legacy load/save boundary if one turns up.
CFStringRef cf_string(const char* s) {
    auto bytes = (const UInt8*)s;
    auto length = (CFIndex)strlen(s);
    CFStringRef utf8 =
        CFStringCreateWithBytes(nullptr, bytes, length, kCFStringEncodingUTF8, false);
    return utf8 ? utf8
                : CFStringCreateWithBytes(
                      nullptr, bytes, length, kCFStringEncodingWindowsLatin1, false);
}

CTFontRef make_font(const AvsTextFont& spec) {
    CFStringRef name = cf_string(spec.face[0] ? spec.face : "Arial");
    CTFontRef font = CTFontCreateWithName(name, 16.0, nullptr);
    CFRelease(name);
    if (spec.lf_height != 0) {
        double size = std::abs((double)spec.lf_height);
        if (spec.lf_height > 0) {  // a cell height: scale so ascent + descent matches
            size *= 16.0 / (CTFontGetAscent(font) + CTFontGetDescent(font));
        }
        CTFontRef sized = CTFontCreateCopyWithAttributes(font, size, nullptr, nullptr);
        CFRelease(font);
        font = sized;
    }
    CTFontSymbolicTraits traits =
        (spec.bold ? kCTFontBoldTrait : 0) | (spec.italic ? kCTFontItalicTrait : 0);
    if (traits) {
        CTFontRef styled = CTFontCreateCopyWithSymbolicTraits(
            font, 0.0, nullptr, traits, kCTFontBoldTrait | kCTFontItalicTrait);
        if (styled) {
            CFRelease(font);
            font = styled;
        }
    }
    return font;
}

// A line in the font, its colour taken from the context's fill. Null on a bad string.
CTLineRef make_line(const AvsTextFont& spec, const char* text, AvsTextMetrics* metrics) {
    CFStringRef string = cf_string(text);
    if (!string) {
        return nullptr;
    }
    CTFontRef font = make_font(spec);
    const void* keys[] = {kCTFontAttributeName, kCTForegroundColorFromContextAttributeName};
    const void* values[] = {font, kCFBooleanTrue};
    CFDictionaryRef attributes = CFDictionaryCreate(nullptr,
                                                    keys,
                                                    values,
                                                    2,
                                                    &kCFTypeDictionaryKeyCallBacks,
                                                    &kCFTypeDictionaryValueCallBacks);
    CFAttributedStringRef attributed = CFAttributedStringCreate(nullptr, string, attributes);
    CTLineRef line = CTLineCreateWithAttributedString(attributed);
    CGFloat ascent = 0, descent = 0;
    metrics->width = CTLineGetTypographicBounds(line, &ascent, &descent, nullptr);
    metrics->ascent = ascent;
    metrics->descent = descent;
    CFRelease(attributed);
    CFRelease(attributes);
    CFRelease(font);
    CFRelease(string);
    return line;
}
}  // namespace

AvsTextMetrics avs_text_measure(const AvsTextFont& font, const char* text) {
    AvsTextMetrics metrics = {0, 0, 0};
    if (CTLineRef line = make_line(font, text, &metrics)) {
        CFRelease(line);
    }
    return metrics;
}

void avs_text_draw(uint32_t* buffer,
                   int w,
                   int h,
                   const AvsTextFont& font,
                   const char* text,
                   double x,
                   double top,
                   uint32_t rgb) {
    AvsTextMetrics metrics;
    CTLineRef line = make_line(font, text, &metrics);
    if (!line) {
        return;
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    // Little-endian BGRX: a pixel reads as 0x00RRGGBB, AVS's layout, with row 0 on top.
    CGContextRef context = CGBitmapContextCreate(
        buffer,
        w,
        h,
        8,
        (size_t)w * 4,
        space,
        (CGBitmapInfo)kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    if (context) {
        CGContextSetShouldAntialias(context, font.antialias);
        CGContextSetShouldSmoothFonts(context, false);
        CGContextSetRGBFillColor(context,
                                 ((rgb >> 16) & 0xFF) / 255.0,
                                 ((rgb >> 8) & 0xFF) / 255.0,
                                 (rgb & 0xFF) / 255.0,
                                 1.0);
        CGContextSetTextPosition(context, round(x), h - (round(top) + metrics.ascent));
        CTLineDraw(line, context);
        CGContextRelease(context);
    }
    CFRelease(line);
}
