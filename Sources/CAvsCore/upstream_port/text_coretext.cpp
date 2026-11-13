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

}  // namespace

AvsTextLine::AvsTextLine(const AvsTextFont& spec, const char* text) : antialias_(spec.antialias) {
    CFStringRef string = cf_string(text);
    if (!string) {
        return;
    }
    CTFontRef font = make_font(spec);
    // The line's colour comes from the context's fill, so each pass sets its own.
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
    this->metrics_.width = CTLineGetTypographicBounds(line, &ascent, &descent, nullptr);
    this->metrics_.ascent = ascent;
    this->metrics_.descent = descent;
    this->line_ = line;
    CFRelease(attributed);
    CFRelease(attributes);
    CFRelease(font);
    CFRelease(string);
}

AvsTextLine::~AvsTextLine() {
    if (this->line_) {
        CFRelease(this->line_);
    }
}

void AvsTextLine::draw(uint32_t* buffer,
                       int w,
                       int h,
                       double x,
                       double top,
                       const AvsTextPass* passes,
                       int pass_count) const {
    if (!this->line_) {
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
    if (!context) {
        return;
    }
    CGContextSetShouldAntialias(context, this->antialias_);
    CGContextSetShouldSmoothFonts(context, false);
    for (int i = 0; i < pass_count; i++) {
        uint32_t rgb = passes[i].rgb;
        CGContextSetRGBFillColor(context,
                                 ((rgb >> 16) & 0xFF) / 255.0,
                                 ((rgb >> 8) & 0xFF) / 255.0,
                                 (rgb & 0xFF) / 255.0,
                                 1.0);
        CGContextSetTextPosition(context,
                                 round(x + passes[i].dx),
                                 h - (round(top + passes[i].dy) + this->metrics_.ascent));
        CTLineDraw((CTLineRef)this->line_, context);
    }
    CGContextRelease(context);
}
