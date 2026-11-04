#include "VisClassicEffects.h"

#include <algorithm>

namespace visclassic {

void DrawContext::fillRow(int row, int x0, int x1, const RGB &c) const {
    if (row < 0 || row >= h) return;
    x0 = std::max(0, x0);
    x1 = std::min(w, x1);
    uint8_t *line = dst + static_cast<size_t>(h - 1 - row) * stride;
    for (int x = x0; x < x1; ++x) {
        line[x * 4 + 0] = c.b;
        line[x * 4 + 1] = c.g;
        line[x * 4 + 2] = c.r;
        line[x * 4 + 3] = 255;
    }
}

int DrawContext::rows(int lv) const { return std::min(h, std::max(0, lv) * h / 255); }

int DrawContext::peakRow(int pk) const { return std::min(h - 1, std::max(0, pk) * h / 255); }

uint8_t DrawContext::colourIndex(int lv, int row) const {
    return barScheme(std::clamp(lv, 0, 255), row * 255 / std::max(1, h));
}

void GhostState::reset(int bands, int barWidth) {
    ghost.assign(static_cast<size_t>(bands), 0);
    ghost2.assign(static_cast<size_t>(bands), 0);
    smoke.assign(static_cast<size_t>(bands * barWidth), 0);
    smokeMove = 1;
    waveStart = 2;
    waveDivisor = 3;
    waveOldVolume = 0;
}

namespace {

uint8_t ch(int v) { return static_cast<uint8_t>(std::clamp(v, 0, 255)); }

RGB scaled(const RGB &c, double d) {
    return RGB{ch(static_cast<int>(c.r / d)), ch(static_cast<int>(c.g / d)), ch(static_cast<int>(c.b / d))};
}

// (c * wc + bg * wbg) / div per channel: the plugin's Aux colours.
RGB blend(const RGB &c, int wc, const RGB &bg, int wbg, int div) {
    return RGB{ch((c.r * wc + bg.r * wbg) / div), ch((c.g * wc + bg.g * wbg) / div), ch((c.b * wc + bg.b * wbg) / div)};
}

// CalculateFadeShadowAuxColours: six steps from the bar colour toward the background.
RGB fadeShadowColour(const RGB &c, const RGB &bg, int step) {
    static const int kWeights[6][3] = {{1, 7, 8}, {1, 3, 4}, {3, 5, 8}, {1, 1, 2}, {5, 3, 8}, {3, 1, 4}};
    const int *k = kWeights[std::clamp(step, 0, 5)];
    return blend(c, k[0], bg, k[1], k[2]);
}

// CalculateSmokeAuxColours: four densities.
RGB smokeColour(const RGB &c, const RGB &bg, int step) {
    static const int kWeights[4][3] = {{2, 5, 7}, {3, 5, 8}, {4, 5, 9}, {1, 1, 2}};
    const int *k = kWeights[std::clamp(step, 0, 3)];
    return blend(c, k[0], bg, k[1], k[2]);
}

const RGB &barColour(const DrawContext &ctx, uint8_t idx) { return (*ctx.bars)[idx]; }

// Both of these use the bar colour table at half resolution (`colour_lookup / 2` into a 128-entry
// table built from every second bar colour).
const RGB &halfBarColour(const DrawContext &ctx, uint8_t idx) { return (*ctx.bars)[(idx / 2) * 2]; }

// Rows from the bar's top (snapped down to the Y-Spacing grid) up to the ghost's top.
template <typename ColourAt>
void ghostRows(const DrawContext &ctx, int x0, int x1, int fromLevel, int toLevel, ColourAt colourAt) {
    const int ys = ctx.ySpacing;
    for (int row = ctx.rows(fromLevel) / ys * ys; row < ctx.rows(toLevel); row += ys) {
        ctx.fillRow(row, x0, x1, colourAt(row));
    }
}

void plainBar(const DrawContext &ctx, size_t bar) {
    const int lv = ctx.level[bar];
    for (int row = 0; row < ctx.rows(lv); row += ctx.ySpacing) {
        ctx.fillRow(row, ctx.barStart[bar], ctx.barEnd[bar], barColour(ctx, ctx.colourIndex(lv, row)));
    }
}

void plainPeak(const DrawContext &ctx, size_t bar) {
    if (ctx.peak[bar] <= 0) return;
    const int row = ctx.peakRow(ctx.peak[bar]) / ctx.ySpacing * ctx.ySpacing;
    ctx.fillRow(row, ctx.barStart[bar], ctx.barEnd[bar], (*ctx.peaks)[ctx.peakColour[bar]]);
}

void drawMirror(const DrawContext &ctx) {
    const int ys = ctx.ySpacing;
    const int middle = ctx.h / 2 / ys * ys;
    for (size_t bar = 0; bar < ctx.barStart.size(); ++bar) {
        const int x0 = ctx.barStart[bar], x1 = ctx.barEnd[bar], lv = ctx.level[bar];
        for (int y = 0; y < ctx.rows(lv) / 2; y += ys) {
            const RGB &c = barColour(ctx, ctx.colourIndex(lv, y * 2));
            ctx.fillRow(middle + y, x0, x1, c);
            ctx.fillRow(middle - y, x0, x1, c);
        }
        if (ctx.peak[bar] > 0) {
            const int p = ctx.peakRow(ctx.peak[bar]) / 2 / ys * ys;
            const RGB &c = (*ctx.peaks)[ctx.peakColour[bar]];
            ctx.fillRow(middle + p, x0, x1, c);
            ctx.fillRow(middle - p, x0, x1, c);
        }
    }
}

// Reflection (RenderWideBarsDarkMirror) and Reflection Waves (RenderWideBarsWaveyReflection): bars
// stand on a line one third up, with a half-height dimmed reflection below. Waves shifts each
// reflected row sideways along a 16-step wave whose amplitude follows the volume.
void drawReflection(const DrawContext &ctx, const GhostState &g, bool waves) {
    static const int kWaves[16] = {0, 0, 1, 2, 2, 2, 2, 1, 0, 0, -1, -2, -2, -2, -2, -1};
    const int ys = ctx.ySpacing;
    const int middle = ctx.h / 3 / ys * ys;
    const double dim = waves ? 1.65 : 1.75;
    bool drawY = true;  // the plugin keeps this across bars

    const auto reflect = [&](int row, int x0, int x1, int wave, const RGB &c) {
        if (!waves) {
            ctx.fillRow(row, x0, x1, c);
            return;
        }
        const int shift = kWaves[wave] / g.waveDivisor;
        const int a = std::max(x0, 2), b = std::min(x1, ctx.w - 2);  // the plugin skips the outer columns
        if (a < b) ctx.fillRow(row, a + shift, b + shift, c);
    };

    for (size_t bar = 0; bar < ctx.barStart.size(); ++bar) {
        const int x0 = ctx.barStart[bar], x1 = ctx.barEnd[bar], lv = ctx.level[bar];
        int wave = g.waveStart;
        for (int y = 0; y < ctx.rows(lv) * 2 / 3; y += ys) {
            const RGB &c = barColour(ctx, ctx.colourIndex(lv, y * 3 / 2));
            if (!waves || y / 2 > 0) reflect((middle - y / 2) / ys * ys, x0, x1, wave, scaled(c, dim));
            if (waves) {
                // y is halved below, so the wave steps every second row to show whole waves.
                drawY = !drawY;
                if (drawY) wave = (wave + 1) % 16;
            }
            ctx.fillRow(middle + y, x0, x1, c);
        }
        if (ctx.peak[bar] > 0) {
            const RGB &c = (*ctx.peaks)[ctx.peakColour[bar]];
            // *2/6 rather than /3, so rounding never puts the reflected peak inside its bar.
            reflect((middle - ctx.rows(ctx.peak[bar]) * 2 / 6) / ys * ys, x0, x1,
                    (ctx.peak[bar] / 6 + g.waveStart) % 16, scaled(c, dim));
            ctx.fillRow(middle + (ctx.peakRow(ctx.peak[bar]) * 2 / 3) / ys * ys, x0, x1, c);
        }
    }
}

void drawSmoke(const DrawContext &ctx, const GhostState &g) {
    const RGB &bg = (*ctx.volumes)[0];
    const int bw = ctx.barWidth;
    for (size_t bar = 0; bar < ctx.barStart.size(); ++bar) {
        const int x0 = ctx.barStart[bar], span = ctx.barEnd[bar] - x0;
        // The plugin's smoke columns are the bar's Bar Width pixel columns; here, equal slices of
        // the bar as drawn, so a box of any size shows the same smoke.
        for (int s = 0; s < bw; ++s) {
            const size_t col = bar * static_cast<size_t>(bw) + static_cast<size_t>(s);
            if (col >= g.smoke.size()) break;
            const int sm = g.smoke[col];
            ghostRows(ctx, x0 + span * s / bw, x0 + span * (s + 1) / bw, ctx.level[bar], sm, [&](int row) {
                return smokeColour(halfBarColour(ctx, ctx.colourIndex(sm, row)), bg, sm / 72);
            });
        }
    }
    for (size_t bar = 0; bar < ctx.barStart.size(); ++bar) {
        plainBar(ctx, bar);
        plainPeak(ctx, bar);
    }
}

// None, Shadow, Double Shadow and Fade Shadow: ghosts behind an upright bar.
void drawUpright(const DrawContext &ctx, int effect, const GhostState &g) {
    const RGB &bg = (*ctx.volumes)[0];
    for (size_t bar = 0; bar < ctx.barStart.size(); ++bar) {
        const int x0 = ctx.barStart[bar], x1 = ctx.barEnd[bar], lv = ctx.level[bar];
        switch (effect) {
        case kEffectShadow: {
            const int gh = g.ghost[bar];
            ghostRows(ctx, x0, x1, lv, gh, [&](int row) { return blend(barColour(ctx, ctx.colourIndex(gh, row)), 1, bg, 1, 2); });
            break;
        }
        case kEffectDoubleShadow: {
            const int outer = g.ghost[bar], inner = g.ghost2[bar];
            ghostRows(ctx, x0, x1, inner, outer, [&](int row) { return blend(barColour(ctx, ctx.colourIndex(outer, row)), 2, bg, 5, 7); });
            ghostRows(ctx, x0, x1, lv, inner, [&](int row) { return blend(barColour(ctx, ctx.colourIndex(inner, row)), 1, bg, 1, 2); });
            break;
        }
        case kEffectFadeShadow: {
            const int gh = g.ghost[bar], step = g.ghost2[bar] / 4;
            ghostRows(ctx, x0, x1, lv, gh, [&](int row) { return fadeShadowColour(halfBarColour(ctx, ctx.colourIndex(gh, row)), bg, step); });
            break;
        }
        default:
            break;
        }
        plainBar(ctx, bar);
        plainPeak(ctx, bar);
    }
}

// The grids take the palette colour for a height and draw it dimmed: `dim` above the reflection
// line (and everywhere for upright and mirror), `reflectedDim` below it.

// BackgroundGrid / BackgroundFade: every Y-spaced row, in the bar columns only, coloured by its
// height: `colouridx = y * (height_scale + 0.0035)`, height_scale = 255 / (draw_height - 1).
template <typename ColourAt>
void gridUpright(const DrawContext &ctx, ColourAt colourAt) {
    const double heightScale = 255.0 / std::max(1, ctx.h - 1) + 0.0035;
    for (int row = 0; row < ctx.h; row += ctx.ySpacing) {
        const RGB c = colourAt(std::min(255, static_cast<int>(row * heightScale)));
        for (size_t bar = 0; bar < ctx.barStart.size(); ++bar) ctx.fillRow(row, ctx.barStart[bar], ctx.barEnd[bar], c);
    }
}

// BackgroundGridMirror / BackgroundFadeMirror.
template <typename ColourAt>
void gridMirror(const DrawContext &ctx, ColourAt colourAt) {
    const int ys = ctx.ySpacing;
    const int middle = ctx.h / 2 / ys * ys;
    for (int y = 0; y <= ctx.h / 2; y += ys) {
        const RGB c = colourAt(std::min(255, static_cast<int>(y * 2.0 * 255.0 / ctx.h)));
        for (size_t bar = 0; bar < ctx.barStart.size(); ++bar) {
            ctx.fillRow(middle + y, ctx.barStart[bar], ctx.barEnd[bar], c);
            ctx.fillRow(middle - y, ctx.barStart[bar], ctx.barEnd[bar], c);
        }
    }
}

// BackgroundGridReflection / BackgroundFadeReflection: the upright part above the line, then the
// reflected part below it, compressed.
template <typename ColourAt, typename ReflectedAt>
void gridReflection(const DrawContext &ctx, ColourAt colourAt, ReflectedAt reflectedAt) {
    const int ys = ctx.ySpacing;
    const int middle = ctx.h / 3 / ys * ys;
    const double heightScale = 255.0 / std::max(1, ctx.h - 1) + 0.0035;
    const auto rowAt = [&](int row, const RGB &c) {
        for (size_t bar = 0; bar < ctx.barStart.size(); ++bar) ctx.fillRow(row, ctx.barStart[bar], ctx.barEnd[bar], c);
    };
    for (int y = middle; y < ctx.h; y += ys) {
        rowAt(y, colourAt(std::min(255, static_cast<int>((y - middle) * 1.49 * heightScale))));
    }
    for (int y = middle; y >= 0; y -= ys) {
        rowAt(y, reflectedAt(std::min(255, static_cast<int>((middle - y) * 2.975 * heightScale))));
    }
}

template <typename ColourAt, typename ReflectedAt>
void drawGrid(const DrawContext &ctx, int effect, ColourAt colourAt, ReflectedAt reflectedAt) {
    switch (effect) {
    case kEffectMirror:
        gridMirror(ctx, colourAt);
        break;
    case kEffectReflectionWaves:
        if (ctx.xSpacing) break;  // the plugin draws these on black
        gridReflection(ctx, colourAt, reflectedAt);
        break;
    case kEffectReflection:
        gridReflection(ctx, colourAt, reflectedAt);
        break;
    default:
        gridUpright(ctx, colourAt);
        break;
    }
}

}  // namespace

void advanceGhosts(GhostState &g, int effect, const std::vector<int> &level, int barWidth, int xSpacing, Rng &rng) {
    const size_t bands = std::min(level.size(), g.ghost.size());
    switch (effect) {
    case kEffectShadow:
        for (size_t i = 0; i < bands; ++i) {
            g.ghost[i] = g.ghost[i] < level[i] ? level[i] : std::max(0, g.ghost[i] - 1);
        }
        break;
    case kEffectDoubleShadow:
        for (size_t i = 0; i < bands; ++i) {
            g.ghost2[i] = g.ghost2[i] < level[i] ? level[i] : std::max(0, g.ghost2[i] - 2);
            g.ghost[i] = g.ghost[i] < g.ghost2[i] ? g.ghost2[i] : std::max(0, g.ghost[i] - 1);
        }
        break;
    case kEffectFadeShadow:
        // Held for 24 frames, fading one step every 4, then re-taken from the bar.
        for (size_t i = 0; i < bands; ++i) {
            if (g.ghost[i] < level[i] || g.ghost2[i]-- == 0) {
                g.ghost[i] = level[i];
                g.ghost2[i] = 23;
            }
        }
        break;
    case kEffectSmoke: {
        // The smoke drifts right one column a frame across the bar's columns, and pauses over the gap.
        if (--g.smokeMove < barWidth) {
            if (!g.smoke.empty()) {
                std::copy_backward(g.smoke.begin(), g.smoke.end() - 1, g.smoke.end());
                g.smoke[0] = 0;
            }
            if (g.smokeMove <= 0) g.smokeMove = barWidth + xSpacing;
        }
        for (size_t c = 0; c < g.smoke.size(); ++c) {
            const size_t bar = c / static_cast<size_t>(std::max(1, barWidth));
            if (bar >= level.size()) break;
            const int lv = level[bar];
            g.smoke[c] = g.smoke[c] < lv ? lv : std::max(0, g.smoke[c] - static_cast<int>(rng.next() % 4));
        }
        break;
    }
    case kEffectReflectionWaves: {
        static const int kWaveChange[4] = {0, 18, 32, 0};
        g.waveStart -= 2;
        if (!g.waveStart) g.waveStart = 14;
        int volume = 0;
        for (size_t i = 0; i < level.size(); i += 2) volume += level[i];
        volume /= std::max<int>(1, static_cast<int>(level.size()) / 2);
        if (volume > g.waveOldVolume + 5) {  // louder: bigger waves
            if (g.waveDivisor > 1) g.waveDivisor--;
            g.waveOldVolume = volume;
        } else if (volume < g.waveOldVolume - kWaveChange[g.waveDivisor]) {
            if (g.waveDivisor < 3) g.waveDivisor++;
            g.waveOldVolume = volume;
        }
        break;
    }
    default:
        break;
    }
}

void drawBackground(const DrawContext &ctx, int mode, int effect, int volume) {
    const Palette &bars = *ctx.bars;
    const Palette &volumes = *ctx.volumes;
    switch (mode) {
    case kBackgroundFlash:
    case kBackgroundSolid: {
        const RGB c = volumes[static_cast<size_t>(mode == kBackgroundFlash ? std::clamp(volume, 0, 255) : 0)];
        for (int row = 0; row < ctx.h; ++row) ctx.fillRow(row, 0, ctx.w, c);
        break;
    }
    case kBackgroundGrid:
    case kBackgroundFlashGrid: {
        // Grid: the bar colours at a third (4.5th reflected); Flash Grid: the volume colours (/1.45 reflected).
        const bool grid = mode == kBackgroundGrid;
        const Palette &p = grid ? bars : volumes;
        const double dim = grid ? 3.0 : 1.0, reflectedDim = grid ? 4.5 : 1.45;
        const auto at = [&p](int idx, double d) { return scaled(p[static_cast<size_t>(idx)], d); };
        drawGrid(ctx, effect, [&](int idx) { return at(idx, dim); }, [&](int idx) { return at(idx, reflectedDim); });
        break;
    }
    case kBackgroundBlack:
    default:
        break;
    }
}

void drawBars(const DrawContext &ctx, int effect, const GhostState &g) {
    switch (effect) {
    case kEffectMirror:
        drawMirror(ctx);
        break;
    case kEffectReflection:
        drawReflection(ctx, g, false);
        break;
    case kEffectReflectionWaves:
        drawReflection(ctx, g, true);
        break;
    case kEffectSmoke:
        drawSmoke(ctx, g);
        break;
    default:
        drawUpright(ctx, effect, g);
        break;
    }
}

}  // namespace visclassic
