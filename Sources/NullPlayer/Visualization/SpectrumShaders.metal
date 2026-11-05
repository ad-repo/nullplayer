// =============================================================================
// SPECTRUM ANALYZER METAL SHADERS
// =============================================================================
// Classic, Enhanced and Ultra are fullscreen fragment shaders over one smoothed
// analyzer curve (`levels`) and its gliding peak line (`peaks`), both sampled
// with Catmull-Rom so every mode moves and reads continuously:
// - Classic  (analyzer_classic_fragment): soft skin-palette bars
// - Enhanced (analyzer_flow_fragment):    filled flowing curve with a glowing crest
// - Ultra    (analyzer_ultra_fragment):   dense rounded bars, bloom and reflection
// Heights are anti-aliased at sub-pixel precision; that, not the frame rate,
// is what keeps slow motion from stepping.
// =============================================================================

#include <metal_stdlib>
using namespace metal;

/// Must match `AnalyzerParams` in SpectrumAnalyzerView.swift (32 bytes).
struct AnalyzerParams {
    float2 viewportSize;    // drawable pixels
    int pointCount;         // entries in levels/peaks
    int barCount;           // Classic bar count
    float time;
    float brightnessBoost;
    float pixelScale;       // drawable pixels per point
    float padding;
};

struct AnalyzerVertexOut {
    float4 position [[position]];
};

vertex AnalyzerVertexOut analyzer_vertex(uint vid [[vertex_id]]) {
    // One oversized triangle covers the viewport.
    float2 p = float2((vid << 1) & 2, vid & 2);
    AnalyzerVertexOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

// MARK: - Helpers

/// Catmull-Rom sample of `v` at x in [0,1].
static float sampleCurve(constant float* v, int n, float x) {
    float p = clamp(x, 0.0, 1.0) * float(n - 1);
    int i = int(floor(p));
    float t = p - float(i);
    float p0 = v[clamp(i - 1, 0, n - 1)];
    float p1 = v[clamp(i,     0, n - 1)];
    float p2 = v[clamp(i + 1, 0, n - 1)];
    float p3 = v[clamp(i + 2, 0, n - 1)];
    float t2 = t * t, t3 = t2 * t;
    float r = 0.5 * ((2.0 * p1) + (-p0 + p2) * t
                     + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
                     + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3);
    return clamp(r, 0.0, 1.0);
}

/// Continuous sample of the 24-entry skin palette (0 = bottom, 23 = top).
static float3 paletteAt(constant float4* colors, float t) {
    float p = clamp(t, 0.0, 1.0) * 23.0;
    int i = int(floor(p));
    return mix(colors[i].rgb, colors[min(i + 1, 23)].rgb, p - float(i));
}

/// Pixel coordinates with a bottom-left origin.
static float2 bottomUp(float4 position, float2 viewport) {
    return float2(position.x, viewport.y - position.y);
}

/// Distance from p to the segment a-b.
static float segmentDistance(float2 p, float2 a, float2 b) {
    float2 ab = b - a;
    float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
    return length(p - (a + ab * t));
}

/// Signed distance to a rounded box centred at the origin.
static float roundedBox(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// MARK: - Classic: soft skin-palette bars

fragment float4 analyzer_classic_fragment(
    AnalyzerVertexOut in [[stage_in]],
    constant float* levels [[buffer(0)]],
    constant float* peaks [[buffer(1)]],
    constant AnalyzerParams& params [[buffer(2)]],
    constant float4* colors [[buffer(3)]]
) {
    float2 vp = params.viewportSize;
    float2 px = bottomUp(in.position, vp);
    float s = params.pixelScale;

    int n = max(params.barCount, 1);
    float pitch = vp.x / float(n);
    int bar = min(int(px.x / pitch), n - 1);
    float local = px.x - float(bar) * pitch;
    float gap = pitch >= 3.0 * s ? max(1.0, round(pitch * 0.2)) : (pitch >= 3.0 ? 1.0 : 0.0);
    float left = gap * 0.5, right = pitch - gap * 0.5;
    float hCover = clamp(min(local - left, right - local) + 0.5, 0.0, 1.0);
    if (hCover <= 0.0) { return float4(0, 0, 0, 1); }

    float x = (float(bar) + 0.5) / float(n);
    float level = sampleCurve(levels, params.pointCount, x);
    float peak = max(sampleCurve(peaks, params.pointCount, x), level);
    float top = level * vp.y;

    // Body: anti-aliased top edge so the height moves at sub-pixel precision.
    float body = clamp(top - px.y + 0.5, 0.0, 1.0);
    float u = (local - left) / max(right - left, 1.0);
    float shade = 0.80 + 0.20 * sin(3.14159265 * clamp(u, 0.0, 1.0));
    float3 color = paletteAt(colors, px.y / vp.y) * shade * body;

    // Peak cap: a thin line gliding above the bar.
    float capH = max(1.0, 1.5 * s);
    float capTop = peak * vp.y + capH;
    float cap = clamp(capTop - px.y + 0.5, 0.0, 1.0) * clamp(px.y - (capTop - capH) + 0.5, 0.0, 1.0);
    if (peak > 0.02) {
        float3 capColor = min(float3(1.0), colors[23].rgb * 1.25 + 0.15);
        color = mix(color, capColor, cap);
    }

    color = min(color * hCover * params.brightnessBoost, float3(1.0));
    return float4(color, 1.0);
}

// MARK: - Enhanced: flowing filled curve

fragment float4 analyzer_flow_fragment(
    AnalyzerVertexOut in [[stage_in]],
    constant float* levels [[buffer(0)]],
    constant float* peaks [[buffer(1)]],
    constant AnalyzerParams& params [[buffer(2)]]
) {
    float2 vp = params.viewportSize;
    float2 px = bottomUp(in.position, vp);
    float s = params.pixelScale;
    int n = params.pointCount;

    float x = px.x / vp.x;
    float h = sampleCurve(levels, n, x) * vp.y;

    // True distance to the curve: nearest of the polyline segments through the
    // neighbouring columns, so steep flanks don't smear the halo down the column.
    float stepPx = max(1.0, s);
    float2 prev = float2(px.x - 8.0 * stepPx, 0.0);
    prev.y = sampleCurve(levels, n, prev.x / vp.x) * vp.y;
    float dist = 1e6;
    for (int k = -7; k <= 8; k++) {
        float2 cur = float2(px.x + float(k) * stepPx, 0.0);
        cur.y = sampleCurve(levels, n, cur.x / vp.x) * vp.y;
        dist = min(dist, segmentDistance(px, prev, cur));
        prev = cur;
    }

    // Colour drifts from mint (bass) to periwinkle (treble).
    float3 crest = mix(float3(0.30, 1.00, 0.78), float3(0.52, 0.62, 1.00), smoothstep(0.0, 1.0, x));
    float3 deep  = mix(float3(0.00, 0.20, 0.26), float3(0.10, 0.08, 0.34), x);

    float3 color = float3(0.0);

    // Fill: dark at the floor, brightening into the crest.
    float inside = clamp(h - px.y + 0.5, 0.0, 1.0);
    float t = clamp(px.y / max(h, 1.0), 0.0, 1.0);
    color += mix(deep, crest * 0.55, t * t) * inside;

    // Crest line plus a soft halo.
    float lineW = 0.75 * s;
    float line = 1.0 - smoothstep(lineW, lineW + 1.0, dist);
    float halo = exp(-dist / (5.0 * s)) * 0.45;
    float lit = smoothstep(0.0, 2.0 * s, h);   // no line drawn across silence
    color += (mix(crest, float3(1.0), 0.35) * line + crest * halo) * lit;

    // Peak trace: a faint line that settles back onto the curve.
    float p = sampleCurve(peaks, n, x) * vp.y;
    float pSlope = (sampleCurve(peaks, n, x + 1.0 / vp.x) - sampleCurve(peaks, n, x - 1.0 / vp.x)) * 0.5 * vp.y;
    float pd = abs(px.y - p) / sqrt(1.0 + pSlope * pSlope);
    float peakLine = (1.0 - smoothstep(0.5 * s, 0.5 * s + 1.0, pd)) * smoothstep(1.0 * s, 4.0 * s, p - h);
    // Too busy to read in the small main-window display.
    color += crest * peakLine * 0.6 * smoothstep(40.0 * s, 80.0 * s, vp.y);

    color = min(color * params.brightnessBoost, float3(1.0));
    return float4(color, 1.0);
}

// MARK: - Ultra: dense rounded bars with bloom and reflection

static float3 ultraColor(float x) {
    float3 c0 = float3(1.00, 0.30, 0.45);   // bass: rose
    float3 c1 = float3(0.78, 0.32, 1.00);   // low mids: violet
    float3 c2 = float3(0.28, 0.56, 1.00);   // high mids: blue
    float3 c3 = float3(0.22, 0.95, 0.92);   // treble: cyan
    float t = clamp(x, 0.0, 1.0) * 3.0;
    if (t < 1.0) return mix(c0, c1, t);
    if (t < 2.0) return mix(c1, c2, t - 1.0);
    return mix(c2, c3, t - 2.0);
}

fragment float4 analyzer_ultra_fragment(
    AnalyzerVertexOut in [[stage_in]],
    constant float* levels [[buffer(0)]],
    constant float* peaks [[buffer(1)]],
    constant AnalyzerParams& params [[buffer(2)]]
) {
    float2 vp = params.viewportSize;
    float2 px = bottomUp(in.position, vp);
    float s = params.pixelScale;
    int n = params.pointCount;

    // Reflection only where there is room for it.
    bool hasReflection = vp.y >= 90.0 * s;
    float floorY = hasReflection ? round(vp.y * 0.16) : 0.0;
    float span = vp.y - floorY;

    int bars = clamp(int(vp.x / (3.5 * s)), 16, n);
    float pitch = vp.x / float(bars);
    float gap = pitch >= 4.0 ? max(1.0, round(pitch * 0.28)) : 0.0;
    float halfW = (pitch - gap) * 0.5;
    float radius = min(halfW, 2.0 * s);

    bool mirrored = px.y < floorY;
    float y = mirrored ? (floorY - px.y) : (px.y - floorY);

    int bar = min(int(px.x / pitch), bars - 1);
    float3 color = float3(0.0);

    // Neighbouring bars contribute bloom; the own bar contributes its body.
    for (int k = -2; k <= 2; k++) {
        int b = bar + k;
        if (b < 0 || b >= bars) continue;
        float bx = (float(b) + 0.5) / float(bars);
        float level = sampleCurve(levels, n, bx);
        float top = level * span;
        if (top < 0.5) continue;
        float3 base = ultraColor(bx);

        float cx = (float(b) + 0.5) * pitch;
        // Extend the box below the floor so only the top corners are rounded.
        float2 halfSize = float2(halfW, (top + radius) * 0.5);
        float2 centre = float2(cx, (top - radius) * 0.5);
        float d = roundedBox(float2(px.x, y) - centre, halfSize, radius);

        float glow = exp(-max(d, 0.0) / (4.0 * s)) * 0.28 * level;
        color += base * glow;

        if (k == 0) {
            float cover = clamp(0.5 - d, 0.0, 1.0);
            float v = clamp(y / max(top, 1.0), 0.0, 1.0);
            float3 body = base * mix(0.35, 1.0, v) + float3(1.0) * pow(v, 6.0) * 0.45 * level;
            color = mix(color, body, cover);

            // Peak cap gliding above the bar.
            float peak = max(sampleCurve(peaks, n, bx), level) * span;
            float capH = max(1.0, min(1.25 * s, span * 0.05));
            float capY = peak + max(1.0, min(1.5 * s, span * 0.04));
            float capD = roundedBox(float2(px.x - cx, y - capY - capH * 0.5),
                                    float2(halfW, capH * 0.5), capH * 0.5);
            float cap = clamp(0.5 - capD, 0.0, 1.0) * smoothstep(0.0, 0.03, peak / span);
            color = mix(color, mix(base, float3(1.0), 0.7), cap);
        }
    }

    if (mirrored) {
        float fade = 1.0 - clamp(y / max(floorY, 1.0), 0.0, 1.0);
        color *= 0.22 * fade * fade;
    }

    color = min(color * params.brightnessBoost, float3(1.0));
    return float4(color, 1.0);
}
