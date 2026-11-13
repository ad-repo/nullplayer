/// NullPlayer-Fractal's GLSL: the shared scene header (uniforms, palette, raymarch helpers) that
/// every `FractalScene` body is appended to, and the feedback and present passes.
enum FractalShaders {
    /// A full-screen triangle from `gl_VertexID`; drawn with an empty VAO.
    static let vertex = """
    #version 330 core
    void main() {
        vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
        gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
    }
    """

    /// A scene's whole fragment shader. The body defines `vec4 scene(vec2 frag)`: HDR colour, and
    /// alpha as solidity (1 replaces the trails, 0 adds over them as glow). A raymarched body also
    /// defines `float de(vec3 p, out vec4 trap)`.
    static func fragment(for scene: FractalScene) -> String {
        common + (scene.kind == .raymarched ? raymarch : "") + scene.body
    }

    private static let common = """
    #version 330 core
    out vec4 fragColor;
    uniform vec2 u_res;
    uniform float u_time;      // seconds, wrapped (see FractalEngine)
    uniform float u_beat;      // 1 on a beat, decaying
    uniform float u_beatTime;  // beats at the tempo, wrapped at 4096 (every period used divides it)
    uniform float u_bar;
    uniform vec3 u_bands;      // bass, mid, treble, smoothed, 0..1
    uniform vec3 u_fast;       // the same, fast
    uniform vec4 u_p;          // the scene's eased parameters
    uniform vec3 u_pa, u_pb, u_pc, u_pd;
    uniform int u_steps;
    const float TAU = 6.28318530718;
    vec3 palette(float t) { return u_pa + u_pb * cos(TAU * (u_pc * t + u_pd)); }
    mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, s, -s, c); }
    float hash1(float n) { return fract(sin(n * 91.345 + 47.853) * 43758.5453); }
    // The camera's shot: a new seed every 64 beats (16 bars), so it cuts to a new path on the
    // phrase and the trails smear the cut. `salt` gives independent draws.
    float shotSeed(float salt) { return hash1(floor(u_beatTime / 64.0) * 1.618 + salt); }
    // Beats into the current shot.
    float shotTime() { return mod(u_beatTime, 64.0); }
    // A smooth wandering path, roughly in [-1, 1]^3, different for every seed.
    vec3 wander(float t, float seed) {
        return (sin(t * vec3(0.31, 0.27, 0.23) + seed * vec3(61.0, 43.0, 79.0))
              + 0.5 * sin(t * vec3(0.73, 0.61, 0.83) + seed * vec3(37.0, 92.0, 23.0))) / 1.5;
    }
    // A 2D shot: zoom (1 is the scene's own framing) and pan towards a fresh part of the plane.
    vec2 explore2D(vec2 uv, float minZoom) {
        float seed = shotSeed(3.0);
        float zoom = mix(minZoom, 1.0, hash1(seed * 5.0));
        vec2 pan = (vec2(hash1(seed * 7.0), hash1(seed * 11.0)) - 0.5) * 1.4 * (1.0 - zoom)
                 + 0.2 * wander(shotTime() * 0.06, seed).xy * zoom;
        return uv * zoom + pan;
    }
    vec4 scene(vec2 frag);
    void main() { fragColor = scene(gl_FragCoord.xy); }

    """

    private static let raymarch = """
    float de(vec3 p, out vec4 trap);
    struct Hit { float t; float steps; vec4 trap; bool hit; };

    Hit march(vec3 ro, vec3 rd, float maxT) {
        Hit h; h.t = 0.0; h.hit = false; h.trap = vec4(0.0);
        float pixel = 1.0 / u_res.y;
        int i;
        for (i = 0; i < u_steps; i++) {
            float d = de(ro + rd * h.t, h.trap);
            if (d < pixel * h.t) { h.hit = true; break; }
            h.t += d * 0.9;
            if (h.t > maxT) break;
        }
        h.steps = float(i) / float(u_steps);
        return h;
    }

    vec3 normalAt(vec3 p, float e) {
        vec4 t; vec2 k = vec2(1.0, -1.0);
        return normalize(k.xyy * de(p + k.xyy * e, t) + k.yyx * de(p + k.yyx * e, t)
                       + k.yxy * de(p + k.yxy * e, t) + k.xxx * de(p + k.xxx * e, t));
    }

    // `zoom` is the lens (focal length over half the height), `roll` turns the frame.
    vec3 cameraRay(vec2 frag, vec3 ro, vec3 target, float zoom, float roll) {
        vec2 uv = rot(roll) * (frag - 0.5 * u_res) / u_res.y;
        vec3 f = normalize(target - ro);
        vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), f));
        vec3 u = cross(f, r);
        return normalize(uv.x * r + uv.y * u + zoom * f);
    }

    // Pushes a camera out of the surface until it has `clearance` (every pixel computes the
    // same answer), so a roaming camera never ends up inside the object.
    vec3 keepClear(vec3 ro, float clearance) {
        vec4 t;
        for (int i = 0; i < 5; i++) {
            float d = de(ro, t);
            if (d >= clearance) break;
            ro += normalAt(ro, 0.5 * clearance) * (clearance - d);
        }
        return ro;
    }

    struct Cam { vec3 ro; vec3 ta; float zoom; float roll; };

    // Roams round an object at the origin. Each shot draws its own speed, lens and roll; within
    // it the distance swings from `near` (skimming the surface) to `far`, the direction drifts
    // over the sphere, and the aim wanders `spread` across the object.
    Cam orbitShot(float near, float far, float spread) {
        float seed = shotSeed(0.0);
        float t = shotTime();
        // Slow on purpose: a fast orbit close in whips the surface past and makes viewers queasy.
        float pace = mix(0.02, 0.05, hash1(seed * 13.0)) * (hash1(seed * 17.0) < 0.5 ? -1.0 : 1.0);
        float az = seed * TAU + pace * t;
        float el = 1.0 * sin(t * 0.03 + seed * 9.0);
        float r = mix(near, far, 0.5 + 0.5 * cos(t * TAU / 64.0 + seed * 5.0));
        Cam c;
        c.ro = r * vec3(cos(el) * cos(az), sin(el), cos(el) * sin(az));
        c.ta = wander(t * 0.04 + 20.0, seed + 0.5) * spread;
        c.zoom = mix(1.0, 2.1, hash1(seed * 7.0)) + 0.03 * u_beat;
        c.roll = (hash1(seed * 3.0) - 0.5) * 0.6 + 0.15 * sin(t * 0.03);
        return c;
    }

    // Flies through a space-filling structure: each shot starts somewhere new within `extent`,
    // heads its own way at `speed` units a beat, sways, and looks around as it goes.
    Cam flightShot(float extent, float speed) {
        float seed = shotSeed(1.0);
        vec3 dir = normalize(vec3(hash1(seed * 3.0), hash1(seed * 5.0), hash1(seed * 7.0)) - 0.5 + vec3(0.0, 0.0, 1e-3));
        float t = shotTime() * speed * mix(0.7, 1.3, hash1(seed * 11.0));
        Cam c;
        c.ro = (vec3(hash1(seed * 13.0), hash1(seed * 17.0), hash1(seed * 19.0)) - 0.5) * 2.0 * extent
             + dir * t + 0.2 * wander(t, seed);
        c.ta = c.ro + dir + 0.5 * wander(t * 0.8 + 9.0, seed + 0.3);
        c.zoom = mix(0.8, 1.5, hash1(seed * 23.0)) + 0.02 * u_beat;
        c.roll = (hash1(seed * 29.0) - 0.5) * 0.8 + 0.2 * sin(t * 0.3);
        return c;
    }

    // Lit surface in `colour`, darkened by the step count (cheap AO); a miss glows by how many
    // steps it took, which is how close it passed.
    vec4 shade(Hit h, vec3 ro, vec3 rd, vec3 colour) {
        vec3 glow = palette(0.6 + 0.3 * u_bands.z) * h.steps * h.steps * (0.35 + 0.8 * u_beat);
        if (!h.hit) return vec4(glow, 0.0);
        vec3 p = ro + rd * h.t;
        vec3 n = normalAt(p, max(h.t / u_res.y, 1e-4));
        vec3 l = normalize(vec3(0.6, 0.8, -0.4));
        float dif = max(dot(n, l), 0.0);
        float head = max(dot(n, -rd), 0.0);  // a headlight, so a roaming camera's view is lit
        float spe = pow(max(dot(reflect(rd, n), l), 0.0), 24.0);
        float rim = pow(1.0 - head, 3.0);
        float ao = 1.0 - h.steps;
        vec3 c = colour * (0.12 + 0.5 * dif + 0.45 * head) * ao + spe * 0.6 + rim * palette(u_bar * 0.25) * 0.7;
        return vec4(c * (1.0 + 0.5 * u_beat) + glow * 0.3, 1.0);
    }

    """

    /// Warps the previous frame (zoom, rotate, swirl), decays and hue-rotates it, and lays the
    /// scene over it: the trails.
    static let feedback = """
    #version 330 core
    out vec4 fragColor;
    uniform sampler2D u_prev;
    uniform sampler2D u_scene;
    uniform vec2 u_res;
    uniform float u_decay, u_zoom, u_rot, u_swirl, u_hue, u_fade;
    vec3 hueRotate(vec3 v, float a) {
        vec3 k = vec3(0.57735);
        float c = cos(a);
        return v * c + cross(k, v) * sin(a) + k * dot(k, v) * (1.0 - c);
    }
    void main() {
        vec2 uv = gl_FragCoord.xy / u_res;
        vec2 aspect = vec2(u_res.x / u_res.y, 1.0);
        vec2 p = (uv - 0.5) * aspect;
        float a = u_rot + u_swirl * length(p);
        p = mat2(cos(a), sin(a), -sin(a), cos(a)) * p * u_zoom;
        vec3 trail = max(hueRotate(textureLod(u_prev, p / aspect + 0.5, 0.0).rgb, u_hue), 0.0) * u_decay;
        vec4 s = texture(u_scene, uv);
        vec3 c = mix(trail, s.rgb, s.a * u_fade) + s.rgb * (1.0 - s.a) * u_fade;
        fragColor = vec4(min(c, vec3(32.0)), 1.0);
    }
    """

    /// Upsamples the feedback image to the viewport: bloom from its mip chain, chromatic
    /// aberration pulsed on the beat, a filmic tonemap and a vignette.
    static let present = """
    #version 330 core
    out vec4 fragColor;
    uniform sampler2D u_image;
    uniform vec2 u_res;
    uniform float u_beat;
    vec3 aces(vec3 x) { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0); }
    void main() {
        vec2 uv = gl_FragCoord.xy / u_res;
        vec2 d = uv - 0.5;
        float ca = 0.003 + 0.005 * u_beat;
        vec3 c = vec3(textureLod(u_image, uv - d * ca, 0.0).r,
                      textureLod(u_image, uv, 0.0).g,
                      textureLod(u_image, uv + d * ca, 0.0).b);
        vec3 bloom = 0.5 * textureLod(u_image, uv, 3.0).rgb + 0.5 * textureLod(u_image, uv, 5.0).rgb;
        c += max(bloom - 0.5, 0.0) * (0.7 + 0.8 * u_beat);
        c = aces(c * 1.2);
        c *= 1.0 - 0.6 * dot(d, d);
        fragColor = vec4(c, 1.0);
    }
    """
}
