/* NullPlayer port: the Ooh/Ugh effect — see ooh_ugh.h. Original work, not upstream Goom. */
#include "ooh_ugh.h"

#include <math.h>
#include <stddef.h>
#include <stdlib.h>
#include "goom_tools.h"

#define MAX_SEGS 192
#define WRAITHS 3
#define MORPH_CYCLES 90  /* how long one scene's emitters take to hand over to the next's */

enum { SIGIL_PENTACLE, SIGIL_GOAT, SIGIL_SWORD, SIGIL_CROSS, SIGIL_KINDS };

typedef struct { float x0, y0, x1, y1; } Seg;

/* A sigil is flung out of the abyss: drawn small into the feedback for a few cycles while the
   zoom carries each copy outwards, so it reads as a smeared echo, never as a picture. */
typedef struct { int kind, alive, age, life; unsigned seed; float rot; } Sigil;

typedef struct { float x, y; int drawn; } Wraith;

/* A scene: where its abyss sits (the zoom's middle, as fractions of the screen) and how much
   of each emitter it runs. filters.c holds the matching flow field, by the same index. */
typedef struct { float ax, ay, wraiths, fire, ash; } Scene;
static const Scene scenes[OOH_SCENES] = {
    { 0.50f, 0.75f, 0.5f, 0.8f, 0.0f },   /* throat */
    { 0.50f, 0.50f, 1.0f, 0.3f, 0.3f },   /* maelstrom */
    { 0.50f, 0.85f, 0.4f, 1.0f, 0.0f },   /* pyre */
    { 0.50f, 0.50f, 0.6f, 0.2f, 0.0f },   /* rift */
    { 0.50f, 0.15f, 0.7f, 0.0f, 1.0f },   /* descent */
};

struct OohUgh {
    Sigil sigil;
    Wraith wraiths[WRAITHS];
    int scene, prevScene, sceneAge, sceneLen;
    float morph;           /* 0 -> 1 as the previous scene's emitters hand over */
    float ax, ay;          /* the abyss on screen, easing towards the scene's */
    float t;               /* animation clock, runs faster with the music */
    float beat;            /* 1 on a beat, then decays */
    float hit;             /* a big hit: 1, then decays faster */
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
        float r0 = r + push * pcm[(i * 509 / steps) % 512] / 32768.0f;
        float r1 = r + push * pcm[((i + 1) * 509 / steps) % 512] / 32768.0f;
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

static float weight (struct OohUgh *st, size_t field)
{
    float from = *(const float *)((const char *)&scenes[st->prevScene] + field);
    float to = *(const float *)((const char *)&scenes[st->scene] + field);
    return from + (to - from) * st->morph;
}
#define WEIGHT(st, f) weight (st, offsetof (Scene, f))

/* Where the flames start: a wandering line across the lower third, never drawn itself. */
static float burn_y (PluginInfo *g, struct OohUgh *st, int x)
{
    float u = (float)x / g->screen.width * 5.0f + st->t * 0.012f, sum = 0, amp = 1;
    int o;
    for (o = 0; o < 3; o++, u *= 2.1f, amp *= 0.5f) {
        int i = (int)floorf (u);
        float f = u - i;
        float a = (hash ((unsigned)i * 1013u + 31u + o) & 0xffff) / 65535.0f;
        float c = (hash ((unsigned)(i + 1) * 1013u + 31u + o) & 0xffff) / 65535.0f;
        sum += amp * (a + (c - a) * f);
    }
    return g->screen.height * (0.84f - 0.16f * sum / 1.75f);
}

/* Flames along the burn line, fed into the feedback so they lick upwards into the sky. */
static void draw_fire (PluginInfo *g, struct OohUgh *st, const gint16 *pcm, Pixel *p, float amount)
{
    int w = g->screen.width, h = g->screen.height, x, k;
    float px = 0, py = 0;
    if (amount < 0.02f) return;
    /* the waveform traced along the burn line: the swirl lifts each copy into smoke banks */
    for (x = 0; x < w; x += 2) {
        float y = burn_y (g, st, x) - h * 0.12f * fabsf ((float)pcm[x * 511 / (w > 1 ? w - 1 : 1)]) / 32768.0f;
        if (x) line (p, w, h, px, py, (float)x, y, 2.0f, (int)(160 * amount), (int)(60 * amount * st->beat));
        px = (float)x; py = y;
    }
    for (x = 0; x < w; x += 3) {
        float v = fabsf ((float)pcm[x * 511 / (w > 1 ? w - 1 : 1)]) / 32768.0f;
        float tall = h * (0.02f + 0.20f * v * (0.4f + st->beat)) * (0.4f + 0.6f * frand (g)) * amount;
        int top = (int)tall, base = (int)burn_y (g, st, x);
        float phase = frand (g) * 6.28f;
        for (k = 0; k < top; k++) {
            float t = (float)k / tall, heat = (1 - t) * (1 - t) * (0.35f + 0.65f * v);
            int xx = x + (int)(sinf (k * 0.09f + phase) * 3.0f * t);
            plot (p, w, h, xx, base - k, (int)(150 * heat), (int)(70 * heat * heat * st->beat));
        }
    }
    if (st->beat >= 1.0f)   /* embers */
        for (k = (int)((goom_irand (g->gRandom, 6) + 2) * amount); k > 0; k--) {
            int ex = goom_irand (g->gRandom, w), ey = (int)burn_y (g, st, ex) - goom_irand (g->gRandom, h / 8 + 1);
            plot (p, w, h, ex, ey, 255, 220);
            plot (p, w, h, ex + 1, ey, 200, 160);
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

    st->beat = beat ? 1.0f : st->beat * 0.82f;
    st->hit = g->sound.timeSinceLastBigGoom == 0 ? 1.0f : st->hit * 0.7f;
    st->t += 0.25f + 0.6f * volume + 0.4f * st->beat;
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

    draw_wraiths (g, st, p, volume, WEIGHT (st, wraiths));
    draw_fire (g, st, data[0], p, WEIGHT (st, fire));
    draw_ash (g, p, WEIGHT (st, ash));
    if (sg->alive) draw_sigil (g, st, sg, data[1], p);
}

void ooh_ugh_finish (PluginInfo *g, Pixel *frame)
{
    struct OohUgh *st = state (g);
    int w, h, i, x, y;
    float cx, cy, reach, glow, core;
    if (st == NULL) return;
    w = g->screen.width; h = g->screen.height;
    cx = w * st->ax; cy = h * st->ay; reach = 1.0f / (0.75f * h);
    glow = 50 + 100 * st->beat * st->beat;   /* the sky strobes on the kick */
    core = 255 * st->hit;                    /* a big hit whitens the abyss */
    for (y = 0, i = 0; y < h; y++)
        for (x = 0; x < w; x++, i++) {
            Pixel *q = &frame[i];
            int hi = q->channels.r, lo = q->channels.r, add, white;
            float dx = (x - cx) * 0.6f, dy = y - cy, d = 1.0f - sqrtf (dx * dx + dy * dy) * reach;
            if (q->channels.g > hi) hi = q->channels.g;
            if (q->channels.b > hi) hi = q->channels.b;
            if (q->channels.g < lo) lo = q->channels.g;
            if (q->channels.b < lo) lo = q->channels.b;
            add = d > 0 ? (int)(glow * d * d) : 0;
            white = st->white[lo] + (d > 0.7f ? (int)(core * (d - 0.7f) / 0.3f) : 0);
            {   /* darkness closes in from the edges and swallows the bottom */
                float ex = (2.0f * x / w - 1.0f), ey = (float)y / h;
                float shade = (1.0f - 0.55f * ex * ex) * (ey > 0.8f ? 1.0f - (ey - 0.8f) * 4.5f : 1.0f);
                int red = (int)((st->red[hi] + add + white) * shade);
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
