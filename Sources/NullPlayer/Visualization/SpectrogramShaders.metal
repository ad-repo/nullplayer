#include <metal_stdlib>
using namespace metal;

// MARK: - Constants & Structs

constant float PI = 3.14159265359;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// MARK: - Vertex Shader

// Generates a fullscreen quad (two triangles) from the vertex id alone, so no
// vertex buffer or vertex descriptor is required. texCoord.y = 0 maps to the
// bottom of the screen so low-frequency bands (texture row 0) render at the bottom.
vertex VertexOut spectrogramVertexShader(uint vid [[vertex_id]]) {
    const float2 positions[6] = {
        float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
        float2(-1.0,  1.0), float2(1.0, -1.0), float2( 1.0, 1.0)
    };
    const float2 texCoords[6] = {
        float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0),
        float2(0.0, 1.0), float2(1.0, 0.0), float2(1.0, 1.0)
    };

    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.texCoord = texCoords[vid];
    return out;
}

// MARK: - Color Lookup Functions

// Viridis colormap: perceptually uniform gradient
// Maps normalized dB value (0.0 to 1.0) to RGB color
float3 viridisColormap(float value) {
    // Clamp to [0, 1]
    value = clamp(value, 0.0, 1.0);

    // Viridis colors sampled at key points
    float3 colors[5] = {
        float3(0.267004, 0.004874, 0.329415),  // Dark purple (0%)
        float3(0.282623, 0.140461, 0.469470),  // Purple (25%)
        float3(0.253935, 0.265254, 0.529983),  // Blue (50%)
        float3(0.206756, 0.371758, 0.553806),  // Cyan (75%)
        float3(0.993248, 0.906157, 0.143936)   // Yellow (100%)
    };

    float idx = value * 4.0;
    int i = int(floor(idx));
    float t = fract(idx);

    i = clamp(i, 0, 3);
    return mix(colors[i], colors[i + 1], smoothstep(0.0, 1.0, t));
}

// MARK: - Fragment Shader (Spectrogram)

fragment float4 spectrogramFragmentShader(
    VertexOut in [[stage_in]],
    texture2d<float> historyTexture [[texture(0)]]  // Scrolling spectrogram history
) {
    constexpr sampler textureSampler(coord::normalized,
                                     address::clamp_to_edge,
                                     filter::linear);

    // Sample history texture at current UV
    // Texture is laid out with frequency (band) on Y axis, time (history) on X axis
    // Low frequencies at bottom (Y=0), high at top (Y=1)
    float2 texCoord = in.texCoord;

    // Scroll time axis slightly (optional fade)
    float historyValue = historyTexture.sample(textureSampler, texCoord).r;

    // Fade history to create trailing effect
    historyValue *= 0.95;

    // Apply colormap based on magnitude
    float3 color = viridisColormap(historyValue);

    // Fade the noise floor to black so silence reads as a black background instead of
    // Viridis' dark-purple zero color, without distorting the rest of the gradient.
    color *= smoothstep(0.0, 0.05, historyValue);

    return float4(color, 1.0);
}
