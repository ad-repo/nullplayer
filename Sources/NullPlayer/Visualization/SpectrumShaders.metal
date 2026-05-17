// =============================================================================
// SPECTRUM ANALYZER METAL SHADERS - LED Matrix Renderer
// =============================================================================
// GPU-accelerated LED matrix spectrum analyzer supporting three quality modes:
// - Classic (qualityMode=0): Discrete color bands from skin palette
// - Enhanced (qualityMode=1): Compact LED analyzer with peak caps
// - Ultra (qualityMode=2): Dense professional analyzer with clean peak caps
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
    // Off cells: discard for clean contrast against active bars
    if (in.brightness < 0.01 && in.isPeak < 0.5) {
        discard_fragment();
    }

    // === LED CORNER CLIPPING (hard discard, no alpha) ===
    // Tiny corner cutouts at cell intersections give LED panel definition.
    // Using a HARD discard (not smoothstep alpha) so there are no semi-transparent
    // seams at cell edges — the old shape-as-alpha approach produced shape=0.5 at
    // every cell boundary, creating a visible dark grid line on all four sides.
    float2 centered = in.uv * 2.0 - 1.0;
    float cornerRadius = 0.30;
    float2 q = abs(centered) - (1.0 - cornerRadius);
    if (length(max(q, 0.0)) > cornerRadius) {
        discard_fragment();
    }

    // === METER COLOR ===
    float3 lowColor = float3(0.04, 0.78, 0.48);
    float3 midColor = float3(0.88, 0.82, 0.12);
    float3 highColor = float3(1.00, 0.18, 0.06);
    float lowToMid = smoothstep(0.42, 0.76, in.normalizedRow);
    float midToHigh = smoothstep(0.76, 0.94, in.normalizedRow);
    float3 baseColor = mix(mix(lowColor, midColor, lowToMid), highColor, midToHigh);
    float displayBrightness = in.isPeak > 0.5 ? 1.0 : in.brightness;
    float percBrightness = pow(displayBrightness, 0.88);

    float3 color = baseColor * percBrightness;

    // === INNER LED DEPTH ===
    float radialDist = length(centered);
    float innerGlow = 1.0 - smoothstep(0.0, 1.0, radialDist) * 0.14;
    color *= innerGlow;

    // Keep columns readable without rainbow striping.
    float columnShade = mix(0.88, 1.0, smoothstep(0.0, 1.0, fract(in.normalizedColumn * 9.0)));
    color *= columnShade * mix(0.92, 1.12, in.normalizedRow);

    // === HIGH-BRIGHTNESS EDGE LIFT ===
    if (percBrightness > 0.8) {
        color += baseColor * (percBrightness - 0.8) * 0.35;
    }

    // === PEAK CAP ===
    if (in.isPeak > 0.5) {
        color = mix(baseColor, float3(1.0, 0.95, 0.68), 0.55);
    }

    color = min(color * params.brightnessBoost, float3(1.0));

    // Fully opaque — no alpha seam artifacts at cell boundaries
    return float4(color, 1.0);
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
    
    // === PEAK INDICATOR - chunky low-fi cap ===
    float bandCount = float(params.rowCount);
    float bandHeight = max(1.0, params.maxHeight / bandCount);
    float quantizedBarHeight = floor(barHeight / bandHeight) * bandHeight;
    float quantizedPeakHeight = floor(peakHeight / bandHeight) * bandHeight;
    float peakThickness = max(1.0, floor(bandHeight * 0.55));
    bool isPeakPixel = false;
    if (in.peakPosition > 0.015) {
        float peakDist = abs(pixelY - quantizedPeakHeight);
        isPeakPixel = peakDist < peakThickness;
    }
    
    // === BAR BODY ===
    bool isBarPixel = pixelY <= quantizedBarHeight && in.normalizedHeight > 0.001;
    
    // Discard empty space (not bar, not peak)
    if (!isBarPixel && !isPeakPixel) {
        discard_fragment();
    }
    
    // === DISCRETE COLOR BANDS ===
    float bandIndex = floor(pixelY / bandHeight);
    float withinBand = fmod(pixelY, bandHeight);
    
    // Map band position to 24-color skin palette
    float yNorm = clamp((bandIndex + 0.5) / bandCount, 0.0, 1.0);
    const int colorCount = 24;
    int colorIndex = clamp(int(floor(yNorm * float(colorCount))), 0, colorCount - 1);
    float4 bandColor = colors[colorIndex];
    
    // === PEAK RENDERING ===
    if (isPeakPixel) {
        // Color at peak height from palette, heavily brightened
        float peakBandIndex = floor(quantizedPeakHeight / bandHeight);
        float peakYNorm = clamp((peakBandIndex + 0.5) / bandCount, 0.0, 1.0);
        int peakColorIndex = clamp(int(floor(peakYNorm * float(colorCount))), 0, colorCount - 1);
        float4 peakBaseColor = colors[peakColorIndex];
        
        float3 peakColor = min(float3(1.0), peakBaseColor.rgb * 1.35 + 0.12);
        return float4(peakColor, 1.0);
    }
    
    // === BAND GAPS ===
    if (withinBand > bandHeight - 1.0) {
        return float4(bandColor.rgb * 0.18, 1.0);
    }
    
    // === LOW-FI BAR SHADING ===
    // Coarse edge darkening only; no gloss/specular effects.
    float edge = (in.uv.x < 0.18 || in.uv.x > 0.82) ? 0.72 : 1.0;
    float rowDither = fmod(bandIndex, 2.0) < 1.0 ? 0.92 : 1.0;
    float3 litColor = min(bandColor.rgb * edge * rowDither, float3(1.0));
    
    return float4(litColor, 1.0);
}

// =============================================================================
// MARK: - Ultra Mode Shaders (Maximum Quality)
// =============================================================================
// Ultra mode features:
// - Dense analyzer bars with clean peak caps
// - Vertical green/yellow/red meter palette
// - Short decay trails tuned for readability
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
    // Skip unlit cells aggressively so release does not smear.
    if (in.brightness < 0.01 && in.isPeak < 0.5) {
        discard_fragment();
    }
    
    float displayBrightness = in.isPeak > 0.5 ? 1.0 : in.brightness;
    
    // === PROFESSIONAL METER PALETTE ===
    float3 green = float3(0.02, 0.86, 0.30);
    float3 yellow = float3(0.96, 0.84, 0.10);
    float3 red = float3(1.00, 0.16, 0.06);
    float lowToMid = smoothstep(0.34, 0.72, in.normalizedRow);
    float midToHigh = smoothstep(0.72, 0.94, in.normalizedRow);
    float3 baseColor = mix(mix(green, yellow, lowToMid), red, midToHigh);
    
    // === PERCEPTUAL GAMMA ===
    // A slightly harder curve keeps low-level release crisp.
    float percBrightness = pow(displayBrightness, 0.92);
    
    float3 color = baseColor * percBrightness;
    
    // Subtle column separation without rainbow color-coding.
    float columnShade = mix(0.92, 1.0, smoothstep(0.0, 1.0, fract(in.normalizedColumn * 12.0)));
    color *= columnShade;
    
    // === PEAK CAP ===
    if (in.isPeak > 0.5) {
        color = mix(baseColor, float3(1.0, 0.96, 0.70), 0.55);
    }
    
    // Bright cells get a restrained edge lift instead of neon bloom.
    if (displayBrightness > 0.85) {
        float lift = (displayBrightness - 0.85) * 2.0;
        color += baseColor * lift * 0.08;
    }
    
    // Brightness boost (for small embedded views)
    color *= params.brightnessBoost;
    
    color = min(color, float3(1.0));
    return float4(color, 1.0);
}
