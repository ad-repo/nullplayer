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
    float flareScroll;      // Scroll position frozen when giant fired
    float padding;
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

/// Vivid, saturated star colors from JWST images — cranked up
float3 jwst_star_color(float seed) {
    seed = fract(seed);
    if (seed < 0.16) return float3(0.2, 0.5, 1.0);      // Electric blue
    if (seed < 0.28) return float3(1.0, 0.15, 0.1);     // Vivid red
    if (seed < 0.38) return float3(1.0, 0.85, 0.0);     // Pure gold
    if (seed < 0.48) return float3(0.1, 0.7, 1.0);      // Cyan blue
    if (seed < 0.56) return float3(1.0, 0.1, 0.5);      // Neon pink
    if (seed < 0.64) return float3(0.15, 0.3, 1.0);     // Royal blue
    if (seed < 0.72) return float3(1.0, 0.6, 0.0);      // Blazing orange
    if (seed < 0.80) return float3(0.9, 0.05, 0.2);     // Hot crimson
    if (seed < 0.88) return float3(0.4, 0.9, 1.0);      // Sky blue
    return float3(1.0, 0.98, 0.9);                        // Bright white
}

/// Parametric JWST flare with rotation and chromatic color fringing
/// Returns float3 color directly — spikes carry chromatic aberration
/// (blue fringe on outer edges, warm core)
float3 jwst_flare(float2 delta, float intensity, float size, float angle, float3 baseCol) {
    float ca = cos(angle), sa = sin(angle);
    float2 rd = float2(delta.x * ca - delta.y * sa, delta.x * sa + delta.y * ca);
    
    float dist = length(rd);
    
    // Core glow (white-hot center)
    float coreSharp = 30.0 / (size * size);
    float core = exp(-dist * dist * coreSharp) * 1.2;
    float halo = exp(-dist * (5.0 / size)) * 0.12;
    
    // Spike thinness and length
    float thinness = 120.0 + size * 40.0;
    float falloff = 1.5 / size;
    
    float spikes = 0.0;
    spikes += exp(-abs(rd.x) * thinness) * exp(-abs(rd.y) * falloff * 0.6) * 0.65;
    float2 d2 = float2(rd.x * 0.5 - rd.y * 0.866, rd.x * 0.866 + rd.y * 0.5);
    float2 d3 = float2(rd.x * 0.5 + rd.y * 0.866, -rd.x * 0.866 + rd.y * 0.5);
    spikes += exp(-abs(d2.x) * thinness) * exp(-abs(d2.y) * falloff) * 0.4;
    spikes += exp(-abs(d3.x) * thinness) * exp(-abs(d3.y) * falloff) * 0.4;
    spikes += exp(-abs(rd.y) * thinness) * exp(-abs(rd.x) * falloff * 2.0) * 0.18;
    
    // === CHROMATIC FRINGING (like real JWST optics) ===
    // Core keeps color, halo tighter and less washy
    float3 coreColor = mix(baseCol, float3(1.0), 0.45);
    float3 haloColor = baseCol * 1.3;
    
    // Chromatic spike spread: slightly different falloff per channel
    // Blue channel extends slightly further, red is slightly tighter
    float spikesR = 0.0, spikesB = 0.0;
    float thinR = thinness * 1.08;  // Red is tighter
    float thinB = thinness * 0.92;  // Blue extends further
    spikesR += exp(-abs(rd.x) * thinR) * exp(-abs(rd.y) * falloff * 0.6) * 0.65;
    spikesB += exp(-abs(rd.x) * thinB) * exp(-abs(rd.y) * falloff * 0.6) * 0.65;
    spikesR += exp(-abs(d2.x) * thinR) * exp(-abs(d2.y) * falloff) * 0.4;
    spikesB += exp(-abs(d2.x) * thinB) * exp(-abs(d2.y) * falloff) * 0.4;
    spikesR += exp(-abs(d3.x) * thinR) * exp(-abs(d3.y) * falloff) * 0.4;
    spikesB += exp(-abs(d3.x) * thinB) * exp(-abs(d3.y) * falloff) * 0.4;
    
    // Compose: colored core + vivid halo + chromatically-fringed spikes
    float3 spikeColor = float3(baseCol.r * spikesR, baseCol.g * spikes, baseCol.b * spikesB) * 1.4;
    float3 result = coreColor * core
                  + haloColor * halo
                  + spikeColor;
    
    return result * intensity;
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
    constant CosmicParams& params [[buffer(0)]],
    constant float* spectrum [[buffer(1)]]
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

    // Giant flare suppression factor (computed early, used throughout)
    // Dims everything else so the giant truly owns the screen
    float giantActive = smoothstep(0.0, 0.08, params.flareIntensity);
    
    color += starField * (1.0 - giantActive * 0.7);  // Dim stars during giant

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

            float celestialSuppress = 1.0 - giantActive;
            color += (glow + coreGlow) * objCol * twinkle * celestialSuppress;
            color += spikes * objCol * twinkle * celestialSuppress;
        }
    }

    // ================================================================
    // JWST LENS FLARES: intensity indicators across the soundscape
    // ================================================================
    // Multiple flares at random positions, their count and size driven
    // by music intensity. Quiet = nothing. Moderate = small sparkles.
    // Loud = multiple bright flares. Major peak = giant screen-filler.

    float2 flareUV = (uv - 0.5) * float2(aspect, 1.0);

    // --- Intensity flares aligned to frequency peaks ---
    // Find the top 2 spectrum peaks only — fewer flares = each one pops harder.
    // X = frequency position, Y = random. Colors cranked to max vivid.
    
    // When the giant flare is active, suppress small flares entirely
    // The giant owns the screen until it fully dissipates
    float flareSuppress = smoothstep(0.0, 0.08, params.flareIntensity);
    
    int peakBands[2] = {-1, -1};
    float peakVals[2] = {0, 0};
    
    // Dynamic threshold: quiet = very high (sparse), loud = lower (more frequent)
    float peakThreshold = max(0.12, 0.40 - energy * 0.9);
    
    for (int b = 1; b < 74; b++) {
        float val = spectrum[b];
        if (val < peakThreshold) continue;
        if (val >= spectrum[b - 1] && val >= spectrum[b + 1]) {
            for (int s = 0; s < 2; s++) {
                if (val > peakVals[s]) {
                    for (int k = 1; k > s; k--) {
                        peakBands[k] = peakBands[k - 1];
                        peakVals[k] = peakVals[k - 1];
                    }
                    peakBands[s] = b;
                    peakVals[s] = val;
                    break;
                }
            }
        }
    }
    
    for (int fi = 0; fi < 2; fi++) {
        if (peakBands[fi] < 0) continue;
        
        float peakVal = peakVals[fi];
        float bandNorm = float(peakBands[fi]) / 74.0;
        
        float cycleRate = 0.3 + float(fi) * 0.25;
        float phase = floor(scroll * cycleRate + float(fi) * 0.37);
        float seed = cosmic_hash(float2(phase * 0.7, float(fi) * 11.3));
        
        float fx = (bandNorm - 0.5) * aspect;
        float fy = cosmic_hash(float2(phase + 100.0, float(fi) * 13.1)) * 0.8 - 0.4;
        float2 fpos = float2(fx, fy);
        
        float cyclePos = fract(scroll * cycleRate + float(fi) * 0.37);
        float fade = exp(-cyclePos * 4.0);
        
        // Each flare is an event — but controlled glow
        float fIntensity = peakVal * (0.6 + seed * 0.5) * fade;
        float fSize = 0.4 + seed * 1.2 + peakVal * 1.5;
        float fAngle = seed * 3.14159;
        
        // Vivid colors at full blast
        float3 fCol = jwst_star_color(seed + float(fi) * 0.23);
        fCol *= 1.6;  // Extra brightness punch
        
        float2 fDelta = flareUV - fpos;
        color += jwst_flare(fDelta, fIntensity, fSize, fAngle, fCol) * (1.0 - flareSuppress);
    }

    // --- Rare giant flare on major peaks (position frozen at trigger) ---
    if (params.flareIntensity > 0.01) {
        float fs = params.flareScroll;  // Scroll snapshot from trigger moment
        float2 giantPos = float2(
            sin(fs * 0.7) * 0.15,
            cos(fs * 0.9) * 0.1
        );
        float giantAngle = sin(fs * 0.3) * 0.4;  // Locked rotation
        float2 gDelta = flareUV - giantPos;
        float3 gCol = jwst_star_color(fract(fs * 0.05 + 0.55));  // Locked color
        color += jwst_flare(gDelta, params.flareIntensity * 1.5, 3.5, giantAngle, gCol);
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
