// =============================================================================
// LIGHTNING SHADERS - Storm Visualizer
// =============================================================================
// Chill, JWST-inspired lightning. Each bolt in a burst decays at its own pace.
// Some linger, some flash and vanish. Rare dramatic strikes light up the sky
// and slowly fade over seconds. Dark and atmospheric when quiet.
// =============================================================================

#include <metal_stdlib>
using namespace metal;

struct ElectricityParams {
    float2 viewportSize;
    float time;
    float bassEnergy;
    float midEnergy;
    float trebleEnergy;
    float totalEnergy;
    float beatIntensity;
    float dramaticIntensity;  // Rare dramatic strike (JWST-style, slow decay)
    int colorScheme;          // 0=classic, 1=plasma, 2=matrix, 3=ember, 4=arctic
    float brightnessBoost;    // Brightness multiplier (1.0 = default, >1.0 = brighter)
};

// MARK: - Noise

float elec_hash(float2 p) {
    p = fract(p * float2(443.897, 441.423));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

float elec_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(elec_hash(i), elec_hash(i + float2(1, 0)), f.x),
        mix(elec_hash(i + float2(0, 1)), elec_hash(i + float2(1, 1)), f.x),
        f.y
    );
}

float elec_fbm(float2 p, int octaves) {
    float val = 0.0, amp = 0.5, freq = 1.0;
    float2x2 rot = float2x2(0.8, 0.6, -0.6, 0.8);
    for (int i = 0; i < octaves; i++) {
        val += amp * elec_noise(p * freq);
        freq *= 2.03; amp *= 0.52;
        p = rot * p;
    }
    return val;
}

// MARK: - Segment Distance

float seg_dist(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// MARK: - Color Palettes

// --- Multicolor helpers: pick a color from a pool based on bolt seed ---

float3 rainbow_pick(float seed, int channel) {
    int idx = int(seed * 6.0) % 6;
    if (channel == 0) {
        float3 cores[6] = {
            float3(1.0, 0.85, 0.85), float3(1.0, 0.95, 0.75), float3(0.8, 1.0, 0.8),
            float3(0.75, 0.95, 1.0), float3(0.9, 0.8, 1.0),   float3(1.0, 0.8, 0.95)
        };
        return cores[idx];
    }
    if (channel == 1) {
        float3 inners[6] = {
            float3(0.95, 0.15, 0.2),  float3(0.95, 0.7, 0.0),  float3(0.1, 0.9, 0.3),
            float3(0.1, 0.5, 0.95),   float3(0.6, 0.2, 0.95),  float3(0.95, 0.1, 0.6)
        };
        return inners[idx];
    }
    float3 outers[6] = {
        float3(0.5, 0.02, 0.05), float3(0.5, 0.3, 0.0),  float3(0.0, 0.4, 0.1),
        float3(0.02, 0.15, 0.5), float3(0.25, 0.05, 0.5), float3(0.5, 0.0, 0.25)
    };
    return outers[idx];
}

float3 neon_pick(float seed, int channel) {
    int idx = int(seed * 4.0) % 4;
    if (channel == 0) {
        float3 cores[4] = {
            float3(1.0, 0.8, 0.9), float3(0.8, 1.0, 1.0),
            float3(1.0, 1.0, 0.8), float3(0.85, 1.0, 0.8)
        };
        return cores[idx];
    }
    if (channel == 1) {
        float3 inners[4] = {
            float3(1.0, 0.1, 0.5), float3(0.0, 0.9, 0.9),
            float3(1.0, 0.9, 0.0), float3(0.3, 1.0, 0.1)
        };
        return inners[idx];
    }
    float3 outers[4] = {
        float3(0.5, 0.0, 0.25), float3(0.0, 0.35, 0.4),
        float3(0.45, 0.35, 0.0), float3(0.1, 0.4, 0.0)
    };
    return outers[idx];
}

float3 aurora_pick(float seed, int channel) {
    int idx = int(seed * 3.0) % 3;
    if (channel == 0) {
        float3 cores[3] = {
            float3(0.8, 1.0, 0.85), float3(0.9, 0.8, 1.0), float3(0.8, 0.9, 1.0)
        };
        return cores[idx];
    }
    if (channel == 1) {
        float3 inners[3] = {
            float3(0.1, 0.85, 0.4), float3(0.55, 0.15, 0.85), float3(0.15, 0.45, 0.9)
        };
        return inners[idx];
    }
    float3 outers[3] = {
        float3(0.02, 0.35, 0.12), float3(0.2, 0.03, 0.4), float3(0.03, 0.12, 0.35)
    };
    return outers[idx];
}

// --- Main palette functions (seed used for multicolor modes) ---

float3 bolt_core(int scheme, float seed) {
    switch (scheme) {
        case 1:  return float3(1.0, 0.85, 0.95);
        case 2:  return float3(0.75, 1.0, 0.80);
        case 3:  return float3(1.0, 0.95, 0.80);
        case 4:  return float3(0.85, 0.95, 1.0);
        case 5:  return rainbow_pick(seed, 0);
        case 6:  return neon_pick(seed, 0);
        case 7:  return aurora_pick(seed, 0);
        default: return float3(0.90, 0.93, 1.0);
    }
}

float3 bolt_inner(int scheme, float seed) {
    switch (scheme) {
        case 1:  return float3(0.85, 0.15, 0.65);
        case 2:  return float3(0.1, 0.8, 0.3);
        case 3:  return float3(0.9, 0.45, 0.1);
        case 4:  return float3(0.2, 0.65, 0.95);
        case 5:  return rainbow_pick(seed, 1);
        case 6:  return neon_pick(seed, 1);
        case 7:  return aurora_pick(seed, 1);
        default: return float3(0.35, 0.6, 0.95);
    }
}

float3 bolt_outer(int scheme, float seed) {
    switch (scheme) {
        case 1:  return float3(0.45, 0.05, 0.7);
        case 2:  return float3(0.0, 0.35, 0.1);
        case 3:  return float3(0.6, 0.1, 0.0);
        case 4:  return float3(0.05, 0.25, 0.5);
        case 5:  return rainbow_pick(seed, 2);
        case 6:  return neon_pick(seed, 2);
        case 7:  return aurora_pick(seed, 2);
        default: return float3(0.20, 0.10, 0.55);
    }
}

float3 bolt_sky(int scheme) {
    switch (scheme) {
        case 1:  return float3(0.04, 0.005, 0.03);
        case 2:  return float3(0.003, 0.015, 0.005);
        case 3:  return float3(0.015, 0.005, 0.002);
        case 4:  return float3(0.003, 0.008, 0.02);
        case 5:  return float3(0.008, 0.005, 0.012);
        case 6:  return float3(0.01, 0.003, 0.015);
        case 7:  return float3(0.003, 0.01, 0.008);
        default: return float3(0.003, 0.003, 0.012);
    }
}

float3 bolt_outer_default(int scheme) { return bolt_outer(scheme, 0.5); }
float3 bolt_inner_default(int scheme) { return bolt_inner(scheme, 0.5); }

// MARK: - Lightning Bolt

float3 bolt(float2 uv, float2 origin, float angle, float reach, float seed,
            float energy) {
    
    float coreW  = 0.0014 + energy * 0.001;
    float innerW = 0.006  + energy * 0.007;
    float outerW = 0.024  + energy * 0.030;
    
    int segments = 6 + int(reach * 8.0);
    segments = min(segments, 20);
    float segLen = reach / float(segments);
    
    float3 accum = float3(0.0);
    float2 prev = origin;
    float sa = sin(angle), ca = cos(angle);
    
    for (int i = 1; i <= segments; i++) {
        float t = float(i) / float(segments);
        float segSeed = elec_hash(float2(seed * 73.0, float(i) * 17.3));
        
        float lateralScale = 0.16 * sin(t * 3.14159);
        lateralScale += 0.05 * sin(t * 6.28318 + seed * 5.0);
        float lateral = (segSeed - 0.5) * lateralScale;
        
        float dx = sa * segLen + lateral * ca;
        float dy = -ca * segLen + lateral * sa;
        
        float2 curr = prev + float2(dx, dy);
        float d = seg_dist(uv, prev, curr);
        
        float taper = smoothstep(1.0, 0.75, t);
        
        accum.x += exp(-d * d / (coreW  * coreW))  * 0.55 * taper;
        accum.y += exp(-d * d / (innerW * innerW))  * 0.30 * taper;
        accum.z += exp(-d * d / (outerW * outerW))  * 0.15 * taper;
        
        prev = curr;
    }
    return accum;
}

/// Branch fork
float3 bolt_fork(float2 uv, float2 forkPt, float forkAngle, float forkLen,
                 float seed, float energy) {
    
    float coreW  = 0.0008 + energy * 0.0004;
    float innerW = 0.003  + energy * 0.004;
    float outerW = 0.012  + energy * 0.014;
    
    int segs = 3 + int(forkLen * 6.0);
    segs = min(segs, 8);
    float segLen = forkLen / float(segs);
    
    float3 accum = float3(0.0);
    float2 prev = forkPt;
    float sa = sin(forkAngle), ca = cos(forkAngle);
    
    for (int i = 1; i <= segs; i++) {
        float t = float(i) / float(segs);
        float segSeed = elec_hash(float2(float(i) * 19.7, seed * 61.0));
        float lateral = (segSeed - 0.5) * 0.07 * sin(t * 3.14159);
        
        float dx = sa * segLen + lateral;
        float dy = -ca * segLen * 0.4;
        float2 curr = prev + float2(dx, dy);
        float d = seg_dist(uv, prev, curr);
        
        float fade = (1.0 - t);
        fade *= fade;
        
        accum.x += exp(-d * d / (coreW  * coreW))  * 0.25 * fade;
        accum.y += exp(-d * d / (innerW * innerW))  * 0.15 * fade;
        accum.z += exp(-d * d / (outerW * outerW))  * 0.08 * fade;
        
        prev = curr;
    }
    return accum;
}

// MARK: - Lightning Burst (varied decay per bolt)

float3 lightning_burst(float2 uv, float2 origin, float burstSeed,
                       float energy, float aspect, float time, int cs) {
    
    float3 total = float3(0.0);
    
    // Energy gate — higher threshold, less activity overall
    float gate = smoothstep(0.18, 0.45, energy);
    if (gate < 0.01) return total;
    
    // 1-2 bolts max — keep it sparse
    int boltCount = 1 + int(energy * 1.2);
    boltCount = min(boltCount, 2);
    
    float fanSpread = 0.12 + energy * 0.35;
    
    for (int i = 0; i < boltCount; i++) {
        float fi = float(i);
        
        // === VARIED DECAY: each bolt has its own epoch rate ===
        // Slower rates — bolts cycle every ~2s to ~5s
        float boltRate = 0.2 + elec_hash(float2(burstSeed * 17.0 + fi * 41.0, fi * 7.3)) * 0.35;
        // boltRate ranges 0.2 to 0.55 → periods of ~1.8s to ~5s
        
        float epoch = floor(time * boltRate + burstSeed * 50.0 + fi * 13.7);
        float phase = fract(time * boltRate + burstSeed * 50.0 + fi * 13.7);
        
        // Each bolt also has its own decay speed
        float decaySpeed = 1.2 + elec_hash(float2(epoch + fi * 31.0, burstSeed * 53.0)) * 2.5;
        // decaySpeed 1.2 to 3.7 → longer lingering overall
        float flashEnvelope = exp(-phase * decaySpeed);
        
        flashEnvelope *= gate;
        if (flashEnvelope < 0.02) continue;
        
        // Seed from epoch so shape is stable within each bolt's own cycle
        float bSeed = elec_hash(float2(epoch + fi * 41.3, burstSeed * 67.0 + fi));
        
        // Fan angle
        float baseAngle;
        if (boltCount <= 1) {
            baseAngle = (bSeed - 0.5) * 0.25;
        } else {
            baseAngle = (fi / float(boltCount - 1) - 0.5) * 2.0 * fanSpread;
        }
        float jitter = (elec_hash(float2(bSeed * 31.0, fi * 13.0)) - 0.5) * 0.1;
        float angle = baseAngle + jitter;
        
        // Reach: wide variation, energy-scaled
        float reachRng = elec_hash(float2(epoch + fi * 23.7, burstSeed * 89.0));
        float reach;
        if (i == 0) {
            reach = 0.15 + reachRng * 0.35 + energy * 1.5;
        } else {
            float classRng = elec_hash(float2(epoch + fi * 67.1, burstSeed * 37.0));
            if (classRng < 0.35) {
                reach = 0.08 + reachRng * 0.15 + energy * 0.2;
            } else if (classRng < 0.65) {
                reach = 0.12 + reachRng * 0.25 + energy * 0.5;
            } else {
                reach = 0.2 + reachRng * 0.35 + energy * 1.0;
            }
        }
        
        float intensity = (i == 0) ? 1.0 : (0.25 + bSeed * 0.3);
        intensity *= smoothstep(0.10, 0.40, energy);
        
        // When reach is large, make the bolt itself thicker
        float reachBoost = smoothstep(0.8, 1.5, reach);
        float3 b = bolt(uv, origin, angle, reach, bSeed, energy + reachBoost * 0.3);
        float bScale = intensity * flashEnvelope * (1.0 + reachBoost * 0.5);
        // Color this bolt using its seed (multicolor modes pick per-bolt)
        float colorSeed = elec_hash(float2(bSeed * 97.0, burstSeed * 13.0 + fi));
        total += (b.x * bolt_core(cs, colorSeed) * 1.8
                + b.y * bolt_inner(cs, colorSeed) * 1.3
                + b.z * bolt_outer(cs, colorSeed) * 0.8) * bScale;
        
        // Branch structure scales with reach — big bolts get big branch trees
        // Branches cluster in the bottom 1/3 where the bolt splays out
        if (i == 0 && flashEnvelope > 0.15) {
            // Number of branches: 0 for short bolts, up to 6 for massive ones
            int branchCount = int(reach * 3.0);
            branchCount = clamp(branchCount, 0, 6);
            
            for (int f = 0; f < branchCount; f++) {
                float ff = float(f);
                float fSeed = elec_hash(float2(epoch + ff * 53.0, bSeed * 79.0 + ff));
                
                // Place branches: a couple along the upper part,
                // then cluster heavily in the bottom 1/3
                float forkT;
                if (f < 2) {
                    // First 1-2 branches: spread along upper 2/3
                    forkT = 0.15 + ff * 0.25 + fSeed * 0.1;
                } else {
                    // Rest: packed into the bottom 1/3 (forkT 0.67-0.95)
                    forkT = 0.67 + (ff - 2.0) * 0.07 + fSeed * 0.06;
                }
                forkT = min(forkT, 0.95);
                
                float forkY = origin.y - cos(angle) * reach * forkT;
                float forkX = origin.x + sin(angle) * reach * forkT;
                forkX += (elec_hash(float2(bSeed * 73.0, forkT * 17.3)) - 0.5) * 0.07;
                
                // Alternate sides
                float side = (f % 2 == 0) ? 1.0 : -1.0;
                float forkDir = side * (0.4 + fSeed * 0.7);
                
                // Bottom branches are longer — the splay-out effect
                float bottomBoost = smoothstep(0.5, 0.85, forkT);
                float forkLen = (0.04 + fSeed * 0.08 + reach * 0.06)
                              * (1.0 + bottomBoost * 1.2);  // up to 2.2x longer at bottom
                float branchFade = 0.5 - ff * 0.04;
                
                float3 fb = bolt_fork(uv, float2(forkX, forkY), forkDir, forkLen,
                                      fSeed + ff, energy);
                float fbScale = branchFade * flashEnvelope;
                total += (fb.x * bolt_core(cs, colorSeed) * 1.8
                        + fb.y * bolt_inner(cs, colorSeed) * 1.3
                        + fb.z * bolt_outer(cs, colorSeed) * 0.8) * fbScale;
                
                // Sub-branches on bottom-third branches of big bolts
                if (forkT > 0.6 && reach > 0.8) {
                    float subSeed = elec_hash(float2(fSeed * 37.0, epoch + ff * 19.0));
                    float subForkT = 0.35 + subSeed * 0.3;
                    float subX = forkX + sin(forkDir) * forkLen * subForkT;
                    float subY = forkY - cos(forkDir) * forkLen * subForkT * 0.4;
                    float subDir = forkDir + (subSeed > 0.5 ? 0.3 : -0.3);
                    float subLen = forkLen * 0.55;
                    
                    float3 sb = bolt_fork(uv, float2(subX, subY), subDir, subLen,
                                          subSeed, energy);
                    total += (sb.x * bolt_core(cs, colorSeed) * 1.8
                            + sb.y * bolt_inner(cs, colorSeed) * 1.3
                            + sb.z * bolt_outer(cs, colorSeed) * 0.8) * 0.25 * flashEnvelope;
                    
                    if (reach > 1.2 && f < 4) {
                        float ter = elec_hash(float2(subSeed * 43.0, epoch + ff * 7.0));
                        float terX = subX + sin(subDir) * subLen * 0.5;
                        float terY = subY - cos(subDir) * subLen * 0.2;
                        float terDir = subDir + (ter - 0.5) * 0.5;
                        float3 tb = bolt_fork(uv, float2(terX, terY), terDir, subLen * 0.4,
                                              ter, energy);
                        total += (tb.x * bolt_core(cs, colorSeed) * 1.8
                                + tb.y * bolt_inner(cs, colorSeed) * 1.3
                                + tb.z * bolt_outer(cs, colorSeed) * 0.8) * 0.12 * flashEnvelope;
                    }
                }
            }
        }
    }
    
    return total;
}

// MARK: - Dramatic Strike (rare, JWST-style)

/// A massive bolt that dominates the screen and fades over seconds.
/// Explodes with thick, visible branches — uses full `bolt()` for major
/// branches so they're as visible as the trunk, not thin `bolt_fork()`.
float3 dramatic_strike(float2 uv, float aspect, float time, float intensity, int cs) {
    if (intensity < 0.02) return float3(0.0);
    
    float strikeSeed = elec_hash(float2(floor(time * 0.08) * 7.1, 42.0));
    
    float3 total = float3(0.0);
    
    // Main trunk bolt
    float mainAngle = (strikeSeed - 0.5) * 0.4;
    float originX = (elec_hash(float2(strikeSeed * 31.0, 17.0)) - 0.5) * aspect * 0.6;
    float2 origin = float2(originX, 0.5);
    float mainReach = 1.2 + strikeSeed * 0.6;
    
    // Color seed for the dramatic strike (trunk + all branches same color)
    float dColorSeed = elec_hash(float2(strikeSeed * 97.0, 42.0));
    
    // Helper lambda-style: color a glow triple
    #define COLOR_BOLT(g, s) ((g).x * bolt_core(cs, s) * 1.8 \
                            + (g).y * bolt_inner(cs, s) * 1.3 \
                            + (g).z * bolt_outer(cs, s) * 0.8)
    
    // Main trunk
    float3 trunk = bolt(uv, origin, mainAngle, mainReach, strikeSeed, 0.8 + intensity * 0.2);
    total += COLOR_BOLT(trunk, dColorSeed);
    
    float mainSa = sin(mainAngle), mainCa = cos(mainAngle);
    
    // === BRANCH EXPLOSION ===
    for (int f = 0; f < 7; f++) {
        float ff = float(f);
        float fSeed = elec_hash(float2(strikeSeed * 47.0 + ff * 31.0, ff * 13.0));
        // Each branch can get its own color in multicolor modes
        float branchColorSeed = elec_hash(float2(dColorSeed * 61.0 + ff * 17.0, strikeSeed));
        
        float forkT;
        if (f < 2) {
            forkT = 0.2 + ff * 0.2 + fSeed * 0.08;
        } else {
            forkT = 0.6 + (ff - 2.0) * 0.07 + fSeed * 0.04;
        }
        forkT = min(forkT, 0.93);
        
        float forkY = origin.y - mainCa * mainReach * forkT;
        float forkX = origin.x + mainSa * mainReach * forkT;
        forkX += (elec_hash(float2(strikeSeed * 73.0, forkT * 17.3)) - 0.5) * 0.09;
        float2 branchOrigin = float2(forkX, forkY);
        
        float side = (f % 2 == 0) ? 1.0 : -1.0;
        float branchAngle = mainAngle + side * (0.5 + fSeed * 0.8);
        
        float bottomBoost = smoothstep(0.45, 0.8, forkT);
        float branchReach = (0.10 + fSeed * 0.15 + bottomBoost * 0.25);
        float branchBright = 0.7 - ff * 0.04;
        
        float3 mb = bolt(uv, branchOrigin, branchAngle, branchReach,
                         fSeed + strikeSeed, 0.6);
        total += COLOR_BOLT(mb, branchColorSeed) * branchBright;
        
        if (forkT > 0.5) {
            for (int s = 0; s < 2; s++) {
                float ss = float(s);
                float subSeed = elec_hash(float2(fSeed * 37.0 + ss * 29.0, strikeSeed + ff * 19.0));
                float subT = 0.3 + subSeed * 0.4;
                float subX = branchOrigin.x + sin(branchAngle) * branchReach * subT;
                float subY = branchOrigin.y - cos(branchAngle) * branchReach * subT;
                float subDir = branchAngle + (s == 0 ? 0.4 : -0.4) + (subSeed - 0.5) * 0.3;
                float subLen = branchReach * (0.4 + subSeed * 0.3);
                
                float3 sb = bolt_fork(uv, float2(subX, subY), subDir, subLen,
                                      subSeed, 0.7);
                total += COLOR_BOLT(sb, branchColorSeed) * branchBright * 0.5;
            }
        }
    }
    
    #undef COLOR_BOLT
    
    return total * intensity;
}

// MARK: - Shaders

vertex float4 electricity_vertex(uint vertexID [[vertex_id]]) {
    float2 positions[6] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1),
        float2(-1, 1),  float2(1, -1), float2(1, 1)
    };
    return float4(positions[vertexID], 0, 1);
}

fragment float4 electricity_fragment(
    float4 position [[position]],
    constant ElectricityParams& params [[buffer(0)]],
    constant float* spectrum [[buffer(1)]]
) {
    float2 uv = position.xy / params.viewportSize;
    uv.y = 1.0 - uv.y;
    float aspect = params.viewportSize.x / params.viewportSize.y;
    float2 centered = (uv - 0.5) * float2(aspect, 1.0);
    
    float t      = params.time;
    float energy = params.totalEnergy;
    float beat   = params.beatIntensity;
    float dramatic = params.dramaticIntensity;
    int cs       = params.colorScheme;
    
    // ================================================================
    // STORM ATMOSPHERE
    // ================================================================
    
    float3 skyBase = bolt_sky(cs);
    float3 color = skyBase;
    
    float clouds = elec_fbm(float2(centered.x * 1.2 + t * 0.008,
                                    centered.y * 1.8 + t * 0.005), 3);
    float heightGrad = smoothstep(-0.5, 0.5, centered.y);
    // Cloud tint uses the outer color for atmospheric glow
    float3 cloudTint = bolt_outer_default(cs) * 0.08;
    color += cloudTint * clouds * heightGrad * smoothstep(0.05, 0.25, energy);
    color += cloudTint * 1.5 * energy * clouds * heightGrad;
    
    // ================================================================
    // LIGHTNING BURSTS (suppressed during dramatic strike)
    // ================================================================
    
    float dramaticSuppress = 1.0 - smoothstep(0.0, 0.1, dramatic);
    
    int peakBands[2] = {-1, -1};
    float peakVals[2] = {0, 0};
    float peakThreshold = max(0.18, 0.45 - energy * 0.5);
    
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
    
    float3 totalBolt = float3(0.0);
    
    for (int pi = 0; pi < 2; pi++) {
        if (peakBands[pi] < 0) continue;
        
        float peakVal = peakVals[pi];
        float bandNorm = float(peakBands[pi]) / 74.0;
        
        float originX = (bandNorm - 0.5) * aspect * 0.85;
        float2 origin = float2(originX, 0.5);
        
        float burstSeed = float(peakBands[pi]) * 0.137 + float(pi) * 3.7;
        float burstEnergy = clamp(peakVal * 1.5, 0.0, 1.0);
        float rankScale = (pi == 0) ? 1.0 : 0.35;
        
        float3 burst = lightning_burst(centered, origin, burstSeed,
                                       burstEnergy, aspect, t, cs);
        totalBolt += burst * rankScale * dramaticSuppress;
    }
    
    // ================================================================
    // DRAMATIC STRIKE — rare, massive, slow-fading
    // ================================================================
    
    float3 dramaticBolt = dramatic_strike(centered, aspect, t, dramatic, cs);
    totalBolt += dramaticBolt;
    
    // Bolts are already colored — add directly
    color += totalBolt;
    
    // ================================================================
    // SKY ILLUMINATION — clouds glow from lightning (tinted by palette)
    // ================================================================
    
    float boltBrightness = clamp(length(totalBolt), 0.0, 1.0);
    float3 skyGlowColor = mix(bolt_outer_default(cs), bolt_inner_default(cs), 0.3) * 0.15;
    color += skyGlowColor * boltBrightness * clouds;
    
    // Extra dramatic sky glow
    if (dramatic > 0.05) {
        float skyGlow = dramatic * 0.15 * clouds;
        color += mix(bolt_outer_default(cs), bolt_inner_default(cs), 0.5) * 0.2 * skyGlow;
    }
    
    // ================================================================
    // GROUND GLOW
    // ================================================================
    
    float groundGlow = exp(-(centered.y + 0.48) * (centered.y + 0.48) / 0.012)
                     * boltBrightness * 0.15;
    color += groundGlow * mix(bolt_outer_default(cs), bolt_inner_default(cs), 0.3);
    
    // ================================================================
    // POST-PROCESSING
    // ================================================================
    
    color *= 1.0 + beat * 0.04;
    
    float3 lum = float3(dot(color, float3(0.299, 0.587, 0.114)));
    color = mix(lum, color, 1.05 + energy * 0.15);
    
    float2 vig = (uv - 0.5) * 2.0;
    color *= 1.0 - dot(vig, vig) * 0.18;
    
    // Brightness boost (for small embedded views)
    color *= params.brightnessBoost;

    color = color / (color + 0.55);
    color = pow(max(color, 0.0), float3(0.92));
    
    return float4(color, 1.0);
}
