// =============================================================================
// SNOW SHADERS - Procedural Snowfall Visualizer
// =============================================================================
// Layered snowfall rendered entirely in the fragment shader. Audio drives the
// storm state: quiet passages produce light flurries, louder passages build
// denser snowfall, longer streaks, brighter exposure, and a whiteout sky.
// Fall speed comes from BPM, not energy, and is driven on the CPU side.
// =============================================================================

#include <metal_stdlib>
using namespace metal;

struct SnowParams {
    float2 viewportSize;
    float time;
    float bassEnergy;
    float trebleEnergy;
    float totalEnergy;
    float beatIntensity;
    float fallOffset;
    float windPhase;
    float density;
    float brightnessBoost;
    float stormLevel;
};

float snow_hash(float2 p) {
    p = fract(p * float2(443.897, 441.423));
    p += dot(p, p + 23.19);
    return fract(p.x * p.y);
}

float snow_hash1(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float snow_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(snow_hash(i), snow_hash(i + float2(1.0, 0.0)), f.x),
        mix(snow_hash(i + float2(0.0, 1.0)), snow_hash(i + float2(1.0, 1.0)), f.x),
        f.y
    );
}

float snow_fbm(float2 p) {
    float value = 0.0;
    float amp = 0.55;
    float freq = 1.0;
    float2x2 rot = float2x2(0.8, 0.6, -0.6, 0.8);
    for (int i = 0; i < 4; i++) {
        value += amp * snow_noise(p * freq);
        p = rot * p;
        freq *= 2.07;
        amp *= 0.5;
    }
    return value;
}

float snowflake_alpha(float2 delta, float radius, float blur, float stretch) {
    float2 q = float2(delta.x / max(stretch, 0.001), delta.y);
    float d = length(q);
    float core = 1.0 - smoothstep(radius * 0.25, radius, d);
    float halo = 1.0 - smoothstep(radius, radius + blur, d);
    return max(core, halo * 0.45);
}

float snow_streak(float2 delta, float width, float trail) {
    float core = 1.0 - smoothstep(width, width + 0.06, abs(delta.x));
    float tail = smoothstep(-trail * 0.2, 0.0, delta.y) * (1.0 - smoothstep(0.0, trail, delta.y));
    return core * tail;
}

vertex float4 snow_vertex(uint vertexID [[vertex_id]]) {
    float2 positions[6] = {
        float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
        float2(-1.0, 1.0),  float2(1.0, -1.0), float2(1.0, 1.0)
    };
    return float4(positions[vertexID], 0.0, 1.0);
}

fragment float4 snow_fragment(
    float4 position [[position]],
    constant SnowParams& params [[buffer(0)]]
) {
    float2 uv = position.xy / params.viewportSize;
    uv.y = 1.0 - uv.y;
    float aspect = params.viewportSize.x / max(params.viewportSize.y, 1.0);
    float2 centered = (uv - 0.5) * float2(aspect, 1.0);

    float storm = clamp(params.stormLevel, 0.0, 1.0);
    float storm2 = storm * storm;
    float density = clamp(pow(params.density, 1.15), 0.004, 1.0);
    float driftStrength = 0.012 + params.bassEnergy * 0.04;

    // Sky: darkens and washes toward storm-grey whiteout as the blizzard builds.
    float skyMix = smoothstep(-0.25, 0.9, uv.y);
    float3 skyTop = mix(float3(0.18, 0.22, 0.26), float3(0.42, 0.45, 0.50), storm);
    float3 skyBottom = mix(float3(0.34, 0.38, 0.43), float3(0.62, 0.66, 0.70), storm);
    float3 color = mix(skyBottom, skyTop, skyMix);

    float cloud = snow_fbm(centered * float2(0.8, 1.2) + float2(params.time * 0.01 + params.windPhase * 0.15, 0.0));
    color += float3(0.06, 0.07, 0.08) * cloud * 0.05;
    // Whiteout fog band — heavier near the horizon line during blizzard.
    float fogBand = smoothstep(0.15, 0.85, uv.y) * 0.55 + 0.45;
    color = mix(color, float3(0.88, 0.91, 0.95), storm2 * fogBand * 0.55);

    // Streak slant — gentle lean, no oscillation.
    float windSlant = 0.08 + storm * 0.18;

    float snowAccum = 0.0;

    const int layerCount = 5;
    for (int layer = 0; layer < layerCount; layer++) {
        float lf = float(layer) / float(layerCount - 1);
        float layerDensity = density * mix(0.08, 0.52, lf);
        float cols = mix(8.0, 22.0, lf) * aspect;
        float rows = mix(7.0, 19.0, lf);
        float fall = params.fallOffset * mix(0.45, 1.95, lf);

        float2 field = float2(uv.x * cols, uv.y * rows + fall * rows);

        float2 baseCell = floor(field);
        for (int oy = -1; oy <= 1; oy++) {
            for (int ox = -1; ox <= 1; ox++) {
                float2 cell = baseCell + float2(float(ox), float(oy));
                float seed = snow_hash(cell + float2(float(layer) * 31.7, float(layer) * 17.1));
                float spawnProb = mix(0.004, 0.14, clamp(layerDensity, 0.0, 1.0));
                spawnProb *= mix(0.65, 1.15, lf);
                if (seed > spawnProb) {
                    continue;
                }

                float2 jitter = float2(
                    snow_hash(cell * 1.73 + 9.1 + float(layer)),
                    snow_hash(cell * 2.31 + 4.7 + float(layer) * 3.1)
                );
                float2 flakePos = cell + jitter;
                float drift = (snow_hash1(seed * 91.7) - 0.5) * driftStrength * cols;
                flakePos.x += drift * (0.5 + lf);
                float2 delta = field - flakePos;

                float radius = mix(0.08, 0.22, lf) * (0.90 + snow_hash1(seed * 73.1) * 0.75);
                radius *= 1.0 + params.totalEnergy * 0.14 + params.beatIntensity * 0.35;
                float blur = radius * mix(0.8, 1.35, lf) * (1.0 + storm * 0.4);
                float stretch = 1.0 + mix(0.02, 0.08, lf);
                float alpha = snowflake_alpha(delta, radius, blur, stretch);

                // Slant the streak's local axis with the wind so streaks lean diagonally in a blizzard.
                float2 slantDelta = float2(delta.x - delta.y * windSlant, delta.y);
                float streakWidth = radius * mix(0.45, 0.20, storm);
                float streakTrail = mix(0.25, 0.95, lf) * (0.45 + params.totalEnergy * 0.55 + storm * 1.1);
                float streak = snow_streak(slantDelta, streakWidth, streakTrail);
                alpha = max(alpha, streak * (0.35 + storm * 0.5));
                if (alpha <= 0.0001) {
                    continue;
                }

                // Treble sparkle: per-flake twinkle keyed off the flake's seed.
                float twinkle = 1.0 + params.trebleEnergy * 0.6 * sin(seed * 51.3 + params.time * 6.0);

                float nearWeight = mix(0.40, 1.15, lf);
                snowAccum += alpha * nearWeight * twinkle;
            }
        }
    }

    float3 snowColor = float3(1.0, 1.0, 1.0);
    color += snowColor * min(snowAccum * (0.86 + params.beatIntensity * 0.4), 3.0);

    float vignette = 1.0 - dot(uv - 0.5, uv - 0.5) * 0.45;
    color *= clamp(vignette, 0.80, 1.0);

    float exposure = 1.10 + params.brightnessBoost * 0.24 + storm * 0.25;
    color = 1.0 - exp(-color * exposure);
    return float4(saturate(color), 1.0);
}
