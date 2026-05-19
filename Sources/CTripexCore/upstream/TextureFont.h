#pragma once

#include "Renderer.h"
#include "Texture.h"
#include "ColorRgb.h"
#include <memory>

class TextureFont
{
public:
	static const int TF_FADE_IN_START = 8;
	static const int TF_FADE_IN_FINISH = 0; // default
	static const int TF_FADE_OUT_START = 0; // default
	static const int TF_FADE_OUT_FINISH = 16;

	static const int LETTER_APPEAR_FRAMES = 200;
	static const int LETTER_DIFF_FRAMES = 10;

	int width, height;

	struct Glyph
	{
		char character = 0;
		int start = 0;
		int end = 0;
		int bitmap_x = 0;
		int bitmap_y = 0;
		std::unique_ptr<uint8[]> data;
	};

	std::vector<Glyph> glyphs;
	std::shared_ptr<Texture> texture;
	std::unique_ptr<ColorRgb[]> pixels;
	uint8 char_to_glyph[256];

	bool LineAboveThreshold(BYTE *data);

	TextureFont();
	~TextureFont();
	void Add(const uint8 *source_data);
	Error* Create(Renderer& renderer);
	ColorRgb *GetBitmap();
	Glyph* FindGlyph(char character);
	const Glyph* FindGlyph(char character) const;
	int GetWidth(char c) const;
	int GetWidth(const char *text) const;
	void Draw(GeometryBuffer& geom, const Glyph &glyph, const Point<int> &p, ColorRgb c) const;
	void Draw(GeometryBuffer& geom, const char* text, Point<int> p, ColorRgb c, int frame_in, int frame_out, int frame, int flags = 0) const;
	void Draw(GeometryBuffer& geom, const char *text, const Point<int> &p, ColorRgb c = ColorRgb::White(), int flags = 0) const;
};

