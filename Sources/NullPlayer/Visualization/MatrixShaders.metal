// =============================================================================
// MATRIX SHADERS - Digital Rain Visualizer
// =============================================================================
// The Matrix's iconic falling digital rain, driven by audio spectrum. Procedural
// glyph-like shapes cascade down in columns mapped to frequency bands. Brightness
// and speed scale with dB levels. Beat-synced flashes, phosphor glow, CRT vignette,
// and a wet-floor reflection at the bottom. Multiple color schemes and intensity
// presets. Full GPU procedural — no compute pass or simulation textures needed.
// =============================================================================

#include <metal_stdlib>
using namespace metal;

struct MatrixParams {
    float2 viewportSize;        // offset 0
    float time;                 // offset 8
    float bassEnergy;           // offset 12
    float midEnergy;            // offset 16
    float trebleEnergy;         // offset 20
    float totalEnergy;          // offset 24
    float beatIntensity;        // offset 28
    float dramaticIntensity;    // offset 32 - rare awakening flash
    float scrollOffset;         // offset 36
    int colorScheme;            // offset 40 - 0=classic,1=amber,2=blue,3=red,4=neon
    float intensity;            // offset 44 - 1.0=subtle, 2.0=intense
    float brightnessBoost;      // offset 48 - brightness multiplier (1.0 default)
};

// =============================================================================
// MARK: - Noise Utilities
// =============================================================================

float matrix_hash(float2 p) {
    p = fract(p * float2(443.897, 441.423));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

float matrix_hash1(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float matrix_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(matrix_hash(i), matrix_hash(i + float2(1, 0)), f.x),
        mix(matrix_hash(i + float2(0, 1)), matrix_hash(i + float2(1, 1)), f.x),
        f.y
    );
}

// =============================================================================
// MARK: - Color Palette Functions
// =============================================================================

// Leading character (near-white, tinted per scheme)
float3 matrix_head_color(int scheme) {
    switch (scheme) {
        case 1:  return float3(1.0, 0.95, 0.80);  // Warm white (amber)
        case 2:  return float3(0.85, 0.95, 1.0);   // Cool white (blue)
        case 3:  return float3(1.0, 0.85, 0.88);   // Pink-white (red)
        case 4:  return float3(1.0, 0.85, 0.95);   // Magenta-white (neon)
        default: return float3(0.75, 1.0, 0.80);   // Green-white (classic)
    }
}

// Main trail color (bright, saturated)
float3 matrix_trail_color(int scheme) {
    switch (scheme) {
        case 1:  return float3(0.85, 0.55, 0.10);  // Amber/orange
        case 2:  return float3(0.10, 0.55, 0.95);   // Electric blue
        case 3:  return float3(0.85, 0.10, 0.15);   // Crimson
        case 4:  return float3(0.90, 0.10, 0.65);   // Hot magenta
        default: return float3(0.05, 0.82, 0.15);   // Matrix green
    }
}

// Fading tail color (dark, desaturated)
float3 matrix_fade_color(int scheme) {
    switch (scheme) {
        case 1:  return float3(0.30, 0.18, 0.04);  // Dark brown
        case 2:  return float3(0.03, 0.12, 0.30);   // Deep navy
        case 3:  return float3(0.30, 0.04, 0.06);   // Dark maroon
        case 4:  return float3(0.25, 0.03, 0.20);   // Deep purple
        default: return float3(0.01, 0.25, 0.04);   // Dark green
    }
}

// Background tint (near-black, tinted)
float3 matrix_bg_color(int scheme) {
    switch (scheme) {
        case 1:  return float3(0.015, 0.008, 0.002); // Amber-black
        case 2:  return float3(0.002, 0.006, 0.018); // Blue-black
        case 3:  return float3(0.015, 0.003, 0.004); // Red-black
        case 4:  return float3(0.012, 0.002, 0.012); // Purple-black
        default: return float3(0.002, 0.012, 0.003); // Green-black
    }
}

// Glow color (for phosphor bloom around bright chars)
float3 matrix_glow_color(int scheme) {
    switch (scheme) {
        case 1:  return float3(0.50, 0.30, 0.05);
        case 2:  return float3(0.05, 0.30, 0.55);
        case 3:  return float3(0.50, 0.05, 0.08);
        case 4:  return float3(0.55, 0.05, 0.35);
        default: return float3(0.02, 0.45, 0.08);
    }
}

// =============================================================================
// MARK: - Procedural Glyph Rendering
// =============================================================================

/// Draw a procedural glyph in a cell. Returns brightness [0,1].
/// Uses hash-based segment patterns to create shapes that evoke katakana/kanji
/// without using actual font data. Each glyph is a combination of horizontal bars,
/// vertical strokes, and diagonal slashes determined by a seed hash.
float draw_glyph(float2 cellUV, float glyphSeed) {
    // cellUV is [0,1] within the cell
    // Shrink to leave padding around the glyph
    float2 g = (cellUV - 0.5) * 2.2; // [-1.1, 1.1] with some bleed
    
    float glyph = 0.0;
    
    // Use seed to pick which segments to draw (each bit = one segment)
    float seedBits = fract(glyphSeed * 127.31);
    int pattern = int(seedBits * 256.0); // 8-bit pattern
    
    // Horizontal bars (top, middle, bottom)
    if (pattern & 1) {
        float bar = smoothstep(0.06, 0.0, abs(g.y - 0.7)) * smoothstep(0.0, 0.15, 0.8 - abs(g.x));
        glyph = max(glyph, bar);
    }
    if (pattern & 2) {
        float bar = smoothstep(0.06, 0.0, abs(g.y)) * smoothstep(0.0, 0.15, 0.7 - abs(g.x));
        glyph = max(glyph, bar);
    }
    if (pattern & 4) {
        float bar = smoothstep(0.06, 0.0, abs(g.y + 0.7)) * smoothstep(0.0, 0.15, 0.8 - abs(g.x));
        glyph = max(glyph, bar);
    }
    
    // Vertical strokes (left, center, right)
    if (pattern & 8) {
        float stroke = smoothstep(0.06, 0.0, abs(g.x + 0.5)) * smoothstep(0.0, 0.15, 0.85 - abs(g.y));
        glyph = max(glyph, stroke);
    }
    if (pattern & 16) {
        float stroke = smoothstep(0.06, 0.0, abs(g.x)) * smoothstep(0.0, 0.15, 0.85 - abs(g.y));
        glyph = max(glyph, stroke);
    }
    if (pattern & 32) {
        float stroke = smoothstep(0.06, 0.0, abs(g.x - 0.5)) * smoothstep(0.0, 0.15, 0.85 - abs(g.y));
        glyph = max(glyph, stroke);
    }
    
    // Diagonal slashes
    if (pattern & 64) {
        float diag = smoothstep(0.08, 0.0, abs(g.x - g.y) * 0.707) * smoothstep(0.0, 0.15, 0.8 - abs(g.x));
        glyph = max(glyph, diag);
    }
    if (pattern & 128) {
        float diag = smoothstep(0.08, 0.0, abs(g.x + g.y) * 0.707) * smoothstep(0.0, 0.15, 0.8 - abs(g.x));
        glyph = max(glyph, diag);
    }
    
    // Small accent dot (common in katakana)
    float dotSeed = fract(glyphSeed * 53.71);
    if (dotSeed > 0.5) {
        float2 dotPos = float2(0.4 * (dotSeed - 0.5) * 4.0, 0.6);
        float dot = smoothstep(0.12, 0.0, length(g - dotPos));
        glyph = max(glyph, dot);
    }
    
    return clamp(glyph, 0.0, 1.0);
}

// =============================================================================
// MARK: - Rain Column Logic
// =============================================================================

/// Compute the rain state for a given column and row.
/// Row 0 = top of screen, numRows = bottom.
/// Head falls downward (increasing row), trail extends upward behind it.
/// Returns: x = brightness of this cell, y = head proximity (0-1 for glow)
float2 rain_cell(int col, int row, int numCols, int numRows,
                 float time, float spectrumVal, float intensity,
                 float scrollOffset) {
    float colF = float(col);
    float rowF = float(row);
    float numRowsF = float(numRows);
    
    // Per-column random speed multiplier (CONSTANT per column — never changes)
    // This ensures smooth motion: scrollOffset already has energy-based speed
    // baked in from the Swift side, so we just scale it per-column for variety.
    float colSeed = matrix_hash1(colF * 0.0731 + 0.5);
    float colSpeedMul = 0.6 + colSeed * 0.8; // 0.6x to 1.4x speed variety
    
    // Multiple rain streams per column
    // Subtle: 1-2 streams, Intense: 2-4 streams
    float totalBrightness = 0.0;
    float headProximity = 0.0;
    
    int numStreams = 1 + int(intensity * 0.8 + spectrumVal * intensity * 1.2);
    numStreams = max(numStreams, 2);
    numStreams = min(numStreams, 5);
    
    // Wrap length — how far the head travels before wrapping around
    float wrapLen = numRowsF * 2.5;
    
    for (int s = 0; s < numStreams; s++) {
        float streamSeed = matrix_hash1(colF * 7.13 + float(s) * 31.7 + 0.3);
        float streamSeed2 = matrix_hash1(colF * 11.3 + float(s) * 17.3 + 0.7);
        
        // Per-stream speed variation (also constant)
        float streamSpeedMul = colSpeedMul * (0.8 + streamSeed * 0.4);
        
        // Stream phase offset (spread streams across time, constant per stream)
        float phaseOffset = streamSeed * numRowsF * 2.0 + float(s) * numRowsF * 0.8;
        
        // Head position scrolls downward — SMOOTH because:
        //   scrollOffset is accumulated in Swift with smoothed energy (no jumps)
        //   streamSpeedMul is constant per stream (no frame-to-frame changes)
        float headPos = fmod(scrollOffset * streamSpeedMul + phaseOffset, wrapLen);
        
        // Trail length: longer with more energy, scaled by intensity
        // Subtle: shorter trails (3-10), Intense: longer trails (6-24)
        float trailBase = 2.0 + intensity * 2.0;
        float trailEnergy = spectrumVal * (4.0 + intensity * 6.0);
        float trailLen = trailBase + trailEnergy + streamSeed2 * 3.0;
        
        // Distance: head is at headPos (bottom of streak), trail extends ABOVE it
        // rowF < headPos means this row is above the head → it's in the trail
        // dist > 0 means we're in the trail (above the head)
        float dist = headPos - rowF;
        
        if (dist > -1.5 && dist < trailLen) {
            if (dist < 0.0) {
                // Slightly below the head — fading out edge
                float belowFade = 1.0 + dist; // dist is -1.5 to 0
                belowFade = clamp(belowFade, 0.0, 1.0);
                float brightness = belowFade * 0.3;
                totalBrightness = max(totalBrightness, brightness);
                if (dist > -0.5) {
                    headProximity = max(headProximity, 1.0 + dist * 2.0);
                }
            } else {
                // In the trail (above the head)
                // Normalize: 0 = head, 1 = tail
                float t = dist / trailLen;
                
                // Exponential falloff: bright at head, rapid fade
                // spectrumVal drives peak brightness hard
                float brightness = exp(-t * 2.5) * (0.7 + spectrumVal * 1.5);
                
                // Secondary streams dimmer
                if (s > 0) brightness *= 0.4 + streamSeed * 0.3;
                
                totalBrightness = max(totalBrightness, brightness);
                
                // Track head proximity for glow effect (within 2 rows of head)
                if (dist < 2.0) {
                    headProximity = max(headProximity, 1.0 - dist / 2.0);
                }
            }
        }
    }
    
    return float2(clamp(totalBrightness, 0.0, 1.5), headProximity);
}

// =============================================================================
// MARK: - Shaders
// =============================================================================

vertex float4 matrix_vertex(uint vertexID [[vertex_id]]) {
    float2 positions[6] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1),
        float2(-1, 1),  float2(1, -1), float2(1, 1)
    };
    return float4(positions[vertexID], 0, 1);
}

fragment float4 matrix_fragment(
    float4 position [[position]],
    constant MatrixParams& params [[buffer(0)]],
    constant float* spectrum [[buffer(1)]]
) {
    float2 uv = position.xy / params.viewportSize;
    // DON'T flip Y — keep natural screen coords where y=0 is top, y=1 is bottom
    // This makes rain fall downward naturally (increasing row = moving down)
    float aspect = params.viewportSize.x / params.viewportSize.y;
    
    float t          = params.time;
    float bass       = params.bassEnergy;
    float mid        = params.midEnergy;
    float treble     = params.trebleEnergy;
    float energy     = params.totalEnergy;
    float beat       = params.beatIntensity;
    float dramatic   = params.dramaticIntensity;
    float scroll     = params.scrollOffset;
    int cs           = params.colorScheme;
    float intensity  = params.intensity;
    
    // Fetch palette for current scheme
    float3 headCol   = matrix_head_color(cs);
    float3 trailCol  = matrix_trail_color(cs);
    float3 fadeCol   = matrix_fade_color(cs);
    float3 bgCol     = matrix_bg_color(cs);
    float3 glowCol   = matrix_glow_color(cs);
    
    // ================================================================
    // GRID SETUP
    // ================================================================
    
    int numCols = 75; // Match spectrum bands
    int numRows = int(float(numCols) / aspect * 1.6); // ~40 rows for typical aspect
    numRows = max(numRows, 20);
    
    float cellW = 1.0 / float(numCols);
    float cellH = 1.0 / float(numRows);
    
    // ================================================================
    // BACKGROUND: near-black with subtle code pattern
    // ================================================================
    
    float3 color = bgCol;
    
    // Faint background code layer (very dim, slowly scrolling downward)
    {
        float bgScrollSpeed = 0.06;
        float2 bgUV = uv;
        bgUV.y = fmod(bgUV.y + t * bgScrollSpeed, 1.0);
        
        int bgCol2 = int(bgUV.x * float(numCols));
        int bgRow = int(bgUV.y * float(numRows));
        float2 bgCellUV = float2(fract(bgUV.x * float(numCols)), fract(bgUV.y * float(numRows)));
        
        // Slow glyph mutation for background
        float bgGlyphSeed = matrix_hash(float2(float(bgCol2), float(bgRow)) + floor(t * 0.3) * 0.1);
        float bgGlyph = draw_glyph(bgCellUV, bgGlyphSeed);
        
        // Very dim, with random visibility per cell
        // Subtle: sparser background, Intense: denser
        float bgThreshold = 0.72 - (intensity - 1.0) * 0.15;
        float bgVisible = matrix_hash(float2(float(bgCol2) * 7.1, float(bgRow) * 11.3));
        bgVisible = step(bgThreshold, bgVisible);
        
        float bgBrightness = 0.04 + (intensity - 1.0) * 0.04;
        color += fadeCol * bgGlyph * bgVisible * bgBrightness * (0.7 + energy * 0.3);
    }
    
    // ================================================================
    // MAIN DIGITAL RAIN
    // ================================================================
    
    // Determine which cell we're in
    // Row 0 = top of screen, row increases downward
    int col = int(uv.x * float(numCols));
    col = clamp(col, 0, numCols - 1);
    int row = int(uv.y * float(numRows));
    row = clamp(row, 0, numRows - 1);
    
    float2 cellUV = float2(fract(uv.x * float(numCols)), fract(uv.y * float(numRows)));
    
    // Get spectrum value for this column
    float specVal = spectrum[col];
    
    // ---- STREAKERS: top 1-4 spectrum peaks get a fast, extra-bright streak ----
    // Find the hottest frequency bands — streakers appear where the music is loudest
    // Spread out: peaks must be at least 8 bands apart to avoid clustering
    int streakers[4] = {-1, -1, -1, -1};
    float streakVals[4] = {0, 0, 0, 0};
    float streakThreshold = 0.20 + (2.0 - intensity) * 0.1; // Higher bar for subtle mode
    
    for (int b = 1; b < 74; b++) {
        float val = spectrum[b];
        if (val < streakThreshold) continue;
        // Must be a local peak (bigger than neighbors)
        if (val >= spectrum[b - 1] && val >= spectrum[b + 1]) {
            // Check minimum spacing from existing streakers
            bool tooClose = false;
            for (int s = 0; s < 4; s++) {
                if (streakers[s] >= 0 && abs(b - streakers[s]) < 8) { tooClose = true; break; }
            }
            if (tooClose) continue;
            
            // Insert into sorted list
            for (int s = 0; s < 4; s++) {
                if (val > streakVals[s]) {
                    for (int k = 3; k > s; k--) {
                        streakers[k] = streakers[k-1]; streakVals[k] = streakVals[k-1];
                    }
                    streakers[s] = b; streakVals[s] = val;
                    break;
                }
            }
        }
    }
    
    bool isStreaker = false;
    float streakEnergy = 0.0;
    for (int s = 0; s < 4; s++) {
        if (col == streakers[s]) { isStreaker = true; streakEnergy = streakVals[s]; break; }
    }
    
    // Streaker scroll is 2.5x faster with unique phase offset, brightness scales with peak energy
    float effectiveScroll = scroll;
    float streakBrightMul = 1.0;
    if (isStreaker) {
        effectiveScroll = scroll * 2.5 + float(col) * 3.7;
        streakBrightMul = 1.5 + streakEnergy * 2.0; // Brighter for louder peaks
    }
    
    // Compute rain state for this cell
    float2 rainState = rain_cell(col, row, numCols, numRows, t, specVal, intensity, effectiveScroll);
    float brightness = rainState.x * streakBrightMul;
    float headProx = rainState.y;
    
    // Glyph rendering with mutation
    // Glyphs change periodically — faster for brighter cells (more "active" look)
    float mutationSpeed = 1.0 + specVal * 3.0 + headProx * 10.0;
    float glyphSeed = matrix_hash(float2(float(col), float(row)) + floor(t * mutationSpeed) * 0.137);
    float glyph = draw_glyph(cellUV, glyphSeed);
    
    // Color the glyph based on brightness and head proximity
    if (brightness > 0.005) {
        // Interpolate: head = white-hot, mid = trail color, tail = fade color
        float3 charColor;
        if (headProx > 0.3) {
            // Near the head: bright, near-white — the iconic leading character
            charColor = mix(trailCol, headCol, headProx * headProx);
        } else {
            // In the trail: gradient from trail to fade
            float trailT = clamp(brightness * 1.5, 0.0, 1.0);
            charColor = mix(fadeCol, trailCol, trailT);
        }
        
        // Apply glyph shape and brightness
        float charBright = glyph * brightness;
        
        // Boost head characters to REALLY pop — blindingly bright leading edge
        if (headProx > 0.4) {
            charBright *= 1.5 + headProx * 3.0;
            // Add solid glow even outside glyph segments near the head
            float headFill = headProx * headProx * 0.3;
            charBright = max(charBright, headFill);
        }
        
        color += charColor * charBright;
    }
    
    // ================================================================
    // PHOSPHOR GLOW: bloom around bright characters
    // ================================================================
    
    {
        float glowAccum = 0.0;
        
        // Sample neighboring cells for glow bleeding
        // Subtle: range 1, Intense: range 2
        int glowRange = int(intensity);
        for (int dy = -glowRange; dy <= glowRange; dy++) {
            for (int dx = -glowRange; dx <= glowRange; dx++) {
                if (dx == 0 && dy == 0) continue;
                
                int nc = col + dx;
                int nr = row + dy;
                if (nc < 0 || nc >= numCols || nr < 0 || nr >= numRows) continue;
                
                float nSpec = spectrum[clamp(nc, 0, 74)];
                bool nIsStreaker = false;
                for (int si = 0; si < 4; si++) { if (nc == streakers[si]) { nIsStreaker = true; break; } }
                float nScroll = nIsStreaker ? (scroll * 2.5 + float(nc) * 3.7) : scroll;
                float2 nRain = rain_cell(nc, nr, numCols, numRows, t, nSpec, intensity, nScroll);
                if (nIsStreaker) { nRain.x *= 1.5 + nSpec * 2.0; }
                
                float dist = length(float2(float(dx), float(dy)));
                float glowFalloff = exp(-dist * dist * 0.8);
                glowAccum += nRain.x * nRain.y * glowFalloff;
            }
        }
        
        // Also add self-glow for head characters
        glowAccum += headProx * brightness * 3.0;
        
        float glowStrength = 0.06 + (intensity - 1.0) * 0.08;
        color += glowCol * glowAccum * glowStrength;
    }
    
    // ================================================================
    // SCANLINE EFFECT: subtle CRT horizontal lines
    // ================================================================
    
    {
        float scanline = sin(uv.y * params.viewportSize.y * 0.5) * 0.5 + 0.5;
        scanline = 0.93 + scanline * 0.07;
        color *= scanline;
    }
    
    // ================================================================
    // REFLECTION POOL: wet floor at bottom
    // ================================================================
    
    {
        // uv.y > 0.82 = bottom 18% of screen (natural coords, y=1 is bottom)
        float reflectionZone = 0.82;
        if (uv.y > reflectionZone) {
            float reflT = (uv.y - reflectionZone) / (1.0 - reflectionZone);
            
            // Mirror UV with ripple distortion
            float ripple = sin(uv.x * 25.0 + t * 2.0) * 0.004 * (1.0 + bass * 3.0)
                         + sin(uv.x * 50.0 - t * 3.0) * 0.002;
            float mirrorY = reflectionZone - (uv.y - reflectionZone) + ripple;
            mirrorY = clamp(mirrorY, 0.0, reflectionZone);
            
            // Sample the mirrored position
            float2 mirrorUV = float2(uv.x + ripple * 2.0, mirrorY);
            int mCol = clamp(int(mirrorUV.x * float(numCols)), 0, numCols - 1);
            int mRow = clamp(int(mirrorUV.y * float(numRows)), 0, numRows - 1);
            
            float mSpec = spectrum[mCol];
            bool mIsStreaker = false;
            for (int si = 0; si < 4; si++) { if (mCol == streakers[si]) { mIsStreaker = true; break; } }
            float mScroll = mIsStreaker ? (scroll * 2.5 + float(mCol) * 3.7) : scroll;
            float2 mRain = rain_cell(mCol, mRow, numCols, numRows, t, mSpec, intensity, mScroll);
            if (mIsStreaker) { mRain.x *= 2.5; }
            
            float2 mCellUV = float2(fract(mirrorUV.x * float(numCols)), fract(mirrorUV.y * float(numRows)));
            float mGlyphSeed = matrix_hash(float2(float(mCol), float(mRow)) + floor(t * (1.0 + mSpec * 3.0)) * 0.137);
            float mGlyph = draw_glyph(mCellUV, mGlyphSeed);
            
            // Reflection color (dimmer, slightly blurred by ripple)
            float reflBright = mRain.x * mGlyph * 0.3;
            float reflFade = 1.0 - reflT; // Fade to black at bottom
            reflFade *= reflFade; // Quadratic fade
            
            float3 reflColor = mix(fadeCol, trailCol, clamp(mRain.x * 2.0, 0.0, 1.0));
            if (mRain.y > 0.3) reflColor = mix(reflColor, headCol, mRain.y * 0.5);
            
            // Add reflection, blending with existing color
            color = mix(color, color + reflColor * reflBright * reflFade, 0.7);
        }
    }
    
    // ================================================================
    // BEAT PULSE: bright flash on bass hits
    // ================================================================
    
    if (beat > 0.05) {
        // Overall brightness boost — significant punch
        color *= 1.0 + beat * 0.5;
        
        // Slight color wash toward head color
        color = mix(color, color + headCol * 0.06, beat);
    }
    
    // ================================================================
    // DRAMATIC EVENT: awakening flash on major peaks
    // ================================================================
    
    if (dramatic > 0.02) {
        // Horizontal scan line that sweeps downward
        float scanY = fract(dramatic * 1.5); // Sweep position (0→1 as dramatic decays from 1→0)
        float scanDist = abs(uv.y - scanY);
        float scanLine = exp(-scanDist * scanDist * 600.0) * dramatic;
        color += headCol * scanLine * 2.5;
        
        // Global brightness pulse (fast onset, slow decay)
        float pulse = dramatic * dramatic; // Quadratic for slow tail
        color += glowCol * pulse * 0.25;
        
        // Momentarily reveal all glyphs across the screen
        float revealGlyph = draw_glyph(cellUV, glyphSeed);
        color += fadeCol * revealGlyph * dramatic * 0.35;
    }
    
    // ================================================================
    // POST-PROCESSING
    // ================================================================
    
    // Beat-reactive overall brightness
    color *= 1.0 + beat * 0.1;
    
    // Saturation boost with energy
    float3 lum = float3(dot(color, float3(0.299, 0.587, 0.114)));
    color = mix(lum, color, 1.2 + energy * 0.4);
    
    // CRT-style vignette (stronger than cosmic for that monitor feel)
    float2 vig = (uv - 0.5) * 2.0;
    float vigStrength = dot(vig, vig) * 0.3;
    color *= 1.0 - vigStrength;
    
    // Brightness boost (for small embedded views)
    color *= params.brightnessBoost;

    // Lighter tone mapping — let bright heads BURN
    color = color / (color + 0.8);
    
    // Gamma (slightly crushed for that CRT phosphor feel)
    color = pow(max(color, 0.0), float3(0.88));
    
    return float4(color, 1.0);
}
