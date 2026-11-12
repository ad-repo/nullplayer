/* Libvisual-plugins - Standard plugins for libvisual
 *
 * Copyright (C) 2000, 2001 Richard Ashburn <richard.asbury@btinternet.com>
 *
 * Authors: Richard Ashburn <richard.asbury@btinternet.com>
 * 	    Jean-Christophe Hoelt <jeko@ios-software.com>
 *	    Dennis Smit <ds@nerds-incorporated.org>
 *
 * Adapted for NullPlayer (2026-11-12) from libvisual's actor_corona.cpp: its per-frame sequence,
 * behind a C ABI with no libvisual dependency, with the palettes held by the host.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */

#include "CoronaCore.h"

#include <cstdlib>
#include <cstring>

#include "corona.h"
#include "palette.h"

// libvisual's actor_corona.cpp carries 23 of these; autopal.h, in the same source, has all 31
// and corrects two checkpoint counts (blue and white lines).
static const int PALETTEDATA[][NB_PALETTES] = {
#include "autopal.h"
};

// Names 0-22 are libvisual's comments; it names none of 23-30, so those describe the colours.
static const char *const paletteNames[] = {
	"Fire", "Ice", "White", "White to Blue", "Gray to Blue", "Yellow to Blue", "White to Red",
	"Blue to Red", "Red to Blue", "Blue to White", "White to Black", "Blue to Black",
	"Red to Black", "Blue Lines on Black", "White Lines on Black", "Night Sky", "Pink to Blue",
	"Black on White", "Black to White on White", "Heavenly Blue", "Blue, Red Line",
	"Twilight Yellow", "Clouds", "Tan and Blue", "Gold Glints", "Pastel Rainbow", "Slate",
	"Autumn", "Sepia", "Black to Pink on White", "Gray to Dark Red on White",
};
static constexpr int paletteCount = sizeof(PALETTEDATA) / sizeof(*PALETTEDATA);
static_assert(paletteCount == CORONA_CORE_PALETTE_COUNT, "the header's count is the table's");
static_assert(sizeof(paletteNames) / sizeof(*paletteNames) == paletteCount, "one name per palette");

struct CoronaCore {
	Corona corona;
	PaletteCycler palette{PALETTEDATA, paletteCount};
	TimedLevel level;
	uint32_t *rgba;
	int size;
};

CoronaCore *CoronaCore_create(int width, int height) {
	if (width < 32 || height < 32) return nullptr;
	CoronaCore *core = new CoronaCore();
	core->level.state = normal_state;
	core->size = width * height;
	core->rgba = (uint32_t *)malloc(sizeof(uint32_t) * core->size);
	if (core->rgba == nullptr || !core->corona.setUpSurface(width, height)) {
		CoronaCore_destroy(core);
		return nullptr;
	}
	return core;
}

void CoronaCore_destroy(CoronaCore *core) {
	if (core == nullptr) return;
	free(core->rgba);
	delete core;
}

const uint32_t *CoronaCore_update(CoronaCore *core, const uint8_t *spectrum, unsigned elapsedMs) {
	memcpy(core->level.frequency[0], spectrum, 512);
	memcpy(core->level.frequency[1], spectrum, 512);
	core->level.timeStamp += elapsedMs;
	core->corona.update(&core->level);
	core->palette.update(&core->level);

	const Palette &pal = core->palette.getPalette();
	uint32_t lut[256];
	for (int i = 0; i < 256; ++i) {
		const uint8_t bytes[4] = {pal[i].rgbRed, pal[i].rgbGreen, pal[i].rgbBlue, 255};
		memcpy(&lut[i], bytes, 4);
	}
	const unsigned char *index = core->corona.getSurface();
	for (int i = 0; i < core->size; ++i) core->rgba[i] = lut[index[i]];
	return core->rgba;
}

void CoronaCore_setPalette(CoronaCore *core, int index, int fade) {
	if (index >= 0 && index < paletteCount) core->palette.holdPalette(index, fade != 0);
}

const char *CoronaCore_paletteName(int index) {
	return (index >= 0 && index < paletteCount) ? paletteNames[index] : "";
}

void CoronaCore_setBlaze(CoronaCore *core, int blaze) {
	core->corona.setPreset(blaze ? PRESET_BLAZE : PRESET_CORONA);
}
