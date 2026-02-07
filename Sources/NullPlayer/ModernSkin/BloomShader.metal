#include <metal_stdlib>
using namespace metal;

// MARK: - Bloom Post-Processing Shaders

/// Extract pixels above brightness threshold
kernel void bloom_extract_brightness(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float &threshold [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) return;
    
    float4 color = inTexture.read(gid);
    
    // Calculate perceived brightness (luminance)
    float brightness = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    
    if (brightness > threshold) {
        // Keep bright pixels, scale by how much they exceed threshold
        float scale = (brightness - threshold) / (1.0 - threshold);
        outTexture.write(float4(color.rgb * scale, color.a), gid);
    } else {
        outTexture.write(float4(0.0, 0.0, 0.0, 0.0), gid);
    }
}

/// Horizontal Gaussian blur pass
kernel void bloom_blur_horizontal(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant int &radius [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) return;
    
    int width = inTexture.get_width();
    float4 sum = float4(0.0);
    float weightSum = 0.0;
    
    for (int i = -radius; i <= radius; i++) {
        int x = clamp(int(gid.x) + i, 0, width - 1);
        
        // Gaussian weight
        float sigma = float(radius) / 2.0;
        float weight = exp(-float(i * i) / (2.0 * sigma * sigma));
        
        sum += inTexture.read(uint2(x, gid.y)) * weight;
        weightSum += weight;
    }
    
    outTexture.write(sum / weightSum, gid);
}

/// Vertical Gaussian blur pass
kernel void bloom_blur_vertical(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant int &radius [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) return;
    
    int height = inTexture.get_height();
    float4 sum = float4(0.0);
    float weightSum = 0.0;
    
    for (int i = -radius; i <= radius; i++) {
        int y = clamp(int(gid.y) + i, 0, height - 1);
        
        // Gaussian weight
        float sigma = float(radius) / 2.0;
        float weight = exp(-float(i * i) / (2.0 * sigma * sigma));
        
        sum += inTexture.read(uint2(gid.x, y)) * weight;
        weightSum += weight;
    }
    
    outTexture.write(sum / weightSum, gid);
}

/// Composite bloom over original image
kernel void bloom_composite(
    texture2d<float, access::read> originalTexture [[texture(0)]],
    texture2d<float, access::read> bloomTexture [[texture(1)]],
    texture2d<float, access::write> outTexture [[texture(2)]],
    constant float &intensity [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= originalTexture.get_width() || gid.y >= originalTexture.get_height()) return;
    
    float4 original = originalTexture.read(gid);
    float4 bloom = bloomTexture.read(gid);
    
    // Additive blending with intensity control
    float4 result = original + bloom * intensity;
    result.a = original.a;
    
    // Clamp to valid range
    result = clamp(result, 0.0, 1.0);
    
    outTexture.write(result, gid);
}
