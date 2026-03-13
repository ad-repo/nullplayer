// =============================================================================
// SNOW SHADERS - Procedural Snowfall Visualizer
// =============================================================================
// Layered snowfall rendered entirely in the fragment shader. Audio drives the
// storm state: quiet passages produce light flurries, louder passages build
// denser snowfall, faster descent, and stronger bass-driven gusting. Spectrum
// energy also modulates local density across the screen for a believable,
// frequency-shaped storm front.
// =============================================================================

#include <metal_stdlib>
using namespace metal;

struct SnowParams {
    float2 viewportSize;
    float time;
    float bassEnergy;
    float midEnergy;
    float trebleEnergy;
    float totalEnergy;
    float beatIntensity;
    float fallOffset;
    float windPhase;
    float density;
    float brightnessBoost;
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

float sample_spectrum(float x, constant float* spectrum) {
    float xf = clamp(x, 0.0, 1.0) * 74.0;
    int i0 = int(floor(xf));
    int i1 = min(i0 + 1, 74);
    float t = xf - float(i0);
    float base = mix(spectrum[i0], spectrum[i1], t);
    
    float spread = 0.0;
    float weight = 0.0;
    for (int i = -2; i <= 2; i++) {
        int idx = clamp(i0 + i, 0, 74);
        float w = 1.0 - abs(float(i)) * 0.22;
        spread += spectrum[idx] * w;
        weight += w;
    }
    return max(base, spread / max(weight, 0.001));
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
    constant SnowParams& params [[buffer(0)]],
    constant float* spectrum [[buffer(1)]]
) {
    float2 uv = position.xy / params.viewportSize;
    uv.y = 1.0 - uv.y;
    float aspect = params.viewportSize.x / max(params.viewportSize.y, 1.0);
    float2 centered = (uv - 0.5) * float2(aspect, 1.0);
    
    float density = clamp(pow(params.density, 1.15), 0.004, 1.0);
    float driftStrength = 0.012 + params.bassEnergy * 0.04;
    
    float skyMix = smoothstep(-0.25, 0.9, uv.y);
    float3 skyTop = float3(0.18, 0.22, 0.26);
    float3 skyBottom = float3(0.34, 0.38, 0.43);
    float3 color = mix(skyBottom, skyTop, skyMix);
    
    float cloud = snow_fbm(centered * float2(0.8, 1.2) + float2(params.time * 0.01, 0.0));
    color += float3(0.06, 0.07, 0.08) * cloud * 0.05;
    
    float snowAccum = 0.0;
    
    const int layerCount = 5;
    for (int layer = 0; layer < layerCount; layer++) {
        float lf = float(layer) / float(layerCount - 1);
        float layerDepth = mix(0.35, 1.35, lf);
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
                radius *= 1.0 + params.totalEnergy * 0.14;
                float blur = radius * mix(0.8, 1.35, lf);
                float stretch = 1.0 + mix(0.02, 0.08, lf);
                float alpha = snowflake_alpha(delta, radius, blur, stretch);
                float streak = snow_streak(delta, radius * 0.45, mix(0.25, 0.95, lf) * (0.45 + params.totalEnergy * 0.45));
                alpha = max(alpha, streak * 0.35);
                if (alpha <= 0.0001) {
                    continue;
                }
                
                float nearWeight = mix(0.40, 1.15, lf);
                snowAccum += alpha * nearWeight;
                
            }
        }
    }
    
    float3 snowColor = float3(1.0, 1.0, 1.0);
    color += snowColor * min(snowAccum * 0.86, 2.4);
    
    float vignette = 1.0 - dot(uv - 0.5, uv - 0.5) * 0.45;
    color *= clamp(vignette, 0.80, 1.0);
    
    float exposure = 1.10 + params.brightnessBoost * 0.24;
    color = 1.0 - exp(-color * exposure);
    return float4(saturate(color), 1.0);
}
