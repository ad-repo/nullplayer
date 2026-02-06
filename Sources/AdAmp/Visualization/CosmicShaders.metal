// =============================================================================
// JWST SHADERS - Deep Space Drift
// =============================================================================
// Floating through the vast emptiness of deep space. Mostly darkness and
// silence. Stars drift past gently. Rare, colorful celestial bodies appear
// with JWST diffraction flares on intense musical peaks. Chill and majestic.
// =============================================================================

#include <metal_stdlib>
using namespace metal;

struct CosmicParams {
    float2 viewportSize;
    float time;
    float scrollOffset;
    float bassEnergy;
    float midEnergy;
    float trebleEnergy;
    float totalEnergy;
    float beatIntensity;
    float flareIntensity;   // Big JWST flare (rare, on major peaks)
};

// MARK: - Noise

float cosmic_hash(float2 p) {
    p = fract(p * float2(233.34, 851.74));
    p += dot(p, p + 23.45);
    return fract(p.x * p.y);
}

float cosmic_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(cosmic_hash(i), cosmic_hash(i + float2(1, 0)), f.x),
        mix(cosmic_hash(i + float2(0, 1)), cosmic_hash(i + float2(1, 1)), f.x),
        f.y
    );
}

float cosmic_fbm(float2 p, int octaves) {
    float val = 0.0, amp = 0.5, freq = 1.0;
    float2x2 rot = float2x2(0.8, 0.6, -0.6, 0.8);
    for (int i = 0; i < octaves; i++) {
        val += amp * cosmic_noise(p * freq);
        freq *= 2.17; amp *= 0.48;
        p = rot * p;
    }
    return val;
}

// MARK: - JWST Color Palette

float3 jwst_palette(float t) {
    t = fract(t);
    const float3 deepSpace  = float3(0.01, 0.012, 0.04);
    const float3 indigo     = float3(0.06, 0.04, 0.16);
    const float3 violet     = float3(0.18, 0.08, 0.24);
    const float3 mauve      = float3(0.40, 0.16, 0.24);
    const float3 dustyRose  = float3(0.58, 0.28, 0.22);
    const float3 chocolate  = float3(0.38, 0.20, 0.12);
    const float3 amber      = float3(0.70, 0.42, 0.14);
    const float3 gold       = float3(0.88, 0.60, 0.22);
    const float3 cream      = float3(0.95, 0.80, 0.55);
    const float3 warmWhite  = float3(0.98, 0.93, 0.82);

    if (t < 0.1) return mix(deepSpace, indigo,    t / 0.1);
    if (t < 0.2) return mix(indigo,    violet,    (t - 0.1) / 0.1);
    if (t < 0.3) return mix(violet,    mauve,     (t - 0.2) / 0.1);
    if (t < 0.4) return mix(mauve,     dustyRose, (t - 0.3) / 0.1);
    if (t < 0.5) return mix(dustyRose, chocolate, (t - 0.4) / 0.1);
    if (t < 0.6) return mix(chocolate, amber,     (t - 0.5) / 0.1);
    if (t < 0.7) return mix(amber,     gold,      (t - 0.6) / 0.1);
    if (t < 0.8) return mix(gold,      cream,     (t - 0.7) / 0.1);
    if (t < 0.9) return mix(cream,     warmWhite, (t - 0.8) / 0.1);
    return mix(warmWhite, deepSpace, (t - 0.9) / 0.1);
}

// MARK: - JWST Diffraction Spikes

float jwst_diffraction(float2 delta, float brightness) {
    // Strong vertical spike
    float spikes = exp(-abs(delta.x) * 90.0) * exp(-abs(delta.y) * 1.2) * 0.6;
    // 60° diagonals
    float2 d2 = float2(delta.x * 0.5 - delta.y * 0.866, delta.x * 0.866 + delta.y * 0.5);
    float2 d3 = float2(delta.x * 0.5 + delta.y * 0.866, -delta.x * 0.866 + delta.y * 0.5);
    spikes += exp(-abs(d2.x) * 90.0) * exp(-abs(d2.y) * 1.8) * 0.35;
    spikes += exp(-abs(d3.x) * 90.0) * exp(-abs(d3.y) * 1.8) * 0.35;
    // Short horizontal strut
    spikes += exp(-abs(delta.y) * 90.0) * exp(-abs(delta.x) * 4.0) * 0.15;
    return spikes * brightness;
}

/// Parametric JWST flare with rotation
/// size: 0.5 = small sparkle, 1.0 = medium, 2.0+ = screen-filler
/// angle: rotation in radians — gives each flare a unique orientation
float jwst_flare(float2 delta, float intensity, float size, float angle) {
    // Rotate delta so each flare has its own spike orientation
    float ca = cos(angle), sa = sin(angle);
    float2 rd = float2(delta.x * ca - delta.y * sa, delta.x * sa + delta.y * ca);
    
    float dist = length(rd);
    
    // Core glow
    float coreSharp = 30.0 / (size * size);
    float core = exp(-dist * dist * coreSharp) * 1.2;
    float halo = exp(-dist * (4.0 / size)) * 0.25;
    
    // Spike thinness and length scale with size
    float thinness = 120.0 + size * 40.0;
    float falloff = 1.5 / size;
    
    float spikes = 0.0;
    
    // Vertical spike (strongest)
    spikes += exp(-abs(rd.x) * thinness) * exp(-abs(rd.y) * falloff * 0.6) * 0.65;
    
    // 60° diagonals
    float2 d2 = float2(rd.x * 0.5 - rd.y * 0.866, rd.x * 0.866 + rd.y * 0.5);
    float2 d3 = float2(rd.x * 0.5 + rd.y * 0.866, -rd.x * 0.866 + rd.y * 0.5);
    spikes += exp(-abs(d2.x) * thinness) * exp(-abs(d2.y) * falloff) * 0.4;
    spikes += exp(-abs(d3.x) * thinness) * exp(-abs(d3.y) * falloff) * 0.4;
    
    // Horizontal strut spike
    spikes += exp(-abs(rd.y) * thinness) * exp(-abs(rd.x) * falloff * 2.0) * 0.18;
    
    return (core + halo + spikes) * intensity;
}

// MARK: - Shaders

vertex float4 cosmic_vertex(uint vertexID [[vertex_id]]) {
    float2 positions[6] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1),
        float2(-1, 1),  float2(1, -1), float2(1, 1)
    };
    return float4(positions[vertexID], 0, 1);
}

fragment float4 cosmic_fragment(
    float4 position [[position]],
    constant CosmicParams& params [[buffer(0)]]
) {
    float2 uv = position.xy / params.viewportSize;
    uv.y = 1.0 - uv.y;
    float aspect = params.viewportSize.x / params.viewportSize.y;
    float2 centered = (uv - 0.5) * float2(aspect, 1.0);

    float t      = params.time;
    float scroll = params.scrollOffset;
    float bass   = params.bassEnergy;
    float treble = params.trebleEnergy;
    float energy = params.totalEnergy;
    float beat   = params.beatIntensity;

    // ================================================================
    // CAMERA: slow weightless drift
    // ================================================================

    centered.x += sin(t * 0.09) * 0.006;
    centered.y += cos(t * 0.07) * 0.004;
    centered *= 1.0 - beat * 0.01;

    // ================================================================
    // DEEP SPACE: vast darkness with faint color regions
    // ================================================================

    // Very slow color shifts across space as you drift
    float region = cosmic_noise(float2(scroll * 0.015, scroll * 0.01));
    float3 color = jwst_palette(region * 0.2 + 0.05) * 0.08;

    // Barely perceptible far nebula tint
    float farGas = cosmic_fbm(float2(uv.x * 1.2 + scroll * 0.02, uv.y * 1.8 + scroll * 0.03), 2);
    color += jwst_palette(farGas * 0.3 + region * 0.2 + 0.15) * farGas * 0.04;

    // ================================================================
    // STAR FIELD: sparse, gentle 3D drift
    // ================================================================

    float3 starField = float3(0);
    const int numLayers = 5;

    for (int i = 0; i < numLayers; i++) {
        float z = fmod(float(i) / float(numLayers) + scroll * 0.05, 1.0);
        z = 0.1 + z * 0.9;

        float2 projUV = centered * (0.5 / z);
        float gridScale = 2.5;
        float2 gridPos = projUV * gridScale;
        float2 cell = floor(gridPos);
        float2 local = fract(gridPos) - 0.5;

        float h = cosmic_hash(cell + float(i) * 97.0);

        // Very sparse — mostly empty space
        if (h > 0.93) {
            float2 offset = float2(cosmic_hash(cell * 1.7 + float(i) * 31.0),
                                   cosmic_hash(cell * 2.3 + float(i) * 53.0)) - 0.5;
            offset *= 0.7;
            float2 delta = local - offset;
            float dist = length(delta);

            float closeness = 1.0 - z;
            float starBright = pow(closeness, 1.3) * ((h - 0.93) / 0.07);

            // Gentle radial elongation (very subtle)
            float2 radDir = length(centered) > 0.001 ? normalize(centered) : float2(0, 1);
            float radComp = dot(delta, radDir);
            float perpComp = length(delta - radDir * radComp);
            float coreSize = 0.025 + closeness * 0.04;
            float streakSize = coreSize * (1.0 + energy * 0.3);
            float core = exp(-perpComp * perpComp / (coreSize * coreSize))
                       * exp(-radComp * radComp / (streakSize * streakSize));
            core *= starBright;

            // Soft halo
            float halo = exp(-dist * 3.5) * starBright * 0.04;

            // Twinkle
            float twinkle = 0.6 + 0.4 * sin(t * (h * 2.0 + 0.5) + h * 300.0);
            twinkle *= 0.8 + treble * 0.6;

            // Star color
            float3 starCol;
            float colorSeed = cosmic_hash(cell * 3.1 + float(i) * 17.0);
            if (h > 0.985) {
                // Rare colored star
                if (colorSeed < 0.3)       starCol = float3(1.0, 0.65, 0.35);  // Orange
                else if (colorSeed < 0.6)  starCol = float3(0.55, 0.7, 1.0);   // Blue
                else                        starCol = float3(1.0, 0.4, 0.35);   // Red
            } else {
                starCol = float3(1.0, 0.96, 0.88);  // Warm white
            }

            starField += (core + halo) * starCol * twinkle;
        }
    }

    color += starField;

    // ================================================================
    // CELESTIAL BODIES: rare, colorful, with JWST flares on peaks
    // ================================================================
    // These are special — only a few visible at any time, richly colored,
    // with diffraction spikes that bloom on musical intensity peaks.

    for (int layer = 0; layer < 2; layer++) {
        float z = fmod(float(layer) * 0.5 + scroll * 0.02, 1.0);
        z = 0.2 + z * 0.8;

        float2 projUV = centered * (0.4 / z);
        float gridScale = 1.5;
        float2 gridPos = projUV * gridScale;
        float2 cell = floor(gridPos);
        float2 local = fract(gridPos) - 0.5;

        float h = cosmic_hash(cell + float(layer) * 200.0 + 500.0);

        // Very rare objects
        if (h > 0.92) {
            float2 offset = float2(cosmic_hash(cell * 1.3 + 10.0),
                                   cosmic_hash(cell * 2.7 + 20.0)) - 0.5;
            offset *= 0.5;
            float2 delta = local - offset;
            float dist = length(delta);

            float closeness = 1.0 - z;
            float objBright = pow(closeness, 1.2) * ((h - 0.92) / 0.08);

            // Soft colored nebula glow (the body itself)
            float glowSize = 0.06 + closeness * 0.08;
            float glow = exp(-dist * dist / (glowSize * glowSize)) * objBright;

            // Bright core
            float coreGlow = exp(-dist * dist * 300.0) * objBright * 1.2;

            // Rich color from palette
            float3 objCol = jwst_palette(h * 7.0 + scroll * 0.01 + float(layer) * 0.3);
            // Pump up saturation
            float3 lum = float3(dot(objCol, float3(0.299, 0.587, 0.114)));
            objCol = mix(lum, objCol, 1.8);

            // JWST DIFFRACTION FLARE: only blooms on intensity peaks!
            // Spikes scale with beat intensity — subtle normally, dramatic on peaks
            float spikeStrength = beat * beat * 2.0 + energy * 0.15;
            float spikes = 0.0;
            if (spikeStrength > 0.05) {
                spikes = jwst_diffraction(delta / gridScale, objBright * spikeStrength) * gridScale;
            }

            float twinkle = 0.75 + 0.25 * sin(t * 1.2 + h * 100.0);

            color += (glow + coreGlow) * objCol * twinkle;
            color += spikes * objCol * twinkle;
        }
    }

    // ================================================================
    // JWST LENS FLARES: intensity indicators across the soundscape
    // ================================================================
    // Multiple flares at random positions, their count and size driven
    // by music intensity. Quiet = nothing. Moderate = small sparkles.
    // Loud = multiple bright flares. Major peak = giant screen-filler.

    float2 flareUV = (uv - 0.5) * float2(aspect, 1.0);

    // --- Intensity flares (4 channels, each with unique character) ---
    for (int fi = 0; fi < 4; fi++) {
        // Higher thresholds = fewer flares, only during louder passages
        float threshold = 0.10 + float(fi) * 0.07;
        float flareEnergy = max(0.0, energy - threshold);
        if (flareEnergy < 0.005) continue;

        // Position cycles at different rates — not aligned to any frequency
        float cycleRate = 0.35 + float(fi) * 0.25;
        float phase = floor(scroll * cycleRate + float(fi) * 0.37);
        float seed = cosmic_hash(float2(phase * 0.7, float(fi) * 11.3));
        float2 fpos = float2(
            cosmic_hash(float2(phase, float(fi) * 7.3)) * 1.4 - 0.7,
            cosmic_hash(float2(phase + 100.0, float(fi) * 13.1)) * 1.0 - 0.5
        );

        // Fade through cycle
        float cyclePos = fract(scroll * cycleRate + float(fi) * 0.37);
        float fade = exp(-cyclePos * 5.0);

        // Each flare has unique size, intensity, rotation, and color
        float fIntensity = flareEnergy * (0.8 + seed * 1.2) * fade;
        float fSize = 0.3 + seed * 1.5 + float(fi) * 0.3 + flareEnergy * 1.5;
        float fAngle = seed * 3.14159;  // Random rotation per flare

        // Rich varied color from full JWST palette (not pushed to white)
        float3 fCol = jwst_palette(seed * 0.8 + float(fi) * 0.2);
        // Only slightly lighten — keep the color character
        fCol = mix(fCol, float3(1.0, 0.95, 0.88), 0.2);
        // Boost brightness so colors read clearly
        fCol *= 1.3;

        float2 fDelta = flareUV - fpos;
        float f = jwst_flare(fDelta, fIntensity, fSize, fAngle);
        color += fCol * f;
    }

    // --- Rare giant flare on major peaks ---
    if (params.flareIntensity > 0.01) {
        float2 giantPos = float2(
            sin(scroll * 0.7) * 0.15,
            cos(scroll * 0.9) * 0.1
        );
        float giantAngle = sin(scroll * 0.3) * 0.4;  // Slow lazy rotation
        float2 gDelta = flareUV - giantPos;
        float gf = jwst_flare(gDelta, params.flareIntensity * 1.5, 3.5, giantAngle);

        float3 gCol = jwst_palette(fract(scroll * 0.05 + 0.55));
        gCol = mix(gCol, float3(1.0, 0.92, 0.7), 0.3);
        color += gCol * gf;
    }

    // ================================================================
    // POST-PROCESSING
    // ================================================================

    // Gentle beat glow
    color *= 1.0 + beat * 0.06;

    // Saturation lift with energy
    float3 lum = float3(dot(color, float3(0.299, 0.587, 0.114)));
    color = mix(lum, color, 1.0 + energy * 0.25);

    // Soft vignette
    float2 vig = (uv - 0.5) * 2.0;
    color *= 1.0 - dot(vig, vig) * 0.12;

    // Tone mapping
    color = color / (color + 0.55);

    // Gamma
    color = pow(max(color, 0.0), float3(0.88));

    return float4(color, 1.0);
}
