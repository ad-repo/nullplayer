/* NullPlayer port: the Ooh/Ugh effect — see ooh_ugh.h. Original work, not upstream Goom. */
#include "ooh_ugh.h"

#include <math.h>
#include <stdlib.h>
#include "goom_tools.h"

#define MAX_SEGS 192
#define WRAITHS 3
#define MORPH_CYCLES 90  /* how long one scene's emitters take to hand over to the next's */
#define SOULS 6

enum { SIGIL_PENTACLE, SIGIL_GOAT, SIGIL_SWORD, SIGIL_CROSS, SIGIL_KINDS, SOUL_SKULL = SIGIL_KINDS, SOUL_GOAT };

typedef struct { float x0, y0, x1, y1; } Seg;

/* A sigil is flung out of the abyss: drawn small into the feedback for a few cycles while the
   zoom carries each copy outwards, so it reads as a smeared echo, never as a picture. */
typedef struct { int kind, alive, age, life; unsigned seed; float rot; } Sigil;

typedef struct { float x, y; int drawn; } Wraith;

/* A soul: a skull or goat face that rises out of the fire, faint and wavering like the flames,
   so the feedback's lift smears it into them. Only ever half seen. */
typedef struct { int kind, alive, age, life; unsigned seed; float x, size; } Soul;

/* A scene: where its abyss sits (the zoom's middle, as fractions of the screen) and how much
   of each emitter it runs. filters.c holds the matching flow field, by the same index. */
typedef struct { float ax, ay, wraiths, fire, ash, sparks; } Scene;
static const Scene scenes[OOH_SCENES] = {
    { 0.50f, 0.75f, 0.5f, 0.8f, 0.0f, 0.0f },   /* throat */
    { 0.50f, 0.50f, 1.0f, 0.7f, 0.3f, 0.0f },   /* maelstrom */
    { 0.50f, 0.85f, 0.4f, 1.0f, 0.0f, 0.0f },   /* pyre */
    { 0.50f, 0.50f, 0.6f, 0.6f, 0.0f, 0.0f },   /* rift */
    { 0.50f, 0.48f, 0.5f, 0.0f, 0.5f, 1.0f },   /* vortex */
};

struct OohUgh {
    Sigil sigil;
    Wraith wraiths[WRAITHS];
    Soul souls[SOULS];
    int scene, prevScene, sceneAge, sceneLen;
    float morph;           /* 0 -> 1 as the previous scene's emitters hand over */
    float ax, ay;          /* the abyss on screen, easing towards the scene's */
    float t;               /* animation clock, runs faster with the music */
    float beat;            /* 1 on a beat, then decays */
    float hit;             /* a big hit: 1, then decays faster */
    float lowpass;         /* the low-pass filter's last output, carried across cycles */
    float lowEnv, lowRef;  /* the low end's envelope, and the slow peak it is measured against */
    float bass;            /* 0..1: how hard the thick low end is pushing right now */
    /* the burn line's frame: it turns round the screen (pi = hanging from the top), bows and
       ripples, each easing towards a target that scene changes and big hits pick */
    float ang, spin, spinTo, bend, bendTo, twist, twistTo, reach, reachTo;
    unsigned char red[256];    /* brightest channel -> red */
    unsigned char white[256];  /* dimmest channel -> white */
};

static unsigned hash (unsigned a)
{
    a ^= a >> 16; a *= 0x7feb352du; a ^= a >> 15; a *= 0x846ca68bu; a ^= a >> 16;
    return a;
}

static float frand (PluginInfo *g) { return (float)goom_irand (g->gRandom, 10000) / 10000.0f; }

/* ---- drawing: additive, clipped per pixel ---- */

static void plot (Pixel *p, int w, int h, int x, int y, int r, int gb)
{
    Pixel *q;
    int v;
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    q = &p[y * w + x];
    v = q->channels.r + r;  q->channels.r = v > 255 ? 255 : v;
    v = q->channels.g + gb; q->channels.g = v > 255 ? 255 : v;
    v = q->channels.b + gb; q->channels.b = v > 255 ? 255 : v;
}

static void line (Pixel *p, int w, int h, float x0, float y0, float x1, float y1,
                  float thick, int r, int gb)
{
    float dx = x1 - x0, dy = y1 - y0;
    float len = sqrtf (dx * dx + dy * dy);
    int steps = (int)len + 1, i, k, t = (int)thick;
    float nx = len > 0 ? -dy / len : 0, ny = len > 0 ? dx / len : 0;
    if (len > 4.0f * (w + h)) return;
    for (k = -(t / 2); k <= t - 1 - t / 2; k++)
        for (i = 0; i <= steps; i++) {
            float s = (float)i / steps;
            plot (p, w, h, (int)(x0 + s * dx + k * nx), (int)(y0 + s * dy + k * ny), r, gb);
        }
}

/* ---- shapes, in unit space with y down; a sigil scales and turns them ---- */

static void add (Seg *s, int *n, float x0, float y0, float x1, float y1)
{
    if (*n < MAX_SEGS) s[(*n)++] = (Seg){ x0, y0, x1, y1 };
}

static void bezier (Seg *s, int *n, float ax, float ay, float bx, float by,
                    float cx, float cy, float dx, float dy)
{
    float px = ax, py = ay;
    int i;
    for (i = 1; i <= 12; i++) {
        float t = i / 12.0f, u = 1 - t;
        float x = u*u*u*ax + 3*u*u*t*bx + 3*u*t*t*cx + t*t*t*dx;
        float y = u*u*u*ay + 3*u*u*t*by + 3*u*t*t*cy + t*t*t*dy;
        add (s, n, px, py, x, y);
        px = x; py = y;
    }
}

/* A ring, its radius pushed by the waveform. */
static void ring (Seg *s, int *n, float r, int steps, const gint16 *pcm, float push)
{
    int i;
    for (i = 0; i < steps; i++) {
        float a0 = 2 * (float)M_PI * i / steps, a1 = 2 * (float)M_PI * (i + 1) / steps;
        float r0 = r + (pcm ? push * pcm[(i * 509 / steps) % 512] / 32768.0f : 0);
        float r1 = r + (pcm ? push * pcm[((i + 1) * 509 / steps) % 512] / 32768.0f : 0);
        add (s, n, r0 * cosf (a0), r0 * sinf (a0), r1 * cosf (a1), r1 * sinf (a1));
    }
}

static int build (int kind, Seg *s, const gint16 *pcm)
{
    int n = 0, k;
    switch (kind) {
    case SIGIL_PENTACLE:
        /* point-down star in one stroke (y down: angle pi/2 is the bottom point) */
        for (k = 0; k < 5; k++) {
            float a0 = (float)M_PI / 2 + k * 4 * (float)M_PI / 5;
            float a1 = a0 + 4 * (float)M_PI / 5;
            add (s, &n, cosf (a0), sinf (a0), cosf (a1), sinf (a1));
        }
        ring (s, &n, 1.0f, 48, pcm, 0.10f);
        break;
    case SIGIL_GOAT: {
        int m;
        for (m = -1; m <= 1; m += 2) {
            /* horns sweep up and out, curling back in */
            bezier (s, &n, m*0.20f, -0.30f, m*0.85f, -0.50f, m*0.95f, -1.15f, m*0.42f, -0.98f);
            bezier (s, &n, m*0.12f, -0.32f, m*0.60f, -0.62f, m*0.70f, -1.00f, m*0.42f, -0.98f);
            /* ears */
            add (s, &n, m*0.34f, -0.22f, m*0.78f, -0.10f);
            add (s, &n, m*0.78f, -0.10f, m*0.36f, -0.02f);
            /* slanted eyes */
            add (s, &n, m*0.22f, -0.12f, m*0.08f, -0.03f);
            /* long face down to the muzzle */
            add (s, &n, m*0.34f, -0.30f, m*0.24f, 0.22f);
            add (s, &n, m*0.24f, 0.22f, m*0.10f, 0.62f);
            /* beard */
            add (s, &n, m*0.06f, 0.66f, m*0.02f, 0.92f);
        }
        add (s, &n, -0.34f, -0.30f, 0.34f, -0.30f);
        add (s, &n, -0.10f, 0.62f, 0.10f, 0.62f);
        add (s, &n, 0.0f, -0.20f, 0.0f, 0.30f);   /* brow ridge to snout */
        break;
    }
    case SIGIL_SWORD:
        /* point down: blade, fuller, quillons, grip, pommel */
        add (s, &n, -0.05f, -0.25f, 0.0f, 0.78f);
        add (s, &n, 0.05f, -0.25f, 0.0f, 0.78f);
        add (s, &n, 0.0f, -0.20f, 0.0f, 0.52f);
        bezier (s, &n, -0.32f, -0.20f, -0.20f, -0.27f, 0.20f, -0.27f, 0.32f, -0.20f);
        add (s, &n, 0.0f, -0.27f, 0.0f, -0.50f);
        add (s, &n, -0.03f, -0.30f, -0.03f, -0.48f);
        add (s, &n, 0.03f, -0.30f, 0.03f, -0.48f);
        for (k = 0; k < 8; k++) {
            float a0 = k * (float)M_PI / 4, a1 = (k + 1) * (float)M_PI / 4;
            add (s, &n, 0.06f*cosf (a0), -0.56f + 0.06f*sinf (a0), 0.06f*cosf (a1), -0.56f + 0.06f*sinf (a1));
        }
        break;
    case SOUL_SKULL: {
        int m;
        for (m = -1; m <= 1; m += 2) {
            /* cranium, cheekbone down to the teeth, the jaw under them */
            bezier (s, &n, 0.0f, -0.78f, m*0.40f, -0.78f, m*0.62f, -0.40f, m*0.55f, 0.02f);
            bezier (s, &n, m*0.55f, 0.02f, m*0.50f, 0.22f, m*0.36f, 0.30f, m*0.28f, 0.44f);
            bezier (s, &n, m*0.30f, 0.46f, m*0.30f, 0.66f, m*0.16f, 0.74f, 0.0f, 0.74f);
            /* angular sockets, heavy brow sloping in */
            add (s, &n, m*0.40f, -0.18f, m*0.08f, -0.10f);
            add (s, &n, m*0.08f, -0.10f, m*0.14f, 0.06f);
            add (s, &n, m*0.14f, 0.06f, m*0.34f, 0.08f);
            add (s, &n, m*0.34f, 0.08f, m*0.40f, -0.18f);
            /* nose cavity */
            add (s, &n, 0.0f, 0.14f, m*0.07f, 0.28f);
            add (s, &n, m*0.07f, 0.28f, 0.0f, 0.26f);
        }
        add (s, &n, -0.28f, 0.44f, 0.28f, 0.44f);   /* teeth */
        for (k = -2; k <= 2; k++) add (s, &n, k * 0.09f, 0.38f, k * 0.09f, 0.52f);
        break;
    }
    case SOUL_GOAT: {
        /* not the sigil's goat: its spread horns and ears read as wings once they waver, so
           these horns climb straight up like the flames they rise in */
        int m;
        for (m = -1; m <= 1; m += 2) {
            bezier (s, &n, m*0.18f, -0.40f, m*0.45f, -0.70f, m*0.40f, -1.10f, m*0.15f, -1.25f);
            bezier (s, &n, m*0.08f, -0.42f, m*0.28f, -0.68f, m*0.26f, -1.00f, m*0.15f, -1.25f);
            add (s, &n, m*0.18f, -0.40f, m*0.30f, -0.20f);
            bezier (s, &n, m*0.30f, -0.20f, m*0.30f, 0.15f, m*0.18f, 0.45f, m*0.08f, 0.70f);
            add (s, &n, m*0.22f, -0.08f, m*0.07f, 0.00f);    /* slanted eyes */
            add (s, &n, m*0.05f, 0.58f, m*0.02f, 0.66f);     /* nostrils */
            add (s, &n, m*0.04f, 0.72f, m*0.01f, 1.00f);     /* beard */
        }
        add (s, &n, -0.10f, -0.25f, 0.10f, -0.25f);
        add (s, &n, -0.08f, 0.70f, 0.08f, 0.70f);
        break;
    }
    case SIGIL_CROSS:
        /* inverted: the crossbar sits low */
        add (s, &n, -0.03f, -0.65f, -0.03f, 0.65f);
        add (s, &n, 0.03f, -0.65f, 0.03f, 0.65f);
        add (s, &n, -0.28f, 0.28f, 0.28f, 0.28f);
        add (s, &n, -0.28f, 0.34f, 0.28f, 0.34f);
        break;
    }
    return n;
}

/* ---- the hellscape ---- */

/* one of the scene table's emitter amounts, blended from the previous scene's by morph */
#define WEIGHT(st, f) (scenes[(st)->prevScene].f + (scenes[(st)->scene].f - scenes[(st)->prevScene].f) * (st)->morph)

/* Where the flames start: a wandering line, never drawn itself, laid out along u in -1..1 in its
   own frame (y down, flames towards -y), then turned by ang about a point 0.34h behind the
   screen's middle, so at ang 0 it sits across the lower third; ang only tilts it. */
static void burn_local (PluginInfo *g, struct OohUgh *st, float s, float L, float *lx, float *ly)
{
    float h = g->screen.height, u = 2 * s - 1, q = (u + 1) * L / g->screen.width * 5.0f + st->t * 0.012f;
    float sum = 0, amp = 1;
    int o;
    for (o = 0; o < 3; o++, q *= 2.1f, amp *= 0.5f) {
        int i = (int)floorf (q);
        float f = q - i;
        float a = (hash ((unsigned)i * 1013u + 31u + o) & 0xffff) / 65535.0f;
        float c = (hash ((unsigned)(i + 1) * 1013u + 31u + o) & 0xffff) / 65535.0f;
        sum += amp * (a + (c - a) * f);
    }
    *lx = u * L;
    *ly = h * (-0.16f * sum / 1.75f - 0.05f * st->bass + st->bend * u * u
               + st->twist * sinf (u * 9.4f + st->t * 0.02f));
}

static float burn_len (PluginInfo *g)
{
    return 0.55f * hypotf ((float)g->screen.width, (float)g->screen.height);
}

/* The point at s in 0..1 along the burn line, and the unit direction its flames climb. */
static void burn_at (PluginInfo *g, struct OohUgh *st, float s, float *x, float *y, float *nx, float *ny)
{
    float w = g->screen.width, h = g->screen.height, L = burn_len (g);
    float c = cosf (st->ang), sn = sinf (st->ang), x0, y0, x1, y1, tx, ty, len, lnx, lny;
    burn_local (g, st, s, L, &x0, &y0);
    burn_local (g, st, s + 0.002f, L, &x1, &y1);
    tx = x1 - x0; ty = y1 - y0; len = sqrtf (tx * tx + ty * ty);
    lnx = len > 0 ? ty / len : 0; lny = len > 0 ? -tx / len : -1;
    *x = w * 0.5f - st->reach * h * sn + x0 * c - y0 * sn;
    *y = h * 0.5f + st->reach * h * c + x0 * sn + y0 * c;
    *nx = lnx * c - lny * sn;
    *ny = lnx * sn + lny * c;
}

/* Flames along the burn line, fed into the feedback so the flow carries them on. */
static void draw_fire (PluginInfo *g, struct OohUgh *st, const gint16 *pcm, Pixel *p, float amount)
{
    int w = g->screen.width, h = g->screen.height, i, k, n;
    float L2 = 2 * burn_len (g), px = 0, py = 0;
    if (amount < 0.02f) return;
    /* the waveform traced along the burn line: the swirl lifts each copy into smoke banks */
    n = (int)(L2 / 2);
    for (i = 0; i <= n; i++) {
        float s = (float)i / n, bx, by, nx, ny, v;
        burn_at (g, st, s, &bx, &by, &nx, &ny);
        v = h * 0.12f * fabsf ((float)pcm[(int)(s * 511)]) / 32768.0f;
        bx += nx * v; by += ny * v;
        if (i) line (p, w, h, px, py, bx, by, 2.0f, (int)(160 * amount * (0.7f + 0.5f * st->bass)), (int)(60 * amount * st->beat));
        px = bx; py = by;
    }
    n = (int)(L2 / 3);
    for (i = 0; i <= n; i++) {
        float s = (float)i / n, bx, by, nx, ny;
        float v = fabsf ((float)pcm[(int)(s * 511)]) / 32768.0f;
        float tall = h * (0.02f + 0.12f * st->bass + 0.20f * v * (0.4f + st->beat)) * (0.4f + 0.6f * frand (g)) * amount;
        float phase = frand (g) * 6.28f;
        int top = (int)tall;
        burn_at (g, st, s, &bx, &by, &nx, &ny);
        if (bx < -tall || by < -tall || bx > w + tall || by > h + tall) continue;
        for (k = 0; k < top; k++) {
            float t = (float)k / tall, heat = (1 - t) * (1 - t) * (0.35f + 0.65f * v) * (0.8f + 0.5f * st->bass);
            float side = sinf (k * 0.09f + phase) * 3.0f * t;
            plot (p, w, h, (int)(bx + nx * k - ny * side), (int)(by + ny * k + nx * side),
                  (int)(150 * heat), (int)(70 * heat * heat * st->beat));
        }
    }
    if (st->beat >= 1.0f)   /* embers */
        for (k = (int)((goom_irand (g->gRandom, 6) + 2) * amount); k > 0; k--) {
            float bx, by, nx, ny, up = (float)goom_irand (g->gRandom, h / 8 + 1);
            burn_at (g, st, frand (g), &bx, &by, &nx, &ny);
            plot (p, w, h, (int)(bx + nx * up), (int)(by + ny * up), 255, 220);
            plot (p, w, h, (int)(bx + nx * up) + 1, (int)(by + ny * up), 200, 160);
        }
}

/* Ash: dim specks anywhere; the scene's drift draws them into falling streaks. */
static void draw_ash (PluginInfo *g, Pixel *p, float amount)
{
    int w = g->screen.width, h = g->screen.height, k;
    for (k = (int)(24 * amount); k > 0; k--) {
        int x = goom_irand (g->gRandom, w), y = goom_irand (g->gRandom, h), lit = 60 + goom_irand (g->gRandom, 90);
        plot (p, w, h, x, y, lit, lit / 2);
    }
}

/* The vortex's eye throws short jagged sparks at random angles every cycle; the tunnel's rush
   and twist fling each copy outward into spiral streaks: the walls flying past. More and
   hotter on a kick, heavier with the low end. */
static void draw_sparks (PluginInfo *g, struct OohUgh *st, const gint16 *pcm, Pixel *p, float amount)
{
    int w = g->screen.width, h = g->screen.height, i, k;
    float cx = w * st->ax, cy = h * st->ay;
    float lit = amount * (0.5f + 0.4f * st->beat + 0.3f * st->bass);
    if (amount < 0.02f) return;
    for (i = (int)((7 + 8 * st->beat + 4 * st->bass) * amount); i > 0; i--) {
        float a = frand (g) * 2 * (float)M_PI;
        float v = fabsf ((float)pcm[goom_irand (g->gRandom, 512)]) / 32768.0f;
        float r = h * (0.02f + 0.10f * frand (g)), len = h * (0.02f + 0.05f * v);
        float px = cx + r * cosf (a), py = cy + r * sinf (a);
        for (k = 1; k <= 3; k++) {   /* kinked, so a spark is never a clean ray */
            float rr = r + len * k / 3, kink = a + (frand (g) - 0.5f) * 0.3f;
            float x = cx + rr * cosf (kink), y = cy + rr * sinf (kink);
            line (p, w, h, px, py, x, y, 1.0f, (int)(150 * lit), (int)(45 * lit * st->beat));
            px = x; py = y;
        }
    }
}

/* Smoke wraiths: points on slow Lissajous orbits trailing ribbons the swirl twists up. */
static void draw_wraiths (PluginInfo *g, struct OohUgh *st, Pixel *p, float volume, float amount)
{
    int w = g->screen.width, h = g->screen.height, i;
    float lit = (0.3f + 0.7f * fminf (1.0f, volume * 2.0f)) * amount;
    for (i = 0; i < WRAITHS; i++) {
        Wraith *wr = &st->wraiths[i];
        float t = st->t * (0.21f + 0.07f * i) + i * 2.1f;
        float x = w * (0.5f + 0.42f * sinf (t * 1.3f + i) * cosf (t * 0.31f));
        float y = h * (0.45f + 0.35f * sinf (t * 0.9f + 2.0f * i));
        if (wr->drawn && lit > 0.02f)
            line (p, w, h, wr->x, wr->y, x, y, 1.0f + 2.0f * st->beat, (int)(110 * lit), (int)(50 * lit * st->beat));
        wr->x = x; wr->y = y; wr->drawn = 1;
    }
}

/* Faces in the fire: each stroke wavers like a flame, stretches upward as the soul rises, and
   flickers in and out, drawn dim into the feedback so the lift turns it into more fire. */
static void draw_souls (PluginInfo *g, struct OohUgh *st, Pixel *p, float amount)
{
    Seg segs[MAX_SEGS];
    int w = g->screen.width, h = g->screen.height, j, i;
    for (j = 0; j < SOULS; j++) {
        Soul *so = &st->souls[j];
        float life, lit, size, stretch, cx, cy, nx, ny, rise;
        unsigned flicker;
        int n;
        if (!so->alive) continue;
        life = (float)so->age / so->life;
        lit = sinf ((float)M_PI * life) * (0.30f + 0.15f * st->beat + 0.30f * st->bass) * amount;
        size = h * so->size * (1.0f + 0.3f * life);
        stretch = 1.0f + 0.7f * life;
        /* rising off the burn line along its flames, upright to them */
        burn_at (g, st, so->x, &cx, &cy, &nx, &ny);
        rise = h * (0.06f + 0.30f * life);
        cx += nx * rise; cy += ny * rise;
        flicker = so->seed + (unsigned)(so->age / 3) * 2654435761u;
        n = build (so->kind, segs, NULL);
        for (i = 0; i < n; i++) {
            unsigned hs = hash (flicker + (unsigned)i * 7919u);
            float ax = segs[i].x0, ay = segs[i].y0, bx = segs[i].x1, by = segs[i].y1, heat;
            if (hs % 5 < 2) continue;   /* two strokes in five gone at any moment */
            heat = lit * (0.6f + 0.4f * ((hs >> 8) & 255) / 255.0f);
            ax += sinf (ay * 7.0f + st->t * 0.9f + so->seed) * 0.10f;
            bx += sinf (by * 7.0f + st->t * 0.9f + so->seed) * 0.10f;
            ay *= stretch; by *= stretch;
            line (p, w, h, cx + size * (-ny * ax - nx * ay), cy + size * (nx * ax - ny * ay),
                  cx + size * (-ny * bx - nx * by), cy + size * (nx * bx - ny * by), 1.0f, (int)(150 * heat), (int)(30 * heat));
        }
        if (++so->age >= so->life) so->alive = 0;
    }
}

static void draw_sigil (PluginInfo *g, struct OohUgh *st, Sigil *sg, const gint16 *pcm, Pixel *p)
{
    Seg segs[MAX_SEGS];
    int w = g->screen.width, h = g->screen.height, n = build (sg->kind, segs, pcm), i;
    float life = (float)sg->age / sg->life;
    float scale = h * (0.02f + 0.05f * life);
    float lit = sinf ((float)M_PI * life) * 0.6f;
    float c = cosf (sg->rot), s = sinf (sg->rot), cx = w * st->ax, cy = h * st->ay;
    for (i = 0; i < n; i++) {
        unsigned hs = hash (sg->seed + (unsigned)i * 7919u);
        float ax = segs[i].x0, ay = segs[i].y0, bx = segs[i].x1, by = segs[i].y1;
        if ((hs & 3) == 0) continue;    /* a quarter of the strokes gone */
        if (((hs >> 4) & 3) == 0) {     /* and some cut short */
            float keep = 0.3f + 0.5f * ((hs >> 16) & 255) / 255.0f;
            bx = ax + (bx - ax) * keep; by = ay + (by - ay) * keep;
        }
        line (p, w, h, cx + scale * (ax * c - ay * s), cy + scale * (ax * s + ay * c),
              cx + scale * (bx * c - by * s), cy + scale * (bx * s + by * c), 1.0f,
              (int)(170 * lit), (int)(60 * lit));
    }
}

static struct OohUgh *state (PluginInfo *g)
{
    struct OohUgh *st = g->update.oohUgh;
    int i;
    if (st != NULL) return st;
    st = calloc (1, sizeof *st);
    if (st == NULL) return NULL;
    /* any hue's strength becomes red, only what is lit in every channel goes white */
    for (i = 0; i < 256; i++) {
        st->red[i] = i <= 45 ? 0 : (unsigned char)fminf (255.0f, 255.0f * powf ((i - 45) / 170.0f, 1.6f));
        st->white[i] = i <= 140 ? 0 : (unsigned char)(255.0f * powf ((i - 140) / 115.0f, 1.5f));
    }
    st->sceneLen = 600;
    st->reach = st->reachTo = 0.34f;
    st->morph = 1.0f;
    st->ax = scenes[0].ax;
    st->ay = scenes[0].ay;
    g->update.oohUgh = st;
    return st;
}

int ooh_ugh_scene (PluginInfo *g)
{
    struct OohUgh *st = state (g);
    int bigHit = g->sound.timeSinceLastBigGoom == 0;
    if (st == NULL) return 0;
    /* Goom moves the middle and adds planes on its own beats and delivers that unsettled
       now and then, so the scene's config is restated every cycle */
    ooh_ugh_settle (g, &g->update.zoomFilterData);
    /* a scene runs 20-40 s, or gives way early to a big hit once it has had 12 s */
    if (++st->sceneAge < st->sceneLen && !(bigHit && st->sceneAge > 360 && goom_irand (g->gRandom, 3) == 0))
        return 0;
    st->prevScene = st->scene;
    st->scene = (st->scene + 1 + goom_irand (g->gRandom, OOH_SCENES - 1)) % OOH_SCENES;
    st->sceneAge = 0;
    st->sceneLen = 600 + goom_irand (g->gRandom, 600);
    st->morph = 0.0f;
    ooh_ugh_settle (g, &g->update.zoomFilterData);
    return 1;
}

void ooh_ugh_settle (PluginInfo *g, ZoomFilterData *zf)
{
    struct OohUgh *st = state (g);
    if (st == NULL) return;
    zf->oohScene = (char)st->scene;
    zf->middleX = (int)(g->screen.width * scenes[st->scene].ax);
    zf->middleY = (int)(g->screen.height * scenes[st->scene].ay);
    zf->hPlaneEffect = zf->vPlaneEffect = 0;
    zf->noisify = 0;
    zf->waveEffect = zf->hypercosEffect = 0;
    zf->kaleidoEffect = 0;   /* folded round an off-centre abyss, the feedback floods the screen */
}

void ooh_ugh_draw (PluginInfo *g, gint16 data[2][512], Pixel *p)
{
    struct OohUgh *st = state (g);
    int beat = g->sound.timeSinceLastGoom == 0;
    float volume = g->sound.volume;
    Sigil *sg;
    if (st == NULL) return;

    {   /* the thick low end: a one-pole low-pass (~120 Hz at 44.1 kHz) over the cycle's samples,
           its level held like a slow compressor and measured against its recent peak, but never
           against less than real weight: thin rock bass must not read as a doom drone */
        float lp = st->lowpass, sum = 0, level;
        int i;
        for (i = 0; i < 512; i++) {
            lp += 0.017f * (data[0][i] - lp);
            sum += lp * lp;
        }
        st->lowpass = lp;
        level = sqrtf (sum / 512);
        st->lowEnv = level > st->lowEnv ? st->lowEnv + 0.5f * (level - st->lowEnv) : st->lowEnv * 0.96f;
        st->lowRef = fmaxf (fmaxf (st->lowRef * 0.997f, st->lowEnv), 6000.0f);
        st->bass = fminf (1.0f, st->lowEnv / st->lowRef);
        st->bass *= st->bass;   /* only the real weight counts */
    }
    st->beat = beat ? 1.0f : st->beat * 0.82f;
    st->hit = g->sound.timeSinceLastBigGoom == 0 ? 1.0f : st->hit * 0.7f;
    st->t += 0.25f + 0.6f * volume + 0.4f * st->beat;
    {   /* souls rise from the fire all the time, faster on a kick and when the low end leans on it */
        int j, odds = st->hit >= 1.0f ? 3 : beat ? 6 : st->bass >= 0.5f ? 15 : 60;
        for (j = 0; j < SOULS; j++) {
            Soul *so = &st->souls[j];
            if (so->alive || goom_irand (g->gRandom, odds)) continue;
            so->kind = goom_irand (g->gRandom, 2) ? SOUL_SKULL : SOUL_GOAT;
            so->x = 0.15f + 0.7f * frand (g);
            so->size = 0.07f + 0.06f * frand (g);
            so->life = 45 + goom_irand (g->gRandom, 40);
            so->seed = (unsigned)goom_irand (g->gRandom, 1 << 30);
            so->age = 0;
            so->alive = 1;
            break;
        }
    }
    /* a new scene, every ten seconds or so, or now and then a big hit sends the burn line
       somewhere new: swung anywhere from one side round the bottom to the other, nearer the
       middle or further out, with a fresh bow and ripple, so it never settles into a horizon.
       Never over the top: hung from there, the fire left the screen black */
    if (st->morph == 0.0f || st->sceneAge % 300 == 299 || (st->hit >= 1.0f && goom_irand (g->gRandom, 4) == 0)) {
        st->spinTo = (frand (g) - 0.5f) * 3.6f;
        st->reachTo = 0.16f + 0.22f * frand (g);
        st->bendTo = (frand (g) - 0.5f) * 0.6f;
        st->twistTo = frand (g) * 0.10f;
    }
    st->spin += (st->spinTo - st->spin) * 0.015f;
    st->reach += (st->reachTo - st->reach) * 0.015f;
    st->bend += (st->bendTo - st->bend) * 0.02f;
    st->twist += (st->twistTo - st->twist) * 0.02f;
    st->ang = st->spin + 0.3f * sinf (st->t * 0.005f) * (0.5f + st->bass);
    st->morph = fminf (1.0f, st->morph + 1.0f / MORPH_CYCLES);
    st->ax += (scenes[st->scene].ax - st->ax) * 0.03f;
    st->ay += (scenes[st->scene].ay - st->ay) * 0.03f;

    sg = &st->sigil;
    if (sg->alive && ++sg->age >= sg->life) sg->alive = 0;
    if (!sg->alive && beat && goom_irand (g->gRandom, st->hit >= 1.0f ? 3 : 10) == 0) {
        sg->kind = goom_irand (g->gRandom, SIGIL_KINDS);
        sg->rot = (frand (g) - 0.5f) * 0.6f;
        sg->life = 10 + goom_irand (g->gRandom, 8);
        sg->seed = (unsigned)goom_irand (g->gRandom, 1 << 30);
        sg->age = 0;
        sg->alive = 1;
    }

    {   /* the hottest heat cools, so a held drone can't pile it up into a white sky; a kick's
           flash is below the line and untouched */
        int i, n = g->screen.width * g->screen.height;
        for (i = 0; i < n; i++)
            if (p[i].channels.g > 120) {
                p[i].channels.g = (unsigned char)(120 + (p[i].channels.g - 120) * 3 / 4);
                p[i].channels.b = (unsigned char)(120 + (p[i].channels.b - 120) * 3 / 4);
            }
    }
    draw_wraiths (g, st, p, volume, WEIGHT (st, wraiths));
    draw_sparks (g, st, data[1], p, WEIGHT (st, sparks));
    draw_fire (g, st, data[0], p, WEIGHT (st, fire));
    draw_souls (g, st, p, 0.4f + 0.6f * WEIGHT (st, fire));
    draw_ash (g, p, WEIGHT (st, ash));
    if (sg->alive) draw_sigil (g, st, sg, data[1], p);
}

void ooh_ugh_finish (PluginInfo *g, Pixel *frame)
{
    struct OohUgh *st = state (g);
    int w, h, i, x, y;
    float gain, wash, flash, sn, cs;
    if (st == NULL) return;
    w = g->screen.width; h = g->screen.height;
    sn = sinf (st->ang); cs = cosf (st->ang);
    /* the whole fire flares on a kick and swells with the low end, under a faint red wash that
       only the vignette shapes (no glow round the abyss: a round, pulsing orb took away from
       it), and a big hit flashes its hottest parts white */
    gain = 1.0f + 0.8f * st->beat * st->beat + 0.25f * st->bass;
    wash = 30 * st->beat * st->beat + 15 * st->bass;
    flash = 0.35f * st->hit;
    for (y = 0, i = 0; y < h; y++)
        for (x = 0; x < w; x++, i++) {
            Pixel *q = &frame[i];
            int hi = q->channels.r, lo = q->channels.r, white;
            if (q->channels.g > hi) hi = q->channels.g;
            if (q->channels.b > hi) hi = q->channels.b;
            if (q->channels.g < lo) lo = q->channels.g;
            if (q->channels.b < lo) lo = q->channels.b;
            white = st->white[lo] + (int)(flash * st->red[hi]);
            {   /* darkness closes in from the edges and swallows whatever lies behind the burn line */
                float ex = (2.0f * x / w - 1.0f);
                float back = ((x - 0.5f * w) * -sn + (y - 0.5f * h) * cs) / h;
                float shade = (1.0f - 0.55f * ex * ex) * (back > st->reach - 0.04f ? 1.0f - (back - st->reach + 0.04f) * 4.5f : 1.0f);
                int red = (int)((st->red[hi] * gain + wash + white) * shade);
                white = (int)(white * shade);
                q->channels.r = red > 255 ? 255 : red < 0 ? 0 : red;
                q->channels.g = q->channels.b = white > 255 ? 255 : white < 0 ? 0 : white;
            }
        }
}

void ooh_ugh_free (PluginInfo *g)
{
    free (g->update.oohUgh);
    g->update.oohUgh = NULL;
}
