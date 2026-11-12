// Modified for NullPlayer (2026-11-12): scripts load from a directory
// handed in (POSIX directory reading, the extension matched without
// case) into the Smear's own lists, every Environment knowing its
// Smear; the move is the one the host holds (smearapi's "set move",
// without the shared memory) instead of a weighted random pick; the
// four Choose functions share one weighted picker.  See LICENSE.TXT.

#include "smear.h"
#include <dirent.h>

static inline int
BasicRandom(int n)
{
	return rand() % n;
}


static inline int
WeightedRandom(int n)
{
	int n2 = BasicRandom(n * n);
	int w;

	w = n - (int)sqrt(n2) - 1;

	if (w < 0)
		w = 0;

	if (w >= n)
		w = n - 1;

	return w;
}


static void
LoadAllScripts(SmearState *s, const char *base, const char *dir, const char *ext, ScriptList *sl)
{
	char		path[4096];
	DIR		*dp;
	struct dirent	*de;
	Environment	*ep;
	size_t		len, elen = strlen(ext);

	sl->count = 0;

	snprintf(path, sizeof(path), "%s/%s", base, dir);
	if ((dp = opendir(path)) == (DIR *)0)
		return;

	while ((de = readdir(dp)) != (struct dirent *)0 && sl->count < MAX_ENVIRONMENTS)
	{
		len = strlen(de->d_name);
		if (len <= elen || stricmp(de->d_name + len - elen, ext) != 0)
			continue;

		snprintf(path, sizeof(path), "%s/%s/%s", base, dir, de->d_name);
		if ((ep = ParseFile(path)) == (Environment *)0)
			continue;

		ep->eState = s;
		ep->eFile = strdup(de->d_name);

		sl->list[sl->count++] = ep;
	}

	closedir(dp);
}


static void
LoadDummyScript(SmearState *s, ScriptList *sl, char *script)
{
	Environment	*ep;

	if (sl->count > 0)
		return;

	ParserSetupDummyScript(script);

	if ((ep = ParseFile((char *)0)) == (Environment *)0)
		return;

	ep->eState = s;
	ep->eFile = strdup("Internal");
	sl->list[sl->count++] = ep;
}


// Picks with upstream's weighting, then moves the pick to the end of the
// list so it is the least likely next time.
static Environment *
ChooseScript(ScriptList *sl)
{
	int		w;
	Environment	*p;

	if (sl->count == 0)
		return (Environment *)0;

	w = WeightedRandom(sl->count);

	p = sl->list[w];

	if (w < sl->count - 1)
	{
		int	loop;

		for (loop = w; loop < sl->count - 1; loop++)
			sl->list[loop] = sl->list[loop + 1];

		sl->list[sl->count - 1] = p;
	}

	return p;
}


Environment	*
ChooseMoveScript(SmearState *s)
{
	return s->heldMove;
}


Environment	*
ChooseColorScript(SmearState *s)
{
	return ChooseScript(&s->colors);
}


Environment	*
ChooseWaveFormScript(SmearState *s)
{
	return ChooseScript(&s->waveforms);
}


Environment	*
ChooseParticleScript(SmearState *s)
{
	return ChooseScript(&s->particles);
}


void
LoadEverything(SmearState *s, const char *dir)
{
	LoadAllScripts(s, dir, "Moves", ".sms", &s->moves);
	LoadDummyScript(s, &s->moves, "(declare init (set $usePolar 1) (set $useAspect 1) (set $a0 (+ 2 (rnd 16))) (set $a1 (+ .002 (rnd .02))) (set $a2 (+ .002 (rnd .006)))) (declare move (set $srcRadius (pos (- $radius $a2))) (set $srcTheta (+ $theta (* $a1 (sin (* $a0 $radius))))))");

	LoadAllScripts(s, dir, "Color", ".scs", &s->colors);
	LoadDummyScript(s, &s->colors, "(declare init (set $useHSV 1) (set $useTime 1)) (declare color (set $h (* $time 0.05)) (set $v (* $value 2.0)) (set $s (* 2 (- 1 $value))))");

	LoadAllScripts(s, dir, "Waveform", ".sws", &s->waveforms);
	LoadDummyScript(s, &s->waveforms, "(declare init (set $paths 1) (set $steps 256)) (declare newline (set $angle (+ $angle 0.015))) (declare waveform (polar $radius $theta (- (* $step 2.0) 1.0) $mid) (cart $x0 $y0 $radius (+ $theta $angle)))");

	LoadAllScripts(s, dir, "Particle", ".sps", &s->particles);

	s->heldMove = s->moves.list[0];
}
