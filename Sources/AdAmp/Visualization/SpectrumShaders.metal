// =============================================================================
// SPECTRUM ANALYZER METAL SHADERS
// =============================================================================
// GPU-accelerated spectrum analyzer rendering supporting two quality modes:
// - Winamp (qualityMode=0): Discrete color lookup, pixel-art aesthetic
// - Enhanced (qualityMode=1): Smooth gradients with optional glow
// =============================================================================

#include <metal_stdlib>
using namespace metal;

// MARK: - Structures

/// Parameters passed from Swift
struct SpectrumParams {
    float2 viewportSize;    // Width, height in pixels
    int barCount;           // Number of bars to render
    float barWidth;         // Width of each bar in pixels
    float barSpacing;       // Space between bars
    float maxHeight;        // Maximum bar height
    int qualityMode;        // 0 = winamp, 1 = enhanced
    float glowIntensity;    // Glow effect intensity
    float padding;          // Alignment padding
};

/// Vertex shader output / Fragment shader input
struct VertexOut {
    float4 position [[position]];
    float2 uv;              // UV coordinates within the bar
    float barIndex;         // Which bar this vertex belongs to
    float normalizedHeight; // Bar height as 0-1 value
};

// MARK: - Vertex Shader

/// Generates quad geometry for each spectrum bar
/// Each bar is rendered as 2 triangles (6 vertices)
vertex VertexOut spectrum_vertex(
    uint vertexID [[vertex_id]],
    constant float* heights [[buffer(0)]],
    constant SpectrumParams& params [[buffer(1)]]
) {
    VertexOut out;
    
    // Calculate which bar and which vertex within the bar
    int barIndex = vertexID / 6;
    int vertexInBar = vertexID % 6;
    
    // Get bar height (0-1 normalized)
    float height = heights[barIndex];
    
    // Calculate bar position
    float totalBarWidth = params.barWidth + params.barSpacing;
    float barX = float(barIndex) * totalBarWidth;
    float barHeight = height * params.maxHeight;
    
    // Vertex positions within the bar (2 triangles forming a quad)
    // Triangle 1: 0-1-2, Triangle 2: 2-1-3
    float2 positions[6] = {
        float2(0, 0),                           // Bottom-left (0)
        float2(params.barWidth, 0),             // Bottom-right (1)
        float2(0, barHeight),                   // Top-left (2)
        float2(0, barHeight),                   // Top-left (2)
        float2(params.barWidth, 0),             // Bottom-right (1)
        float2(params.barWidth, barHeight)      // Top-right (3)
    };
    
    float2 uvs[6] = {
        float2(0, 0),   // Bottom-left
        float2(1, 0),   // Bottom-right
        float2(0, 1),   // Top-left
        float2(0, 1),   // Top-left
        float2(1, 0),   // Bottom-right
        float2(1, 1)    // Top-right
    };
    
    // Apply bar position offset
    float2 pos = positions[vertexInBar];
    pos.x += barX;
    
    // Convert to normalized device coordinates (-1 to 1)
    float2 ndc;
    ndc.x = (pos.x / params.viewportSize.x) * 2.0 - 1.0;
    ndc.y = (pos.y / params.viewportSize.y) * 2.0 - 1.0;
    
    out.position = float4(ndc, 0.0, 1.0);
    out.uv = uvs[vertexInBar];
    out.barIndex = float(barIndex);
    out.normalizedHeight = height;
    
    return out;
}

// MARK: - Fragment Shader

/// Colors the spectrum bars based on quality mode
fragment float4 spectrum_fragment(
    VertexOut in [[stage_in]],
    constant float4* colors [[buffer(0)]],
    constant SpectrumParams& params [[buffer(1)]]
) {
    // Skip fragments for bars with zero height
    if (in.normalizedHeight <= 0.0) {
        discard_fragment();
    }
    
    // Y position determines color (0 = bottom/dark, 1 = top/bright)
    float yPos = in.uv.y;
    
    // Number of colors in palette (Winamp uses 24)
    const int colorCount = 24;
    
    if (params.qualityMode == 0) {
        // === WINAMP MODE: Discrete color lookup (classic pixel-art) ===
        // Map Y position to a discrete color index
        int colorIndex = int(yPos * float(colorCount - 1));
        colorIndex = clamp(colorIndex, 0, colorCount - 1);
        
        return colors[colorIndex];
    } else {
        // === ENHANCED MODE: Modern visuals with glow, gradients, and effects ===
        
        // Calculate smooth interpolated color
        float scaledY = yPos * float(colorCount - 1);
        int lowerIndex = int(scaledY);
        int upperIndex = min(lowerIndex + 1, colorCount - 1);
        float fraction = fract(scaledY);
        
        lowerIndex = clamp(lowerIndex, 0, colorCount - 1);
        
        float4 lowerColor = colors[lowerIndex];
        float4 upperColor = colors[upperIndex];
        
        // Smooth interpolation between colors
        float4 baseColor = mix(lowerColor, upperColor, fraction);
        
        // Boost saturation and vibrancy
        float brightness = max(baseColor.r, max(baseColor.g, baseColor.b));
        float saturationBoost = 1.3;
        float3 saturated = (baseColor.rgb - brightness) * saturationBoost + brightness;
        
        // Add brightness boost toward the top
        float brightnessBoost = 1.0 + yPos * 0.4;
        saturated *= brightnessBoost;
        
        // Apply glow effect - brighter at center of bar, fades to edges
        float centerX = abs(in.uv.x - 0.5) * 2.0;  // 0 at center, 1 at edges
        float centerGlow = 1.0 + (1.0 - centerX) * params.glowIntensity * 0.5;
        
        // Radial glow at top of bar
        float topGlowRadius = 1.0 - yPos;
        float topGlow = pow(yPos, 1.5) * params.glowIntensity * 0.6;
        
        // Specular highlight on left edge
        float specular = smoothstep(0.3, 0.0, in.uv.x) * 0.25 * params.glowIntensity;
        
        // Combine all effects
        float3 finalColor = saturated * centerGlow + topGlow + specular;
        
        // Bloom effect - brighten peaks more
        float peakBloom = pow(in.normalizedHeight, 2.0) * yPos * params.glowIntensity * 0.3;
        finalColor += peakBloom;
        
        // Clamp to valid range
        finalColor = clamp(finalColor, float3(0), float3(1.0));
        
        return float4(finalColor, baseColor.a);
    }
}
