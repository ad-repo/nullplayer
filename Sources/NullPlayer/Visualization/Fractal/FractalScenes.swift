/// One NullPlayer-Fractal scene (a preset): a GLSL body over `FractalShaders`' header, its eased
/// parameters' ranges (`u_p`, retargeted every bar by `FractalDirector`) and how it feeds back.
struct FractalScene {
    enum Kind { case flat, raymarched }

    let name: String
    let kind: Kind
    let params: [ClosedRange<Float>]
    /// Raymarch step cap (`u_steps`); unused by flat scenes.
    let steps: Int32
    /// How much of the previous frame survives each frame, and how hard the trails swirl.
    let trail: Float
    let swirl: Float
    let body: String
    /// Extra zoom on the trails each frame, so they stream outward with a scene moving forward.
    var push: Float = 0
}

enum FractalScenes {
    static let all: [FractalScene] = [
        juliaBloom, mandelbrotDive, kaleidoIFS, newtonRoots,
        mandelbulb, mandelboxFlight, apollonianTunnel, mengerDive, pseudoKleinian, quaternionJulia,
        fractalPlanet,
    ]

    /// `c` rides the Mandelbrot cardioid's edge, once round every 256 beats, nudged by an eased
    /// offset. u_p: x orbit angle, y zoom, z spin, w palette offset.
    static let juliaBloom = FractalScene(
        name: "Julia Bloom", kind: .flat,
        params: [0...1.2, 0.8...1.4, -1...1, 0...1],
        steps: 0, trail: 0.8, swirl: 0.04,
        body: """
        vec4 scene(vec2 frag) {
            vec2 uv = explore2D((frag - 0.5 * u_res) / u_res.y, 0.3);
            uv = rot(u_pBeats.z * TAU / 256.0) * uv * 2.8 * u_p.y / (1.0 + 0.04 * u_beat);
            float th = u_p.x + u_beatTime * TAU / 256.0;
            vec2 e = vec2(cos(th), sin(th));
            vec2 c = (0.5 * e - 0.25 * vec2(e.x * e.x - e.y * e.y, 2.0 * e.x * e.y)) * (0.985 + 0.03 * u_fast.x);
            vec2 z = uv;
            float trap = 1e9;
            float i;
            const float N = 220.0;
            for (i = 0.0; i < N; i++) {
                z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
                trap = min(trap, abs(length(z) - 0.4 - 0.4 * u_fast.y));
                if (dot(z, z) > 256.0) break;
            }
            if (i >= N) return vec4(palette(trap * 3.0 + u_p.w + 0.5) * 0.35 * exp(-trap * 4.0), 0.9);
            float t = (i - log2(log2(dot(z, z))) + 4.0) / 40.0;
            float edge = pow(clamp(t * 1.6, 0.0, 1.0), 2.0);
            vec3 col = palette(t + u_p.w) * (0.12 + 1.0 * exp(-trap * 7.0)) * edge * (1.0 + 0.6 * u_beat);
            return vec4(min(col, vec3(1.5)), 0.8 * edge);
        }
        """)

    /// Power morphs with the eased target plus bass; the camera roams from far out to skimming
    /// the surface.
    /// u_p: x power, w palette offset.
    static let mandelbulb = FractalScene(
        name: "Mandelbulb", kind: .raymarched,
        params: [6...8.5, 0...6.283, -1...1, 0...1],
        steps: 110, trail: 0.72, swirl: 0.02,
        body: """
        float de(vec3 p, out vec4 trap) {
            vec3 z = p;
            float dr = 1.0, r = 0.0;
            float power = u_p.x + 0.6 * u_bands.x;
            trap = vec4(abs(z), dot(z, z));
            for (int i = 0; i < 8; i++) {
                r = length(z);
                if (r > 2.0) break;
                float theta = acos(clamp(z.z / r, -1.0, 1.0)) * power;
                float phi = atan(z.y, z.x) * power;
                dr = pow(r, power - 1.0) * power * dr + 1.0;
                z = pow(r, power) * vec3(sin(theta) * cos(phi), sin(phi) * sin(theta), cos(theta)) + p;
                trap = min(trap, vec4(abs(z), dot(z, z)));
            }
            return 0.5 * log(max(r, 1e-6)) * r / dr;
        }
        vec4 scene(vec2 frag) {
            Cam cam = orbitShot(1.3, 3.3, 0.4);
            vec3 ro = keepClear(cam.ro, 0.02);
            vec3 rd = cameraRay(frag, ro, cam.ta, cam.zoom, cam.roll);
            Hit h = march(ro, rd, 7.0);
            vec3 col = palette(sqrt(h.trap.w) * 0.7 + h.trap.y * 0.5 + u_p.w);
            return shade(h, ro, rd, col);
        }
        """)

    /// A Mandelbox whose scale eases and pulses on the beat, the camera roaming round the
    /// outside from wide views to close surveys of its surface. It never goes in: inside, a
    /// scale change rearranges everything round the camera, the walls whip past, and the camera
    /// lands in dense foam that renders as speckle, which read as a whirling blur.
    /// u_p: x scale, w palette offset.
    static let mandelboxFlight = FractalScene(
        name: "Mandelbox Flight", kind: .raymarched,
        params: [-2.1 ... -1.7, 0...6.283, 0...1, 0...1],
        steps: 120, trail: 0.5, swirl: 0,
        body: """
        float de(vec3 p, out vec4 trap) {
            float scale = u_p.x - 0.04 * u_beat;
            vec4 z = vec4(p, 1.0);
            vec4 c = z;
            trap = vec4(1e9);
            for (int i = 0; i < 12; i++) {
                z.xyz = clamp(z.xyz, -1.0, 1.0) * 2.0 - z.xyz;
                float r2 = dot(z.xyz, z.xyz);
                z *= clamp(1.0 / r2, 1.0, 4.0);
                z = vec4(z.xyz * scale, z.w * abs(scale)) + c;
                trap = min(trap, vec4(abs(z.xyz), r2));
            }
            return length(z.xyz) / abs(z.w);
        }
        vec4 scene(vec2 frag) {
            Cam cam = orbitShot(4.5, 9.0, 1.5);
            vec3 ro = keepClear(cam.ro, 0.1);
            vec3 rd = cameraRay(frag, ro, cam.ta, cam.zoom, cam.roll);
            Hit h = march(ro, rd, 24.0);
            vec3 col = palette(sqrt(h.trap.w) * 0.35 + h.trap.x * 0.15 + u_p.w);
            return shade(h, ro, rd, col);
        }
        """)

    /// Zooms into one of eight deep points for 64 beats, then the next: float precision bounds
    /// the depth (a scale of 2e-4). Bass adds a little zoom on top.
    /// u_p: x spin, y colour density, z, w palette offset.
    static let mandelbrotDive = FractalScene(
        name: "Mandelbrot Dive", kind: .flat,
        params: [-0.6...0.6, 0.6...1.4, 0...1, 0...1],
        steps: 0, trail: 0.75, swirl: 0.02,
        body: """
        const vec2 POINTS[8] = vec2[8](
            vec2(-0.743643887, 0.131825904), vec2(-0.745300, 0.112700), vec2(-1.250660, 0.020120),
            vec2(-0.160701350, 1.037566500), vec2(0.001643722, -0.822467633), vec2(-1.768778833, -0.001738996),
            vec2(0.254987037, -0.000567979), vec2(-0.235125, 0.827215));
        vec4 scene(vec2 frag) {
            float progress = mod(u_beatTime, 64.0) / 64.0;
            vec2 center = POINTS[int(u_beatTime / 64.0) % 8];
            float scale = 2.5 * exp(-(progress * 9.4 + 0.25 * u_fast.x));
            vec2 uv = rot(u_p.x * progress * TAU) * (frag - 0.5 * u_res) / u_res.y;
            vec2 c = center + uv * scale;
            vec2 z = vec2(0.0);
            float limit = 160.0 + 500.0 * progress;
            float i;
            for (i = 0.0; i < 660.0; i++) {
                z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
                if (dot(z, z) > 256.0 || i >= limit) break;
            }
            float fade = smoothstep(0.0, 0.04, progress) * (1.0 - smoothstep(0.94, 1.0, progress));
            if (i >= limit) return vec4(vec3(0.0), 0.9 * fade);
            float sn = i - log2(log2(dot(z, z)));
            float t = sn / 60.0 * u_p.y;
            float edge = pow(clamp(sn / (0.12 * limit), 0.0, 1.0), 1.2);
            vec3 col = palette(t + u_p.w) * edge * (0.3 + 1.2 * pow(fract(t * 3.0), 3.0) + 0.5 * u_beat);
            return vec4(min(col, vec3(1.5)) * fade, 0.85 * fade);
        }
        """)

    /// Kali's set (`p = |p| / p² - c`, an abs-and-inversion IFS) behind a kaleidoscope whose fold
    /// count (3 to 7) changes every 4 bars, the fold angle on the treble; ring traps colour each
    /// iteration's copy. It zooms in for ever, ×e every 32 beats: Kali's set is not exactly
    /// self-similar, so two layers e apart both zoom in and crossfade, the finer handing back to
    /// the coarser as each period ends, which never shows a jump.
    /// u_p: x fold rotation, y and z `c`, w palette offset.
    static let kaleidoIFS = FractalScene(
        name: "Kaleido IFS", kind: .flat,
        params: [-0.6...0.6, 0.45...0.85, 0.45...0.85, 0...1],
        steps: 0, trail: 0.8, swirl: 0.05,
        body: """
        vec3 kali(vec2 p) {
            vec2 c = vec2(u_p.y, u_p.z);
            vec3 col = vec3(0.0);
            for (int i = 0; i < 10; i++) {
                p = abs(p) / dot(p, p) - c;
                col += palette(float(i) / 10.0 + u_p.w) * exp(-18.0 * abs(length(p) - 0.9 - 0.3 * u_fast.y));
            }
            return col;
        }
        vec4 scene(vec2 frag) {
            vec2 p = rot(u_beatTime * TAU / 128.0) * (frag - 0.5 * u_res) / u_res.y * (1.3 - 0.04 * u_beat);
            float seg = TAU / (3.0 + mod(floor(u_bar / 4.0), 5.0));
            float a = abs(mod(atan(p.y, p.x) + u_p.x + 0.4 * u_fast.z + 0.5 * seg, seg) - 0.5 * seg);
            p = vec2(cos(a), sin(a)) * length(p);
            // Zoom toward a point off the centre, where the set has detail at every scale (its
            // centre empties out); equal-power weights keep the crossfade from dimming.
            const vec2 focus = vec2(0.35, 0.2);
            float f = fract(u_beatTime / 32.0);
            float w = smoothstep(0.0, 1.0, f);
            vec3 col = kali(focus + p * exp(-f)) * sqrt(w) + kali(focus + p * exp(-f - 1.0)) * sqrt(1.0 - w);
            col = pow(col * 0.6, vec3(1.4)) * (1.0 + 0.6 * u_beat);
            return vec4(min(col, vec3(1.5)), 0.7);
        }
        """, push: 0.004)

    /// Newton's method on a cubic whose three roots are pushed out by bass, mid and treble; each
    /// beat turns the basins' palette a step.
    /// u_p: x spin, y root spread, z, w palette offset.
    static let newtonRoots = FractalScene(
        name: "Newton Roots", kind: .flat,
        params: [-1...1, 0.7...1.2, 0...1, 0...1],
        steps: 0, trail: 0.7, swirl: -0.04,
        body: """
        vec2 cmul(vec2 a, vec2 b) { return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x); }
        vec2 cdiv(vec2 a, vec2 b) { return cmul(a, vec2(b.x, -b.y)) / dot(b, b); }
        vec4 scene(vec2 frag) {
            vec2 z = explore2D((frag - 0.5 * u_res) / u_res.y, 0.3) * 3.0;
            float th = u_pBeats.x * TAU / 128.0;
            vec2 r[3];
            for (int k = 0; k < 3; k++) {
                float a = th + TAU * float(k) / 3.0;
                r[k] = vec2(cos(a), sin(a)) * u_p.y * (0.8 + 0.6 * u_fast[k]);
            }
            float i;
            for (i = 0.0; i < 40.0; i++) {
                vec2 a = z - r[0], b = z - r[1], c = z - r[2];
                vec2 f = cmul(cmul(a, b), c);
                vec2 df = cmul(a, b) + cmul(b, c) + cmul(a, c);
                vec2 step = cdiv(f, df);
                z -= step;
                if (dot(step, step) < 1e-7) break;
            }
            int nearest = 0;
            float best = 1e9;
            for (int k = 0; k < 3; k++) {
                float d = length(z - r[k]);
                if (d < best) { best = d; nearest = k; }
            }
            float turn = (floor(u_beatTime) + smoothstep(0.0, 0.3, fract(u_beatTime))) * 0.04;
            float shade = pow(clamp(i / 25.0, 0.0, 1.0), 2.0);
            vec3 col = palette(float(nearest) / 3.0 + turn + u_p.w) * (0.08 + 1.4 * shade) * (1.0 + 0.5 * u_beat);
            return vec4(col, 0.85);
        }
        """)

    /// IQ-style Apollonian gasket, periodic in space, so every shot flies its own way through it
    /// for as long as it likes; the inversion radius swells with the mids.
    /// u_p: x inversion, w palette offset.
    static let apollonianTunnel = FractalScene(
        name: "Apollonian Tunnel", kind: .raymarched,
        params: [1.05...1.25, -1...1, 0...1, 0...1],
        steps: 120, trail: 0.65, swirl: 0.03,
        body: """
        float de(vec3 p, out vec4 trap) {
            float s = 1.0;
            float k = u_p.x + 0.12 * u_bands.y;
            trap = vec4(1e9);
            for (int i = 0; i < 8; i++) {
                p = -1.0 + 2.0 * fract(0.5 * p + 0.5);
                float r2 = dot(p, p);
                trap = min(trap, vec4(abs(p), r2));
                float f = k / r2;
                p *= f;
                s *= f;
            }
            return 0.25 * abs(p.y) / s;
        }
        vec4 scene(vec2 frag) {
            Cam cam = flightShot(4.0, 0.08);
            vec3 ro = keepClear(cam.ro, 0.02);
            vec3 rd = cameraRay(frag, ro, cam.ta, cam.zoom, cam.roll);
            Hit h = march(ro, rd, 12.0);
            vec3 col = palette(sqrt(h.trap.w) * 0.8 + h.trap.y * 0.3 + u_p.w);
            vec4 c = shade(h, ro, rd, col);
            return vec4(c.rgb * exp(-0.12 * h.t), c.a);
        }
        """)

    /// A dive into a Menger sponge for ever. The sponge is exactly self-similar at ×3 about the
    /// midpoint of an edge, (1, 1, 0); the camera sits at (0, -0.75, 0), inside the cube, and the
    /// sponge is scaled ×3 every 16 beats about that midpoint, so the camera flies down the line
    /// between them and arrives at its own copy a third the size. That line was searched for
    /// (in the `fractal-vis` skill): it stays in the tunnels, at least an eighth of the current
    /// scale from any wall. The view looks about, rolls and breathes; colour follows hole depth
    /// less the zoom, so nothing jumps when the loop wraps.
    /// u_p: x roll speed, y look spread, z, w palette offset.
    static let mengerDive = FractalScene(
        name: "Menger Dive", kind: .raymarched,
        params: [0...1, 0.3...0.9, 0...1, 0...1],
        steps: 120, trail: 0.6, swirl: 0.0,
        body: """
        const vec3 FIXED = vec3(1.0, 1.0, 0.0);
        const vec3 EYE = vec3(0.0, -0.75, 0.0);
        float sdBox(vec3 p, vec3 b) {
            vec3 d = abs(p) - b;
            return length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0);
        }
        float de(vec3 p, out vec4 trap) {
            float f = fract(u_beatTime / 16.0);
            float zoom = pow(3.0, f);
            p = FIXED + (p - FIXED) / zoom;
            float d = sdBox(p, vec3(1.0));
            float s = 1.0;
            trap = vec4(0.0, 0.0, 0.0, -f);
            for (int m = 0; m < 7; m++) {
                vec3 a = mod(p * s, 2.0) - 1.0;
                s *= 3.0;
                vec3 r = abs(1.0 - 3.0 * abs(a));
                float hole = (min(max(r.x, r.y), min(max(r.y, r.z), max(r.z, r.x))) - 1.0) / s;
                if (hole > d) { d = hole; trap = vec4(r, float(m) - f); }
            }
            return d * zoom;
        }
        vec4 scene(vec2 frag) {
            float seed = shotSeed(5.0);
            float t = shotTime();
            vec3 ahead = normalize(FIXED - EYE);
            vec3 look = ahead + u_p.y * wander(t * 0.07, seed) * (hash1(seed * 3.0) < 0.3 ? 2.5 : 1.0);
            float roll = (hash1(seed * 7.0) - 0.5) * 2.0 * (0.5 * u_beatTime + u_pBeats.x) * TAU / 256.0;
            float lens = mix(0.55, 1.2, hash1(seed * 11.0)) * (1.0 - 0.03 * u_beat);
            vec3 rd = cameraRay(frag, EYE, EYE + look, lens, roll);
            Hit h = march(EYE, rd, 4.0);
            vec3 col = palette(h.trap.w * 0.18 + length(h.trap.xyz) * 0.1 + u_p.w);
            return shade(h, EYE, rd, col);
        }
        """)

    /// Knighty's pseudo-Kleinian, its fold box and inversion breathing with the bands; the camera
    /// flies through it or circles points inside it.
    /// u_p: x box size, w palette offset.
    static let pseudoKleinian = FractalScene(
        name: "Pseudo-Kleinian", kind: .raymarched,
        params: [-1...1, 0...6.283, -1...1, 0...1],
        steps: 130, trail: 0.65, swirl: -0.02,
        body: """
        float de(vec3 p, out vec4 trap) {
            vec3 size = vec3(0.92436, 0.90756, 0.92436) * (1.0 + 0.03 * u_p.x + 0.03 * u_bands.x);
            float k0 = 0.70968 + 0.05 * u_bands.y;
            float factor = 1.0;
            trap = vec4(1e9);
            for (int i = 0; i < 7; i++) {
                p = 2.0 * clamp(p, -size, size) - p;
                float k = max(k0 / dot(p, p), 1.0);
                p *= k;
                factor *= k;
                trap = min(trap, vec4(abs(p), dot(p, p)));
            }
            float rxy = length(p.xy);
            return max(rxy - 0.92784, abs(rxy * p.z) / length(p)) / factor;
        }
        vec4 scene(vec2 frag) {
            // Shots alternate between flights through the structure and close orbits round
            // some point in it.
            float seed = shotSeed(2.0);
            Cam cam;
            if (hash1(seed * 31.0) < 0.6) {
                cam = flightShot(1.5, 0.05);
            } else {
                vec3 centre = (vec3(hash1(seed * 3.0), hash1(seed * 5.0), hash1(seed * 7.0)) - 0.5) * 2.0;
                cam = orbitShot(0.3, 1.0, 0.25);
                cam.ro += centre;
                cam.ta += centre;
            }
            vec3 ro = keepClear(cam.ro, 0.03);
            vec3 rd = cameraRay(frag, ro, cam.ta, cam.zoom, cam.roll);
            Hit h = march(ro, rd, 8.0);
            vec3 col = palette(sqrt(h.trap.w) * 0.5 + h.trap.z * 0.4 + u_p.w);
            vec4 c = shade(h, ro, rd, col);
            return vec4(c.rgb * exp(-0.15 * h.t), c.a);
        }
        """)

    /// A 3D slice of a quaternion Julia set whose 4D `c` drifts with the tempo, kicked on the beat.
    /// u_p: offsets to `c`'s four phases.
    static let quaternionJulia = FractalScene(
        name: "Quaternion Julia", kind: .raymarched,
        params: [-0.4...0.4, -0.4...0.4, -0.4...0.4, -0.4...0.4],
        steps: 110, trail: 0.45, swirl: 0.0,
        body: """
        vec4 qsq(vec4 a) { return vec4(a.x * a.x - dot(a.yzw, a.yzw), 2.0 * a.x * a.yzw); }
        float de(vec3 p, out vec4 trap) {
            vec4 c = 0.45 * cos(vec4(0.5, 3.9, 1.4, 1.1) + u_beatTime * TAU / 256.0 * vec4(1.0, 2.0, 1.0, 3.0) + u_p)
                   - vec4(0.3 - 0.02 * u_beat, 0.0, 0.0, 0.0);
            vec4 z = vec4(p, 0.0);
            float md2 = 1.0, mz2 = dot(z, z);
            trap = vec4(abs(z.xyz), mz2);
            for (int i = 0; i < 11; i++) {
                md2 *= 4.0 * mz2;
                z = qsq(z) + c;
                mz2 = dot(z, z);
                trap = min(trap, vec4(abs(z.xyz), mz2));
                if (mz2 > 4.0) break;
            }
            return 0.25 * sqrt(mz2 / md2) * log(mz2);
        }
        vec4 scene(vec2 frag) {
            Cam cam = orbitShot(1.7, 3.0, 0.35);
            vec3 ro = keepClear(cam.ro, 0.02);
            vec3 rd = cameraRay(frag, ro, cam.ta, cam.zoom, cam.roll);
            Hit h = march(ro, rd, 5.0);
            vec3 col = palette(sqrt(h.trap.w) * 0.9 + h.trap.x * 0.4 + 0.3 * u_bands.z);
            return shade(h, ro, rd, col);
        }
        """)

    /// A drone flyover of an alien world at dusk. The land changes as it goes: a biome field
    /// takes ridged mountains from rolling hills to high peaks, terraces some regions into mesas
    /// and canyons, ripples the low ground into dunes and tints each region its own colour, and
    /// lakes mirror the sky. A very few lit spires stand on fixed spots, and a ringed gas giant
    /// hangs in the starfield. Each shot picks a new place, a height between a high pass looking
    /// steeply down and a lower cruise looking ahead, a path (straight, a long arc or an
    /// S-curve), a pace that swings between a crawl and a rush every 16-30 beats, and gentle
    /// height swoops; the drone banks a little into its turns and holds its height over the
    /// land's broad shape ahead. Speed is distance per beat, so the tempo governs it.
    /// The eased parameters never touch the terrain or the spires, so nothing morphs or pops.
    /// u_p: y haze, w palette offset; x and z are unused.
    static let fractalPlanet = FractalScene(
        name: "Fractal Planet", kind: .raymarched,
        params: [0...1, 0.018...0.035, 0...1, 0...1],
        steps: 170, trail: 0.15, swirl: 0,
        body: """
        const float SEA = 0.55;
        float hash2(vec2 p) {
            p = fract(p * vec2(123.34, 456.21));
            p += dot(p, p + 45.32);
            return fract(p.x * p.y);
        }
        float noise(vec2 p) {
            vec2 i = floor(p), f = fract(p);
            vec2 u = f * f * (3.0 - 2.0 * f);
            return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
                       mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
        }
        const mat2 OCTAVE = mat2(1.6, 1.2, -1.2, 1.6);
        float fbm(vec2 p, int octaves) {
            float a = 0.5, s = 0.0;
            for (int i = 0; i < octaves; i++) { s += a * noise(p); p = OCTAVE * p; a *= 0.5; }
            return s;
        }
        // Ridged fBm: sharp crests that repeat at every scale.
        float ridged(vec2 p, int octaves) {
            float a = 0.5, s = 0.0;
            for (int i = 0; i < octaves; i++) {
                float n = 1.0 - abs(noise(p) * 2.0 - 1.0);
                s += a * n * n;
                p = OCTAVE * p;
                a *= 0.5;
            }
            return s;
        }
        // The biome field, changing over ~50 units: x terraces the land into mesas and canyons,
        // y sets how rugged it is.
        vec2 biome(vec2 xz) { return vec2(noise(xz * 0.02), noise(xz * 0.02 + 31.7)); }
        // Ridged mountains everywhere, from rolling hills to high peaks; terraced where the
        // biome says; dune ripples in the low ground; lakes where it dips under the sea.
        float ground(vec2 xz, int octaves) {
            vec2 b = biome(xz);
            float h = mix(2.0, 6.5, smoothstep(0.3, 0.7, b.y)) * ridged(xz * 0.08, octaves);
            float terraced = (floor(h * 1.2) + 0.5 * smoothstep(0.7, 1.0, fract(h * 1.2))) / 1.2;
            h = mix(h, terraced, smoothstep(0.45, 0.7, b.x));
            vec2 q = xz + 4.0 * vec2(noise(xz * 0.05), noise(xz * 0.05 + 9.0));
            h += 0.35 * pow(0.5 + 0.5 * sin(dot(q, vec2(0.9, 0.5))), 2.0) * (1.0 - smoothstep(0.5, 2.0, h));
            return h + fbm(xz * 0.025, 3) - 0.5;
        }
        // Very sparse spires: a fixed few cells of a coarse grid hold one, standing on the
        // ground (none in the sea). Fixed, so none ever appears or vanishes in view.
        const float CELL = 26.0;
        float tower(vec3 p) {
            vec2 cell = floor(p.xz / CELL);
            if (hash2(cell) > 0.1) return 1e9;
            vec2 centre = (cell + 0.5) * CELL + (vec2(hash2(cell + 1.3), hash2(cell + 2.9)) - 0.5) * CELL * 0.5;
            float base = ground(centre, 3) - 0.5;
            if (base < SEA) return 1e9;
            float height = 6.0 + 9.0 * hash2(cell + 7.1);
            float width = 0.3 + 0.35 * hash2(cell + 3.3);
            float taper = width * (1.0 - 0.6 * clamp((p.y - base) / height, 0.0, 1.0));
            vec2 q = abs(p.xz - centre);
            vec3 d = vec3(q.x, abs(p.y - base - height * 0.5), q.y) - vec3(taper, height * 0.5, taper);
            float box = length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0);
            // A spire stands well inside its cell, so this bound never steps past a neighbour's.
            return min(box, CELL * 0.2);
        }
        float de(vec3 p, out vec4 trap) {
            float terrain = (p.y - ground(p.xz, 7)) * 0.3;
            float water = p.y - SEA;
            float spire = tower(p);
            float d = min(terrain, min(water, spire));
            trap = vec4(p, d == water ? 1.0 : d == spire ? 2.0 : 0.0);
            return d;
        }
        vec3 sky(vec3 rd) {
            vec3 col = mix(palette(0.15 + u_p.w) * 0.18, palette(0.7 + u_p.w) * 0.015, sqrt(max(rd.y, 0.0)));
            vec3 cell = floor(rd * 280.0);
            col += step(0.9975, hash2(cell.xy + cell.z * 17.0)) * smoothstep(0.0, 0.2, rd.y) * 0.9;
            vec3 pd = normalize(vec3(0.45, 0.2, 1.0));
            vec3 e1 = normalize(cross(pd, vec3(0.2, 1.0, 0.0)));
            vec3 e2 = cross(pd, e1);
            vec3 q = rd - pd * dot(rd, pd);
            vec2 a = vec2(dot(q, e1), dot(q, e2));
            if (dot(rd, pd) > 0.0) {
                float disc = length(a);
                float ring = length(vec2(a.x, a.y / 0.28));
                if (disc < 0.17) {
                    float bands = sin(a.y * 70.0 + 3.0 * sin(a.x * 20.0));
                    float lit = smoothstep(-0.12, 0.08, dot(a, vec2(0.7, 0.7)));
                    col = palette(0.35 + 0.08 * bands + u_p.w) * (0.15 + 0.85 * lit);
                }
                if (ring > 0.27 && ring < 0.42 && (a.y < 0.0 || disc > 0.17))
                    col += palette(0.55 + 3.0 * ring + u_p.w) * 0.45 * (0.6 + 0.4 * sin(ring * 260.0));
            }
            return col;
        }
        vec4 scene(vec2 frag) {
            float seed = shotSeed(6.0);
            float t = shotTime();
            // Each shot sits somewhere between a high pass looking steeply down and a lower
            // cruise looking ahead; never at the horizon, where the land flattens into haze.
            float height = hash1(seed * 7.0);
            // The path, its own per shot: a steady turn (straight to a long arc) plus an S-curve
            // of its own size and period.
            float turnRate = (hash1(seed * 19.0) - 0.5) * 0.024;
            float sway = 0.6 * hash1(seed * 23.0) * hash1(seed * 29.0);
            float swayFreq = mix(0.08, 0.2, hash1(seed * 31.0));
            // Speed is distance per beat, so the tempo sets how fast the land goes by. Each shot
            // cruises at its own pace and swings between a crawl and a rush every 16-30 beats.
            float pace = mix(0.9, 1.6, height) * mix(0.7, 1.4, hash1(seed * 37.0));
            float surgeFreq = mix(0.2, 0.4, hash1(seed * 43.0));
            float surgeFreq2 = mix(0.5, 0.8, hash1(seed * 41.0));
            // Fly the path: add up each stretch along its own heading, so the drone travels the
            // way it faces instead of sliding sideways.
            vec2 xz = (vec2(hash1(seed * 3.0), hash1(seed * 5.0)) - 0.5) * 600.0;
            const int LEGS = 32;
            for (int i = 0; i < LEGS; i++) {
                float ti = (float(i) + 0.5) * t / float(LEGS);
                float hi = seed * TAU + turnRate * ti + sway * sin(ti * swayFreq + seed * 3.0);
                float speed = max(0.15, 1.0 + 0.65 * sin(ti * surgeFreq + seed * 5.0) + 0.3 * sin(ti * surgeFreq2 + seed * 11.0));
                xz += vec2(cos(hi), sin(hi)) * pace * speed * t / float(LEGS);
            }
            float heading = seed * TAU + turnRate * t + sway * sin(t * swayFreq + seed * 3.0);
            float turning = turnRate + sway * swayFreq * cos(t * swayFreq + seed * 3.0);
            vec2 dir = vec2(cos(heading), sin(heading));
            // Clear the land's broad shape some way ahead, so the drone rises over a range
            // rather than bouncing over every crest.
            float clearance = SEA;
            for (int i = 0; i < 6; i++) clearance = max(clearance, ground(xz + dir * float(i) * 5.0, 3));
            float altitude = mix(3.0, 10.0, height) * (0.85 + 0.25 * sin(t * mix(0.02, 0.05, hash1(seed * 47.0)) + seed));
            vec3 ro = vec3(xz.x, clearance + altitude, xz.y);
            float pitch = mix(-0.25, -0.6, height) + 0.05 * sin(t * 0.03 + seed);
            float yaw = heading + 0.2 * sin(t * 0.015 + seed * 2.0);
            vec3 look = vec3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch));
            // Bank gently into the turn.
            vec3 rd = cameraRay(frag, ro, ro + look, 1.25, clamp(-turning * 6.0, -0.15, 0.15));
            Hit h = march(ro, rd, 90.0);
            vec3 col;
            // A low sun from the gas giant's side; the shared headlight glared under a drone
            // looking down.
            vec3 sun = normalize(vec3(0.45, 0.35, 1.0));
            if (h.hit) {
                vec3 p = ro + rd * h.t;
                if (h.trap.w > 1.5) {
                    vec3 n = normalAt(p, 0.01);
                    col = palette(0.8 + u_p.w) * 0.1 * (0.3 + 0.7 * max(dot(n, sun), 0.0));
                    vec2 w = vec2(p.y * 9.0, (p.x + p.z) * 8.0);
                    float lit = step(0.6, hash2(floor(w))) * step(0.25, fract(w.x)) * step(0.3, fract(w.y));
                    col += palette(0.95 + u_p.w) * lit * (1.1 + 0.5 * u_beat);
                } else if (h.trap.w > 0.5) {
                    // Water: the sky mirrored through a gentle swell, deeper colour beneath.
                    vec2 swell = vec2(noise(p.xz * 3.0 + u_time * 0.3), noise(p.xz * 3.0 - u_time * 0.25)) - 0.5;
                    vec3 n = normalize(vec3(swell.x * 0.15, 1.0, swell.y * 0.15));
                    float fresnel = 0.2 + 0.8 * pow(1.0 - max(dot(-rd, n), 0.0), 4.0);
                    col = mix(palette(0.5 + u_p.w) * 0.3, sky(reflect(rd, n)) + palette(0.15 + u_p.w) * 0.2, fresnel);
                } else {
                    vec3 n = normalAt(p, 0.02);
                    float slope = 1.0 - n.y;
                    // Each region its own tint.
                    vec2 b = biome(p.xz);
                    vec3 base = palette(0.1 + 0.35 * b.x - 0.2 * b.y + 0.06 * p.y + 0.25 * slope + u_p.w)
                              * (0.35 + 0.3 * (1.0 - slope));
                    col = base * (0.45 + 0.2 * n.y + 0.8 * max(dot(n, sun), 0.0)) * (1.0 - 0.5 * h.steps);
                }
            } else {
                col = sky(rd);
            }
            vec3 haze = palette(0.15 + u_p.w) * 0.12;
            col = h.hit ? mix(col, haze, 1.0 - exp(-u_p.y * h.t))
                        : mix(col, haze, 0.25 * pow(1.0 - max(rd.y, 0.0), 6.0));
            return vec4(col, 1.0);
        }
        """)
}
