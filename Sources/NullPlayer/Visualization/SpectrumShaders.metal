// =============================================================================
// SPECTRUM ANALYZER METAL SHADERS - LED Matrix Renderer
// =============================================================================
// GPU-accelerated LED matrix spectrum analyzer supporting three quality modes:
// - Classic (qualityMode=0): Discrete color bands from skin palette
// - Enhanced (qualityMode=1): Rainbow LED matrix with floating peaks
// - Ultra (qualityMode=2): Maximum quality with bloom, reflection, physics peaks
// =============================================================================

#include <metal_stdlib>
using namespace metal;

// MARK: - Structures

/// Parameters passed from Swift (44 bytes)
struct LEDParams {
    float2 viewportSize;    // Width, height in pixels (offset 0)
    int columnCount;        // Number of columns (offset 8)
    int rowCount;           // Number of rows (offset 12)
    float cellWidth;        // Width of each cell (offset 16)
    float cellHeight;       // Height of each cell (offset 20)
    float cellSpacing;      // Gap between cells (offset 24)
    int qualityMode;        // 0 = classic, 1 = enhanced (offset 28)
    float maxHeight;        // Maximum bar height for classic mode (offset 32)
    float time;             // Animation time in seconds (offset 36)
    float brightnessBoost;  // Brightness multiplier (1.0 default) (offset 40)
};

/// Vertex shader output for LED matrix mode
struct LEDVertexOut {
    float4 position [[position]];
    float2 uv;              // UV within the cell (0-1)
    int column;             // Column index
    int row;                // Row index
    float brightness;       // Cell brightness (0-1)
    float isPeak;           // 1.0 if this is the peak cell
    float normalizedColumn; // Column position 0-1 for color gradient
    float normalizedRow;    // Row position 0-1 for height effects
};

/// Vertex shader output for Classic bar mode
struct BarVertexOut {
    float4 position [[position]];
    float2 uv;              // UV coordinates within the bar (x: 0-1 across width)
    float barIndex;         // Which bar this vertex belongs to
    float normalizedHeight; // Bar height as 0-1 value
    float peakPosition;     // Peak indicator position 0-1
    float2 pixelPos;        // Pre-NDC pixel position for band calculations
};

// MARK: - Helper Functions

/// HSV to RGB conversion
float3 hsv2rgb(float h, float s, float v) {
    float3 c = float3(h * 6.0, s, v);
    float3 rgb = clamp(abs(fmod(c.x + float3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    return c.z * mix(float3(1.0), rgb, c.y);
}

// MARK: - LED Matrix Shaders (Enhanced Mode)

vertex LEDVertexOut led_matrix_vertex(
    uint vertexID [[vertex_id]],
    constant float* cellBrightness [[buffer(0)]],
    constant float* peakPositions [[buffer(1)]],
    constant LEDParams& params [[buffer(2)]]
) {
    LEDVertexOut out;
    
    // Each cell is 6 vertices (2 triangles)
    int cellIndex = vertexID / 6;
    int vertexInCell = vertexID % 6;
    
    // Calculate column and row from cell index
    // Layout: cells are indexed as [col * rowCount + row]
    int column = cellIndex / params.rowCount;
    int row = cellIndex % params.rowCount;
    
    // Bounds check
    if (column >= params.columnCount || row >= params.rowCount) {
        out.position = float4(0, 0, 0, 1);
        out.brightness = 0;
        return out;
    }
    
    // Calculate cell position in pixels
    float totalCellWidth = params.cellWidth + params.cellSpacing;
    float totalCellHeight = params.cellHeight + params.cellSpacing;
    float cellX = float(column) * totalCellWidth;
    float cellY = float(row) * totalCellHeight;
    
    // Get brightness for this cell
    float brightness = cellBrightness[cellIndex];
    
    // Check if this is the peak row
    float peakPos = peakPositions[column];
    int peakRow = min(int(peakPos * float(params.rowCount)), params.rowCount - 1);
    float isPeak = (row == peakRow && peakRow > 0) ? 1.0 : 0.0;
    
    // If this is a peak cell, ensure it has brightness
    if (isPeak > 0.5) {
        brightness = max(brightness, 1.0);
    }
    
    // Quad vertex positions (2 triangles: 0-1-2, 2-1-3)
    float2 positions[6] = {
        float2(0, 0),                                    // Bottom-left (0)
        float2(params.cellWidth, 0),                     // Bottom-right (1)
        float2(0, params.cellHeight),                    // Top-left (2)
        float2(0, params.cellHeight),                    // Top-left (2)
        float2(params.cellWidth, 0),                     // Bottom-right (1)
        float2(params.cellWidth, params.cellHeight)      // Top-right (3)
    };
    
    float2 uvs[6] = {
        float2(0, 0),   // Bottom-left
        float2(1, 0),   // Bottom-right
        float2(0, 1),   // Top-left
        float2(0, 1),   // Top-left
        float2(1, 0),   // Bottom-right
        float2(1, 1)    // Top-right
    };
    
    // Apply cell position offset
    float2 pos = positions[vertexInCell];
    pos.x += cellX;
    pos.y += cellY;
    
    // Convert to normalized device coordinates (-1 to 1)
    float2 ndc;
    ndc.x = (pos.x / params.viewportSize.x) * 2.0 - 1.0;
    ndc.y = (pos.y / params.viewportSize.y) * 2.0 - 1.0;
    
    out.position = float4(ndc, 0.0, 1.0);
    out.uv = uvs[vertexInCell];
    out.column = column;
    out.row = row;
    out.brightness = brightness;
    out.isPeak = isPeak;
    out.normalizedColumn = float(column) / float(max(params.columnCount - 1, 1));
    out.normalizedRow = float(row) / float(max(params.rowCount - 1, 1));
    
    return out;
}

fragment float4 led_matrix_fragment(
    LEDVertexOut in [[stage_in]],
    constant LEDParams& params [[buffer(1)]]
) {
    // Skip cells with zero brightness (unless peak)
    if (in.brightness < 0.01 && in.isPeak < 0.5) {
        discard_fragment();
    }
    
    // === ROUNDED RECTANGLE with anti-aliased edges ===
    float2 centered = in.uv * 2.0 - 1.0;  // -1 to 1
    float cornerRadius = 0.32;
    float2 q = abs(centered) - (1.0 - cornerRadius);
    float sdfDist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
    float edgeSmooth = 0.06;
    float shape = 1.0 - smoothstep(cornerRadius - edgeSmooth, cornerRadius + edgeSmooth, sdfDist);
    if (shape < 0.01) {
        discard_fragment();
    }
    
    // === BASE COLOR - rainbow hue from column position ===
    float hue = in.normalizedColumn;
    float3 baseColor = hsv2rgb(hue, 1.0, 1.0);
    float displayBrightness = in.isPeak > 0.5 ? 1.0 : in.brightness;
    
    // === WARM FADE TRAIL ===
    // As cells dim, they shift toward warm amber before going dark
    // Creates gorgeous "cooling ember" heat trails on decay
    float3 warmTint = float3(1.0, 0.35, 0.05);  // Deep amber
    float warmBlend = pow(1.0 - displayBrightness, 1.5) * 0.7;  // Stronger shift as it dims
    float3 fadedColor = mix(baseColor, warmTint, warmBlend);
    float3 color = fadedColor * displayBrightness;
    
    // === INNER LED GLOW (3D depth) ===
    // Brighter in center, softer toward edges - each cell looks like a real LED
    float radialDist = length(centered);
    float innerGlow = 1.0 - smoothstep(0.0, 0.9, radialDist) * 0.35;
    color *= innerGlow;
    
    // === SPECULAR HIGHLIGHT ===
    // Small bright reflection spot in upper portion of each cell
    float2 specPos = in.uv - float2(0.35, 0.72);
    float specular = exp(-dot(specPos, specPos) * 16.0) * 0.4 * displayBrightness;
    color += float3(specular);
    
    // === HEIGHT-BASED INTENSITY ===
    // Higher rows glow slightly brighter for visual depth
    float heightBoost = mix(0.82, 1.12, in.normalizedRow);
    color *= heightBoost;
    
    // === PEAK CELL RENDERING ===
    if (in.isPeak > 0.5) {
        // Peaks: white-tinted, extra bright, with glow
        float3 peakColor = mix(baseColor, float3(1.0), 0.55);
        peakColor *= innerGlow;
        peakColor += float3(specular * 1.8);
        // Subtle pulse on peaks
        float pulse = 1.0 + sin(params.time * 8.0) * 0.08;
        color = peakColor * 1.25 * pulse;
    }
    
    // === DIM CELL AMBIENT ===
    // Very dim cells still show a faint hint of their color
    // Prevents harsh on/off transitions
    if (displayBrightness > 0.01 && displayBrightness < 0.15) {
        color = max(color, baseColor * 0.04);
    }
    
    // Brightness boost (for small embedded views)
    color *= params.brightnessBoost;
    
    color = min(color, float3(1.0));
    
    return float4(color, shape);
}

// MARK: - Classic Bar Shaders (Classic Mode)

vertex BarVertexOut spectrum_vertex(
    uint vertexID [[vertex_id]],
    constant float* heights [[buffer(0)]],
    constant float* peakPositions [[buffer(1)]],
    constant LEDParams& params [[buffer(2)]]
) {
    BarVertexOut out;
    
    // Calculate which bar and which vertex within the bar
    int barIndex = vertexID / 6;
    int vertexInBar = vertexID % 6;
    
    // Bounds check
    if (barIndex >= params.columnCount) {
        out.position = float4(0, 0, 0, 1);
        out.normalizedHeight = 0;
        out.peakPosition = 0;
        return out;
    }
    
    // Get bar height and peak position (0-1 normalized)
    float height = heights[barIndex];
    float peak = peakPositions[barIndex];
    
    // Calculate bar position
    float totalBarWidth = params.cellWidth + params.cellSpacing;
    float barX = float(barIndex) * totalBarWidth;
    
    // Extend quad to cover both bar body and peak indicator
    float peakLineMargin = 4.0;  // Extra pixels above peak for line thickness
    float barPixelHeight = height * params.maxHeight;
    float peakPixelHeight = peak * params.maxHeight + peakLineMargin;
    float quadHeight = max(barPixelHeight, peakPixelHeight);
    quadHeight = min(quadHeight, params.maxHeight);  // Clamp to viewport
    
    // Collapse quad if nothing to draw
    if (height <= 0.001 && peak <= 0.01) {
        quadHeight = 0;
    }
    
    // Vertex positions within the bar (2 triangles forming a quad)
    float2 positions[6] = {
        float2(0, 0),                           // Bottom-left (0)
        float2(params.cellWidth, 0),            // Bottom-right (1)
        float2(0, quadHeight),                  // Top-left (2)
        float2(0, quadHeight),                  // Top-left (2)
        float2(params.cellWidth, 0),            // Bottom-right (1)
        float2(params.cellWidth, quadHeight)    // Top-right (3)
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
    
    // Store pre-NDC pixel position for precise band calculations in fragment shader
    out.pixelPos = pos;
    
    // Convert to normalized device coordinates (-1 to 1)
    float2 ndc;
    ndc.x = (pos.x / params.viewportSize.x) * 2.0 - 1.0;
    ndc.y = (pos.y / params.viewportSize.y) * 2.0 - 1.0;
    
    out.position = float4(ndc, 0.0, 1.0);
    out.uv = uvs[vertexInBar];
    out.barIndex = float(barIndex);
    out.normalizedHeight = height;
    out.peakPosition = peak;
    
    return out;
}

fragment float4 spectrum_fragment(
    BarVertexOut in [[stage_in]],
    constant float4* colors [[buffer(0)]],
    constant LEDParams& params [[buffer(1)]]
) {
    float pixelY = in.pixelPos.y;
    float barHeight = in.normalizedHeight * params.maxHeight;
    float peakHeight = in.peakPosition * params.maxHeight;
    
    // === PEAK INDICATOR - bright floating line above bars ===
    float peakThickness = 3.0;
    bool isPeakPixel = false;
    if (in.peakPosition > 0.015) {
        float peakDist = abs(pixelY - peakHeight);
        isPeakPixel = peakDist < peakThickness;
    }
    
    // === BAR BODY ===
    bool isBarPixel = pixelY <= barHeight && in.normalizedHeight > 0.001;
    
    // Discard empty space (not bar, not peak)
    if (!isBarPixel && !isPeakPixel) {
        discard_fragment();
    }
    
    // === DISCRETE COLOR BANDS ===
    // Quantize to rowCount bands for authentic Classic LED look
    float bandCount = float(params.rowCount);
    float bandHeight = params.maxHeight / bandCount;
    float bandIndex = floor(pixelY / bandHeight);
    float withinBand = fmod(pixelY, bandHeight);
    
    // Map band position to 24-color skin palette
    float yNorm = clamp((bandIndex + 0.5) / bandCount, 0.0, 1.0);
    const int colorCount = 24;
    float indexFloat = yNorm * float(colorCount - 1);
    int idx0 = clamp(int(indexFloat), 0, colorCount - 2);
    int idx1 = idx0 + 1;
    float blend = fract(indexFloat);
    float4 bandColor = mix(colors[idx0], colors[idx1], blend);
    
    // === PEAK RENDERING ===
    if (isPeakPixel) {
        // Color at peak height from palette, heavily brightened
        float peakBandIndex = floor(peakHeight / bandHeight);
        float peakYNorm = clamp((peakBandIndex + 0.5) / bandCount, 0.0, 1.0);
        float peakIdxFloat = peakYNorm * float(colorCount - 1);
        int peakIdx0 = clamp(int(peakIdxFloat), 0, colorCount - 2);
        int peakIdx1 = peakIdx0 + 1;
        float peakBlend = fract(peakIdxFloat);
        float4 peakBaseColor = mix(colors[peakIdx0], colors[peakIdx1], peakBlend);
        
        // Brighten significantly + white tint for visibility
        float3 peakColor = peakBaseColor.rgb * 1.5 + 0.25;
        
        // 3D cylindrical highlight on peak line
        float cx = in.uv.x * 2.0 - 1.0;
        float peakCylinder = 1.0 - pow(abs(cx), 2.0) * 0.2;
        float peakSpec = exp(-cx * cx * 4.0) * 0.3;
        peakColor = peakColor * peakCylinder + peakSpec;
        
        // Soften peak edges (anti-alias)
        float peakDist = abs(pixelY - peakHeight);
        float peakAlpha = 1.0 - smoothstep(peakThickness * 0.5, peakThickness, peakDist);
        
        return float4(min(float3(1.0), peakColor), peakAlpha);
    }
    
    // === BAND GAPS (fixed 1px line at top of each band for segmented LED look) ===
    // Use exactly 1 pixel regardless of band size - authentic Classic style
    if (withinBand > bandHeight - 1.0) {
        return float4(bandColor.rgb * 0.35, 1.0);
    }
    
    // === 3D BAR SHADING ===
    float cx = in.uv.x * 2.0 - 1.0;
    
    // Cylindrical shading - bright center, darker edges
    float cylinder = 1.0 - pow(abs(cx), 2.0) * 0.4;
    
    // Specular highlight running down center of each bar
    float specular = exp(-cx * cx * 5.0) * 0.2;
    
    // Subtle brightness boost toward top of bar for depth
    float vertBoost = pow(clamp(pixelY / max(barHeight, 1.0), 0.0, 1.0), 1.5) * 0.12;
    
    // === TOP BAND GLOW ===
    // The highest lit band gets an extra brightness kick
    float topBandStart = floor(barHeight / bandHeight) * bandHeight;
    float isTopBand = (bandIndex * bandHeight >= topBandStart - bandHeight && bandIndex * bandHeight < topBandStart) ? 1.0 : 0.0;
    float topGlow = isTopBand * 0.15;
    
    // === COMBINE ===
    float3 litColor = bandColor.rgb * cylinder + specular + bandColor.rgb * (vertBoost + topGlow);
    
    // Ensure colors stay vibrant (minimum brightness floor)
    litColor = max(litColor, bandColor.rgb * 0.75);
    litColor = min(litColor, float3(1.0));
    
    return float4(litColor, 1.0);
}

// =============================================================================
// MARK: - Ultra Mode Shaders (Maximum Quality)
// =============================================================================
// Ultra mode features:
// - 24 LED rows (vs 16 in Enhanced) for smoother vertical resolution
// - Vibrant rainbow colors with high saturation
// - Smooth rounded cells with inner gradient for 3D depth
// - Prominent floating peaks
// =============================================================================

/// Parameters for Ultra mode (56 bytes)
struct UltraParams {
    float2 viewportSize;    // Width, height in pixels (offset 0)
    int columnCount;        // Number of columns (offset 8)
    int rowCount;           // Number of rows - 24 for Ultra (offset 12)
    float cellWidth;        // Width of each cell (offset 16)
    float cellHeight;       // Height of each cell (offset 20)
    float cellSpacing;      // Gap between cells (offset 24)
    float glowRadius;       // Bloom spread radius (offset 28)
    float glowIntensity;    // Bloom strength 0-1 (offset 32)
    float reflectionHeight; // Height of reflection area (0-0.5) (offset 36)
    float reflectionAlpha;  // Reflection opacity (offset 40)
    float time;             // Animation time for subtle effects (offset 44)
    float brightnessBoost;  // Brightness multiplier (1.0 default) (offset 48)
    float padding;          // Alignment padding (offset 52)
};

/// Vertex shader output for Ultra mode
struct UltraVertexOut {
    float4 position [[position]];
    float2 uv;                  // UV within the cell (0-1)
    int column;                 // Column index
    int row;                    // Row index
    float brightness;           // Cell brightness (0-1)
    float isPeak;               // 1.0 if this is the peak cell
    float normalizedColumn;     // Column position 0-1 for color gradient
    float normalizedRow;        // Row position 0-1 for vertical gradient
};

vertex UltraVertexOut ultra_matrix_vertex(
    uint vertexID [[vertex_id]],
    constant float* cellBrightness [[buffer(0)]],
    constant float* peakPositions [[buffer(1)]],
    constant UltraParams& params [[buffer(2)]]
) {
    UltraVertexOut out;
    
    int totalCells = params.columnCount * params.rowCount;
    
    // Each cell is 6 vertices (2 triangles)
    int cellIndex = vertexID / 6;
    int vertexInCell = vertexID % 6;
    
    // Calculate column and row from cell index
    int column = cellIndex / params.rowCount;
    int row = cellIndex % params.rowCount;
    
    // Bounds check
    if (column >= params.columnCount || cellIndex >= totalCells) {
        out.position = float4(0, 0, 0, 1);
        out.brightness = 0;
        return out;
    }
    
    // Calculate cell dimensions
    float totalCellWidth = params.cellWidth + params.cellSpacing;
    float totalCellHeight = params.cellHeight + params.cellSpacing;
    
    // Calculate cell position in pixels
    float cellX = float(column) * totalCellWidth;
    float cellY = float(row) * totalCellHeight;
    
    // Get brightness for this cell
    int cellIdx = column * params.rowCount + row;
    out.brightness = cellBrightness[cellIdx];
    
    // Check if this is the peak row
    float peakPos = peakPositions[column];
    int peakRow = min(int(peakPos * float(params.rowCount)), params.rowCount - 1);
    float isPeak = (row == peakRow && peakRow > 0) ? 1.0 : 0.0;
    
    // If this is a peak cell, ensure it has brightness
    if (isPeak > 0.5) {
        out.brightness = max(out.brightness, 1.0);
    }
    
    // Quad vertex positions
    float2 positions[6] = {
        float2(0, 0),
        float2(params.cellWidth, 0),
        float2(0, params.cellHeight),
        float2(0, params.cellHeight),
        float2(params.cellWidth, 0),
        float2(params.cellWidth, params.cellHeight)
    };
    
    float2 uvs[6] = {
        float2(0, 0),
        float2(1, 0),
        float2(0, 1),
        float2(0, 1),
        float2(1, 0),
        float2(1, 1)
    };
    
    // Apply cell position offset
    float2 pos = positions[vertexInCell];
    pos.x += cellX;
    pos.y += cellY;
    
    // Convert to normalized device coordinates (-1 to 1)
    float2 ndc;
    ndc.x = (pos.x / params.viewportSize.x) * 2.0 - 1.0;
    ndc.y = (pos.y / params.viewportSize.y) * 2.0 - 1.0;
    
    out.position = float4(ndc, 0.0, 1.0);
    out.uv = uvs[vertexInCell];
    out.column = column;
    out.row = row;
    out.isPeak = isPeak;
    out.normalizedColumn = float(column) / float(max(params.columnCount - 1, 1));
    out.normalizedRow = float(row) / float(max(params.rowCount - 1, 1));
    
    return out;
}

fragment float4 ultra_matrix_fragment(
    UltraVertexOut in [[stage_in]],
    constant UltraParams& params [[buffer(1)]]
) {
    // Skip unlit cells (low threshold for smooth trail tails)
    if (in.brightness < 0.003 && in.isPeak < 0.5) {
        discard_fragment();
    }
    
    float displayBrightness = in.isPeak > 0.5 ? 1.0 : in.brightness;
    
    // === SMOOTH RAINBOW COLOR ===
    float hue = in.normalizedColumn * 0.85;
    float3 baseColor = hsv2rgb(hue, 1.0, 1.0);
    
    // === WARM TRAIL COLOR SHIFT ===
    // As brightness fades, color shifts toward warm amber for a fluid heat-trail look
    // Only kicks in at lower brightness to avoid color flashing in dense interior areas
    float warmth = pow(max(0.0, 1.0 - displayBrightness * 1.5), 2.0);
    float3 warmTint = float3(1.0, 0.35, 0.06);  // Warm amber
    float3 trailColor = mix(baseColor, warmTint, warmth * 0.5);
    
    // === PERCEPTUAL GAMMA ===
    // Apply gamma curve so brightness fades look smooth to human eyes
    // Without this, linear fade looks like it "snaps" off at the end
    float percBrightness = pow(displayBrightness, 0.75);
    
    float3 color = trailColor * percBrightness;
    
    // === SMOOTH VERTICAL GRADIENT ===
    // Higher rows subtly brighter for visual depth (smooth interpolation)
    float heightBoost = mix(0.8, 1.15, smoothstep(0.0, 1.0, in.normalizedRow));
    color *= heightBoost;
    
    // === SOFT PEAK GLOW ===
    if (in.isPeak > 0.5) {
        // Peak: bright white-tinted color with soft pulse
        float3 peakColor = mix(baseColor, float3(1.0), 0.45);
        float pulse = 1.0 + sin(params.time * 6.0) * 0.05;
        color = peakColor * pulse;
    }
    
    // === HIGH-BRIGHTNESS BLOOM ===
    // Cells at near-full brightness get a subtle extra glow boost
    if (displayBrightness > 0.85) {
        float bloom = (displayBrightness - 0.85) * 3.0;  // 0 to 0.45
        color += baseColor * bloom * 0.2;
    }
    
    // Brightness boost (for small embedded views)
    color *= params.brightnessBoost;
    
    color = min(color, float3(1.0));
    return float4(color, 1.0);
}
