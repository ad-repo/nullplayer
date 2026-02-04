// =============================================================================
// SPECTRUM ANALYZER METAL SHADERS - LED Matrix Renderer
// =============================================================================
// GPU-accelerated LED matrix spectrum analyzer supporting three quality modes:
// - Winamp (qualityMode=0): Discrete color bands from skin palette
// - Enhanced (qualityMode=1): Rainbow LED matrix with floating peaks
// - Ultra (qualityMode=2): Maximum quality with bloom, reflection, physics peaks
// =============================================================================

#include <metal_stdlib>
using namespace metal;

// MARK: - Structures

/// Parameters passed from Swift (40 bytes, 8-byte aligned)
struct LEDParams {
    float2 viewportSize;    // Width, height in pixels (offset 0)
    int columnCount;        // Number of columns (offset 8)
    int rowCount;           // Number of rows (offset 12)
    float cellWidth;        // Width of each cell (offset 16)
    float cellHeight;       // Height of each cell (offset 20)
    float cellSpacing;      // Gap between cells (offset 24)
    int qualityMode;        // 0 = winamp, 1 = enhanced (offset 28)
    float maxHeight;        // Maximum bar height for winamp mode (offset 32)
    float padding;          // Alignment padding (offset 36)
};

/// Vertex shader output for LED matrix mode
struct LEDVertexOut {
    float4 position [[position]];
    float2 uv;              // UV within the cell (0-1)
    int column;             // Column index
    int row;                // Row index
    float brightness;       // Cell brightness (0-1)
    float isPeak;           // 1.0 if this is the peak cell
};

/// Vertex shader output for Winamp bar mode
struct BarVertexOut {
    float4 position [[position]];
    float2 uv;              // UV coordinates within the bar
    float barIndex;         // Which bar this vertex belongs to
    float normalizedHeight; // Bar height as 0-1 value
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
    
    // Rainbow color based on column position
    float hue = float(in.column) / float(params.columnCount);
    float3 baseColor = hsv2rgb(hue, 1.0, 1.0);
    
    // Apply brightness
    float displayBrightness = in.isPeak > 0.5 ? 1.0 : in.brightness;
    float3 color = baseColor * displayBrightness;
    
    // Peak cells get white tint for extra visibility
    if (in.isPeak > 0.5) {
        color = min(float3(1.0), baseColor + 0.4);
    }
    
    // 3D highlight effect on upper portion of cell
    float highlight = smoothstep(0.5, 1.0, in.uv.y) * 0.3 * displayBrightness;
    color += highlight;
    
    // Rounded corner effect using UV distance from center
    float2 centered = in.uv * 2.0 - 1.0;  // -1 to 1
    float cornerRadius = 0.3;
    float2 q = abs(centered) - (1.0 - cornerRadius);
    float dist = length(max(q, 0.0));
    if (dist > cornerRadius * 0.5) {
        discard_fragment();  // Outside rounded corner
    }
    
    return float4(color, 1.0);
}

// MARK: - Winamp Bar Shaders (Classic Mode)

vertex BarVertexOut spectrum_vertex(
    uint vertexID [[vertex_id]],
    constant float* heights [[buffer(0)]],
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
        return out;
    }
    
    // Get bar height (0-1 normalized)
    float height = heights[barIndex];
    
    // Calculate bar position
    float totalBarWidth = params.cellWidth + params.cellSpacing;
    float barX = float(barIndex) * totalBarWidth;
    float barHeight = height * params.maxHeight;
    
    // Vertex positions within the bar (2 triangles forming a quad)
    float2 positions[6] = {
        float2(0, 0),                           // Bottom-left (0)
        float2(params.cellWidth, 0),            // Bottom-right (1)
        float2(0, barHeight),                   // Top-left (2)
        float2(0, barHeight),                   // Top-left (2)
        float2(params.cellWidth, 0),            // Bottom-right (1)
        float2(params.cellWidth, barHeight)     // Top-right (3)
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

fragment float4 spectrum_fragment(
    BarVertexOut in [[stage_in]],
    constant float4* colors [[buffer(0)]],
    constant LEDParams& params [[buffer(1)]]
) {
    // Skip fragments for bars with zero height
    if (in.normalizedHeight <= 0.0) {
        discard_fragment();
    }
    
    // Y position determines color (0 = bottom/dark, 1 = top/bright)
    float yPos = in.uv.y;
    
    // Number of colors in palette (Winamp uses 24)
    const int colorCount = 24;
    
    // Discrete color lookup (classic pixel-art)
    int colorIndex = int(yPos * float(colorCount - 1));
    colorIndex = clamp(colorIndex, 0, colorCount - 1);
    
    return colors[colorIndex];
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

/// Parameters for Ultra mode (64 bytes)
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
    float2 padding;         // Alignment padding (offset 48)
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
    // Skip unlit cells
    if (in.brightness < 0.01 && in.isPeak < 0.5) {
        discard_fragment();
    }
    
    // === VIVID RAINBOW ===
    float hue = in.normalizedColumn * 0.85;
    float3 baseColor = hsv2rgb(hue, 1.0, 1.0);
    
    // === 3D CYLINDER EFFECT ===
    // Each bar looks like a 3D glowing cylinder
    float2 centered = in.uv * 2.0 - 1.0;
    
    // Cylindrical falloff - bright center, darker edges
    float cylinderFalloff = 1.0 - pow(abs(centered.x), 2.0) * 0.4;
    
    // Specular highlight running down center
    float specular = exp(-centered.x * centered.x * 8.0) * 0.3;
    
    // === VERTICAL GRADIENT - brighter at top ===
    float verticalGradient = mix(0.7, 1.1, in.normalizedRow);
    
    // === COMBINE LIGHTING ===
    float lighting = cylinderFalloff * verticalGradient;
    
    // Add specular highlight
    float3 litColor = baseColor * lighting + float3(specular);
    
    // === PEAKS - bright white tint ===
    if (in.isPeak > 0.5) {
        float3 peakColor = mix(baseColor, float3(1.0, 1.0, 1.0), 0.5);
        litColor = peakColor * 1.3;
    }
    
    // === TOP BLOOM - extra glow at bar tops ===
    float topGlow = pow(in.normalizedRow, 3.0) * in.brightness * 0.4;
    litColor += baseColor * topGlow;
    
    // === ENSURE VIBRANT MINIMUM ===
    litColor = max(litColor, baseColor * 0.7);
    
    return float4(litColor, 1.0);
}
