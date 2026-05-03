// =============================================================================
// EKG SHADERS - Beat-Synced Electrocardiogram Visualizer
// =============================================================================
// Persistent ECG monitor. BPM controls the cardiac clock, raw PCM amplitude
// controls newly drawn peak height, and the already-drawn trace is preserved in
// a ping-pong texture so historical line segments do not refresh or rescale.
// This mode intentionally ignores frequency energy.
// =============================================================================

#include <metal_stdlib>
using namespace metal;

struct EKGParams {
    float2 viewportSize;
    float time;
    float bpm;
    float beatPhase;
    float amplitudeLevel;
    float noiseLevel;
    float scrollDelta;
    float brightnessBoost;
    int colorScheme;
    float2 padding;
};

constant float EKG_SCREEN_SECONDS = 5.6;
constant float EKG_SCAN_HEAD_X = 0.965;

float3 ekg_style_color(int scheme, int role) {
    switch (scheme) {
        case 1: // Cyan
            if (role == 0) return float3(0.080, 0.930, 0.980);
            if (role == 1) return float3(0.650, 1.000, 1.000);
            if (role == 2) return float3(0.010, 0.165, 0.175);
            if (role == 3) return float3(0.015, 0.300, 0.320);
            return float3(0.002, 0.022, 0.026);
        case 2: // Amber
            if (role == 0) return float3(1.000, 0.650, 0.120);
            if (role == 1) return float3(1.000, 0.930, 0.530);
            if (role == 2) return float3(0.170, 0.105, 0.018);
            if (role == 3) return float3(0.330, 0.190, 0.030);
            return float3(0.030, 0.017, 0.003);
        case 3: // Neon
            if (role == 0) return float3(0.980, 0.140, 0.760);
            if (role == 1) return float3(0.420, 1.000, 0.980);
            if (role == 2) return float3(0.150, 0.030, 0.130);
            if (role == 3) return float3(0.280, 0.060, 0.270);
            return float3(0.026, 0.003, 0.024);
        case 4: // Crimson
            if (role == 0) return float3(1.000, 0.145, 0.120);
            if (role == 1) return float3(1.000, 0.760, 0.560);
            if (role == 2) return float3(0.170, 0.030, 0.025);
            if (role == 3) return float3(0.330, 0.060, 0.050);
            return float3(0.030, 0.004, 0.003);
        case 5: // Ice
            if (role == 0) return float3(0.620, 0.940, 1.000);
            if (role == 1) return float3(0.930, 1.000, 1.000);
            if (role == 2) return float3(0.070, 0.130, 0.170);
            if (role == 3) return float3(0.120, 0.250, 0.330);
            return float3(0.009, 0.018, 0.026);
        default: // Clinical
            if (role == 0) return float3(0.105, 0.900, 0.400);
            if (role == 1) return float3(0.780, 1.000, 0.720);
            if (role == 2) return float3(0.005, 0.115, 0.075);
            if (role == 3) return float3(0.020, 0.240, 0.145);
            return float3(0.002, 0.026, 0.019);
    }
}

float ekg_hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float ekg_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(ekg_hash(i), ekg_hash(i + float2(1.0, 0.0)), f.x),
        mix(ekg_hash(i + float2(0.0, 1.0)), ekg_hash(i + float2(1.0, 1.0)), f.x),
        f.y
    );
}

float ekg_gaussian(float p, float center, float width) {
    float d = (p - center) / width;
    return exp(-d * d);
}

float ekg_wave_for_beat(float t, float beatTime, float beatIndex) {
    float dt = t - beatTime;
    float seed = ekg_hash(float2(beatIndex, 19.73));
    float qrsAmp = mix(0.97, 1.04, seed);
    float pAmp = mix(0.92, 1.06, ekg_hash(float2(beatIndex, 43.17)));
    float tAmp = mix(0.93, 1.07, ekg_hash(float2(beatIndex, 71.41)));

    float pWave = 0.080 * ekg_gaussian(dt, -0.180, 0.046) * pAmp;
    float qWave = -0.135 * ekg_gaussian(dt, -0.026, 0.010) * qrsAmp;
    float rWave = 1.000 * ekg_gaussian(dt, 0.000, 0.011) * qrsAmp;
    float sWave = -0.300 * ekg_gaussian(dt, 0.028, 0.014) * qrsAmp;
    float stSeg = 0.016 * smoothstep(0.052, 0.082, dt) * (1.0 - smoothstep(0.150, 0.205, dt));
    float tWave = 0.190 * ekg_gaussian(dt, 0.290, 0.086) * tAmp;
    float uWave = 0.025 * ekg_gaussian(dt, 0.505, 0.050);

    return pWave + qWave + rWave + sWave + stSeg + tWave + uWave;
}

float ekg_waveform_at_time(float t, constant EKGParams& params) {
    float bpm = clamp(params.bpm, 40.0, 100.0);
    float interval = 60.0 / bpm;
    float beatCursor = floor(t / interval);
    float loudness = mix(0.70, 1.42, smoothstep(0.02, 0.92, params.amplitudeLevel));
    float wave = 0.0;

    for (int i = -1; i <= 1; i++) {
        float beatIndex = beatCursor + float(i);
        wave += ekg_wave_for_beat(t, beatIndex * interval, beatIndex);
    }

    float nerve = (ekg_noise(float2(t * 19.0, params.time * 2.0)) - 0.5) * params.noiseLevel * 0.020;
    return wave * loudness + nerve;
}

float ekg_trace_y_for_time(float sampleTime, constant EKGParams& params) {
    float bpmNorm = clamp((params.bpm - 40.0) / 60.0, 0.0, 1.0);
    float tempoBreath = sin(sampleTime * 0.115 * 6.2831853);

    float baseline = 0.365;
    baseline += tempoBreath * 0.009;
    baseline += sin(sampleTime * 0.050 * 6.2831853) * 0.008;
    baseline += sin(sampleTime * 0.33 * 6.2831853) * 0.003;

    float amp = 0.305 + bpmNorm * 0.015;
    return clamp(baseline + ekg_waveform_at_time(sampleTime, params) * amp, 0.055, 0.945);
}

float ekg_sample_time_for_x(float x, constant EKGParams& params) {
    float history = clamp(EKG_SCAN_HEAD_X - x, 0.0, EKG_SCAN_HEAD_X) / EKG_SCAN_HEAD_X;
    return params.time - history * EKG_SCREEN_SECONDS;
}

float distance_segment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.000001), 0.0, 1.0);
    return length(pa - ba * h);
}

float ekg_grid_line(float v, float width) {
    float d = min(fract(v), 1.0 - fract(v));
    return 1.0 - smoothstep(width, width * 1.9, d);
}

vertex float4 ekg_vertex(uint vertexID [[vertex_id]]) {
    float2 positions[6] = {
        float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
        float2(-1.0, 1.0),  float2(1.0, -1.0), float2(1.0, 1.0)
    };
    return float4(positions[vertexID], 0.0, 1.0);
}

fragment float4 ekg_update_fragment(
    float4 position [[position]],
    constant EKGParams& params [[buffer(0)]],
    texture2d<float> previousTrace [[texture(0)]]
) {
    constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_zero);
    float2 screenUV = position.xy / params.viewportSize;
    float2 uv = float2(screenUV.x, 1.0 - screenUV.y);

    float4 previous = previousTrace.sample(s, float2(screenUV.x + params.scrollDelta, screenUV.y));
    previous *= 0.997;

    float minDim = min(params.viewportSize.x, params.viewportSize.y);
    float aspect = params.viewportSize.x / max(params.viewportSize.y, 1.0);
    float2 p = float2(uv.x * aspect, uv.y);
    float pixelX = 1.0 / max(params.viewportSize.x, 1.0);

    float drawBand = max(params.scrollDelta * 3.5, pixelX * 5.0);
    float inHeadBand = smoothstep(EKG_SCAN_HEAD_X - drawBand, EKG_SCAN_HEAD_X - drawBand * 0.35, uv.x);
    inHeadBand *= 1.0 - smoothstep(EKG_SCAN_HEAD_X, EKG_SCAN_HEAD_X + pixelX * 2.0, uv.x);

    float minD = 10.0;
    for (int i = -6; i <= 2; i++) {
        float x0 = clamp(uv.x + float(i) * pixelX * 1.70, EKG_SCAN_HEAD_X - drawBand * 1.35, EKG_SCAN_HEAD_X);
        float x1 = clamp(x0 + pixelX * 2.25, EKG_SCAN_HEAD_X - drawBand * 1.35, EKG_SCAN_HEAD_X);
        float t0 = ekg_sample_time_for_x(x0, params);
        float t1 = ekg_sample_time_for_x(x1, params);
        float y0 = ekg_trace_y_for_time(t0, params);
        float y1 = ekg_trace_y_for_time(t1, params);
        minD = min(minD, distance_segment(p, float2(x0 * aspect, y0), float2(x1 * aspect, y1)));
    }

    float phaseDistance = min(params.beatPhase, 1.0 - params.beatPhase);
    float qrsFlash = exp(-pow(phaseDistance / 0.055, 2.0));
    float livePulse = clamp(qrsFlash * 1.10, 0.0, 1.25);
    float lineWidth = (1.05 + livePulse * 0.62) / max(minDim, 1.0);
    float aa = 1.35 / max(minDim, 1.0);
    float line = (1.0 - smoothstep(lineWidth, lineWidth + aa, minD)) * inHeadBand;
    float nearGlow = exp(-minD * minDim * 0.50) * (0.42 + livePulse * 0.55) * inHeadBand;
    float farGlow = exp(-minD * minDim * 0.105) * (0.13 + livePulse * 0.18) * inHeadBand;

    float3 baseTrace = ekg_style_color(params.colorScheme, 0);
    float3 hotTrace = ekg_style_color(params.colorScheme, 1);
    float3 traceCore = mix(baseTrace, hotTrace, livePulse * 0.48);
    float3 current = traceCore * line * (1.22 + livePulse * 0.80);
    current += baseTrace * nearGlow * 0.95;
    current += baseTrace * farGlow * 0.48;

    return max(previous, float4(current, max(line, nearGlow * 0.42)));
}

fragment float4 ekg_composite_fragment(
    float4 position [[position]],
    constant EKGParams& params [[buffer(0)]],
    texture2d<float> traceTexture [[texture(0)]]
) {
    constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_zero);
    float2 screenUV = position.xy / params.viewportSize;
    float2 uv = float2(screenUV.x, 1.0 - screenUV.y);
    float2 centered = uv - 0.5;

    float scanline = 0.965 + 0.035 * sin(position.y * 3.14159265);
    float vignette = 1.0 - dot(centered, centered) * 0.88;
    float3 backgroundColor = ekg_style_color(params.colorScheme, 4);
    float3 minorColor = ekg_style_color(params.colorScheme, 2);
    float3 majorColor = ekg_style_color(params.colorScheme, 3);
    float3 traceColor = ekg_style_color(params.colorScheme, 0);
    float3 hotTrace = ekg_style_color(params.colorScheme, 1);

    float3 color = backgroundColor * scanline;
    color *= clamp(vignette, 0.36, 1.0);

    float majorX = ekg_grid_line(uv.x * 10.0, 0.010);
    float majorY = ekg_grid_line(uv.y * 8.0, 0.010);
    float minorX = ekg_grid_line(uv.x * 50.0, 0.008);
    float minorY = ekg_grid_line(uv.y * 40.0, 0.008);
    float minorGrid = max(minorX, minorY);
    float majorGrid = max(majorX, majorY);
    color += minorColor * minorGrid * 0.34;
    color += majorColor * majorGrid * 0.42;

    float slowNoise = ekg_noise(uv * float2(70.0, 38.0) + float2(params.time * 0.35, -params.time * 0.25));
    color += (slowNoise - 0.5) * params.noiseLevel * minorColor * 0.38;

    float4 trace = traceTexture.sample(s, screenUV);
    color += trace.rgb;

    float minDim = min(params.viewportSize.x, params.viewportSize.y);
    float phaseDistance = min(params.beatPhase, 1.0 - params.beatPhase);
    float qrsFlash = exp(-pow(phaseDistance / 0.055, 2.0));
    float livePulse = clamp(qrsFlash * 1.10, 0.0, 1.25);

    float scanX = EKG_SCAN_HEAD_X;
    float beam = 1.0 - smoothstep(0.0, 0.024 + livePulse * 0.018, abs(uv.x - scanX));
    float headY = ekg_trace_y_for_time(params.time, params);
    float headD = length((uv - float2(scanX, headY)) * float2(params.viewportSize.x / max(params.viewportSize.y, 1.0), 1.0));
    float head = exp(-headD * minDim * 0.052);
    color += traceColor * beam * 0.24;
    color += hotTrace * head * (0.62 + livePulse * 0.74);

    float floorReflection = (1.0 - smoothstep(0.03, 0.36, uv.y)) * trace.a * 0.16;
    color += traceColor * floorReflection * 0.55;

    float exposure = 0.98 + params.brightnessBoost * 0.24 + livePulse * 0.08;
    color = 1.0 - exp(-color * exposure);
    return float4(saturate(color), 1.0);
}
