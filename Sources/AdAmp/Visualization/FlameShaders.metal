// =============================================================================
// FLAME VISUALIZER - Tongue-based fire with audio reactivity
// =============================================================================
// Low-res grid (128x96) with massive GPU blur for silky smooth output.
// Each column rises independently. Edge erosion thins tongues to points.
// =============================================================================

#include <metal_stdlib>
using namespace metal;

struct FlameParams {
    float2 gridSize;
    float2 viewportSize;
    float time;
    float dt;
    float bassEnergy;
    float midEnergy;
    float trebleEnergy;
    float buoyancy;
    float cooling;
    float turbulence;
    float diffusion;
    float windStrength;
    int colorScheme;
    float intensity;
    float emberRate;
    float padding;
};

struct FlameVertexOut {
    float4 position [[position]];
    float2 uv;
};

float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1));
    float d = hash21(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// MARK: - Fire Propagation

kernel void propagate_fire(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant FlameParams& params [[buffer(0)]],
    constant float* spectrum [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    int W = int(params.gridSize.x);
    int H = int(params.gridSize.y);
    if (int(gid.x) >= W || int(gid.y) >= H) return;

    int x = int(gid.x);
    int y = int(gid.y);

    // --- Bottom 2 rows: inject narrow flame sources ---
    if (y < 2) {
        float bass = 0.0;
        for (int i = 0; i < 16; i++) bass += spectrum[i];
        bass /= 16.0;
        float energy = max(bass, 0.15);

        // Random per-pixel heat
        float rng = hash21(float2(float(x) * 0.37 + params.time * 41.0,
                                   float(y) * 0.71 + params.time * 29.0));

        // Multiple noise octaves for variety: some wide warm areas + narrow bright spikes
        float nx = float(x) / float(W);
        // Slow-moving broad structure
        float broad = valueNoise(float2(nx * 6.0 + params.time * 0.5, params.time * 1.0));
        // Faster-moving narrow detail
        float narrow = valueNoise(float2(nx * 18.0 + params.time * 1.2, params.time * 2.5));
        // Combine: broad warmth + narrow hotspots for variety
        float hotspot = smoothstep(0.3, 0.5, broad) * 0.6 + smoothstep(0.45, 0.6, narrow) * 0.8;

        float heat = rng * energy * hotspot * params.intensity * 5.0;
        // Strong burst on bass peaks - creates the tall tongues
        if (bass > 0.15) {
            heat += rng * hotspot * (bass - 0.15) * 6.0;
        }

        dst.write(float4(clamp(heat, 0.0, 1.0), 0, 0, 1), gid);
        return;
    }

    // --- All other rows: rise straight up, erode edges ---

    // Each column sways independently using its own phase
    float colPhase = hash21(float2(float(x) * 0.13, 1.7)) * 6.28;
    float sway = sin(params.time * 3.0 + colPhase + float(y) * 0.08) * params.turbulence * 0.4;
    sway += sin(params.time * 1.3 + colPhase * 2.0) * params.midEnergy * params.windStrength * 0.2;

    // Sample from below with fractional offset (bilinear)
    float srcX = float(x) + sway;
    float srcY = float(y) - 1.0;
    srcX = clamp(srcX, 0.5, float(W) - 1.5);
    srcY = max(srcY, 0.5);

    float fx = floor(srcX);
    float fy = floor(srcY);
    float tx = srcX - fx;
    float ty = srcY - fy;
    float s00 = src.read(uint2(uint(fx),     uint(fy))).r;
    float s10 = src.read(uint2(min(uint(fx) + 1, uint(W - 1)), uint(fy))).r;
    float s01 = src.read(uint2(uint(fx),     min(uint(fy) + 1, uint(H - 1)))).r;
    float s11 = src.read(uint2(min(uint(fx) + 1, uint(W - 1)), min(uint(fy) + 1, uint(H - 1)))).r;
    float below = mix(mix(s00, s10, tx), mix(s01, s11, tx), ty);

    // Read horizontal neighbors for edge detection
    float here = src.read(uint2(x, y)).r;
    float left  = (x > 0)     ? src.read(uint2(x - 1, y)).r : 0.0;
    float right = (x < W - 1) ? src.read(uint2(x + 1, y)).r : 0.0;

    // Edge erosion: cool faster where there's a temperature difference with neighbors
    // This makes tongues thin to points as they rise
    float edgeness = abs(here - left) + abs(here - right);
    float erosion = edgeness * 0.15;

    // Very light horizontal diffusion (just enough to prevent aliasing)
    float hAvg = (left + right) * 0.5;
    float blended = mix(below, hAvg, params.diffusion * 0.3);

    // Mainly use the value from directly below (preserves vertical columns)
    float result = below * 0.95 + blended * 0.05;

    // Cooling
    float uv_y = float(y) / float(H);
    float coolRate = params.cooling / float(H) * (0.4 + uv_y * 0.6);
    float coolRng = hash21(float2(float(x) + params.time * 11.0, float(y) + params.time * 7.0));
    coolRate *= (0.6 + 0.8 * coolRng);

    result = max(0.0, result - coolRate - erosion);

    // Side absorption
    if (x <= 0 || x >= W - 1) result *= 0.3;
    if (y >= H - 1) result *= 0.2;

    dst.write(float4(clamp(result, 0.0, 1.0), 0, 0, 1), gid);
}

// MARK: - Color Palettes

float3 infernoColor(float t) {
    t = clamp(t, 0.0, 1.0);
    if (t < 0.15) return mix(float3(0.01, 0.0, 0.0), float3(0.4, 0.02, 0.0), t / 0.15);
    if (t < 0.4)  return mix(float3(0.4, 0.02, 0.0), float3(0.9, 0.15, 0.0), (t - 0.15) / 0.25);
    if (t < 0.65) return mix(float3(0.9, 0.15, 0.0), float3(1.0, 0.55, 0.0), (t - 0.4) / 0.25);
    if (t < 0.85) return mix(float3(1.0, 0.55, 0.0), float3(1.0, 0.9, 0.3), (t - 0.65) / 0.2);
    return mix(float3(1.0, 0.9, 0.3), float3(1.0, 1.0, 0.85), (t - 0.85) / 0.15);
}

float3 auroraColor(float t) {
    t = clamp(t, 0.0, 1.0);
    if (t < 0.25) return mix(float3(0.0), float3(0.0, 0.2, 0.1), t / 0.25);
    if (t < 0.5)  return mix(float3(0.0, 0.2, 0.1), float3(0.0, 0.8, 0.5), (t - 0.25) / 0.25);
    if (t < 0.75) return mix(float3(0.0, 0.8, 0.5), float3(0.3, 0.5, 1.0), (t - 0.5) / 0.25);
    return mix(float3(0.3, 0.5, 1.0), float3(0.9, 0.8, 1.0), (t - 0.75) / 0.25);
}

float3 electricColor(float t) {
    t = clamp(t, 0.0, 1.0);
    if (t < 0.25) return mix(float3(0.0, 0.0, 0.03), float3(0.1, 0.0, 0.4), t / 0.25);
    if (t < 0.5)  return mix(float3(0.1, 0.0, 0.4), float3(0.4, 0.15, 0.9), (t - 0.25) / 0.25);
    if (t < 0.75) return mix(float3(0.4, 0.15, 0.9), float3(0.7, 0.5, 1.0), (t - 0.5) / 0.25);
    return mix(float3(0.7, 0.5, 1.0), float3(1.0, 0.95, 1.0), (t - 0.75) / 0.25);
}

float3 oceanColor(float t) {
    t = clamp(t, 0.0, 1.0);
    if (t < 0.25) return mix(float3(0.0, 0.0, 0.03), float3(0.0, 0.08, 0.2), t / 0.25);
    if (t < 0.5)  return mix(float3(0.0, 0.08, 0.2), float3(0.0, 0.3, 0.5), (t - 0.25) / 0.25);
    if (t < 0.75) return mix(float3(0.0, 0.3, 0.5), float3(0.2, 0.7, 0.7), (t - 0.5) / 0.25);
    return mix(float3(0.2, 0.7, 0.7), float3(0.85, 1.0, 0.95), (t - 0.75) / 0.25);
}

float3 flameColor(float t, int scheme) {
    switch (scheme) {
        case 1: return auroraColor(t);
        case 2: return electricColor(t);
        case 3: return oceanColor(t);
        default: return infernoColor(t);
    }
}

// MARK: - Render

vertex FlameVertexOut flame_vertex(uint vertexID [[vertex_id]]) {
    float2 positions[6] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1),
        float2(-1, 1),  float2(1, -1), float2(1, 1)
    };
    float2 uvs[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(0, 1), float2(1, 0), float2(1, 1)
    };
    FlameVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

fragment float4 flame_fragment(
    FlameVertexOut in [[stage_in]],
    texture2d<float, access::sample> fireTex [[texture(0)]],
    constant FlameParams& params [[buffer(0)]]
) {
    constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    // Massive Gaussian blur for silky smooth upscaling from low-res grid
    // Sample at 2-texel steps for wider coverage (effectively 20+ texel radius)
    float2 texel = 1.0 / params.gridSize;
    float blurred = 0.0;
    float wt = 0.0;
    for (int dy = -5; dy <= 5; dy++) {
        for (int dx = -5; dx <= 5; dx++) {
            float d2 = float(dx * dx + dy * dy);
            float w = exp(-d2 * 0.08);  // Wide sigma
            float2 offset = float2(float(dx), float(dy)) * texel * 2.0;  // 2-texel step
            blurred += fireTex.sample(s, in.uv + offset).r * w;
            wt += w;
        }
    }
    blurred /= wt;

    float final_t = pow(blurred, 0.8);

    float3 color = flameColor(final_t, params.colorScheme);

    // Soft edge fade
    float edgeFade = smoothstep(0.0, 0.04, in.uv.x) * smoothstep(0.0, 0.04, 1.0 - in.uv.x);
    color *= edgeFade;

    float alpha = smoothstep(0.008, 0.04, final_t);
    return float4(color, alpha);
}
