# WACUP-era skins

Reference for the `winamp-modern-skin-guide` skill.

**WACUP** ("Winamp Community Update Project") is a separate Winamp-derived player with a superset of
Winamp 5.x's plugin surface. A `.wal` skin written for it is still an ordinary Wasabi/MAKI skin — it
loads and runs here like any other — but it may carry a second set of branches for surfaces stock
Winamp never had. Two of the 36 measured skins do: the four Big Bento Modern variants (two script
sets, since the `Light` editions borrow the base's scripts) and, in passing, Defix Hi-END.

This file exists so the question *"should we have a WACUP mode?"* is answered once. **No.** The
measurement is below.

## How a skin asks, and what we answer

A WACUP-aware skin sniffs for the host by looking for one of its files:

```
System.getSettingsPath()  →  <settings>/WACUP_Tools/koopa.ini
```

The probe result is cached into the skin's own configuration (`Is Wacup`, `wacupCheck` in a hidden
section) and re-read by every script that needs it. Big Bento repeats this in **16 scripts**; there is
also a dedicated `wacup_checker.maki`.

**We answer truthfully: the file is not there, and `Is Wacup` reads `0`.** That is deliberate and it
is load-bearing — B37 fixed the shade titlebar drawing **WACUP** over **WINAMP** precisely by letting
the probe fail. Do not reverse it to unlock a feature.

> **`getSettingsPath` must still be implemented, or the skin dies.** The probe sits near the top of
> nearly every script, so before it was answered **23** of Big Bento's `onScriptLoaded` handlers
> aborted on it and everything they would have laid out afterwards never ran — the menu bar, the
> cover art, the tab captions. Answering "not WACUP" is a *branch*; failing the call is an abort.
> That distinction is the whole of B37.

## What the WACUP branch actually gates — measured

Big Bento's base skin carries **69** `wacup`/`koopa` references across its compiled scripts. They
decompose into almost nothing:

| What | Detail |
|---|---|
| The probe itself | `/WACUP_Tools/koopa.ini`, `wacupCheck`, `Is Wacup` — one mechanism, repeated in 16 scripts |
| Branding | `window.titlebar.text.wacup`, `player.button.bolt.wacup.{n,h,d}`, `infocomp.branding.wacup`, a forum URL |
| A label swap | `Show WACUP Logo` ↔ `Show Winamp Logo`, a user setting under `{F1036C9C-…}` |
| Config-page rows | `wacup_checker.maki` shows/hides the WACUP-only rows (`integrate.waveseeker.*`, `show.winamp.logo.*`) |

**No functionality is gated on it.** A WACUP mode would buy a logo and a bolt button. That is why
there is no `isWACUP` flag in the engine and why adding one is not an improvement: it would be a
quirks switch with nothing behind it, and the standing rule here is to batch work by *capability*, not
by skin or by dialect.

## The trap: WACUP-only *surfaces* are gated on ordinary settings, not on the dialect

This is the part that looks like it needs a WACUP concept and does not.

Big Bento's **integrated Waveform Seeker** — a WACUP plugin that replaces the classic seek bar — is
driven by its own user setting, not by `Is Wacup`:

```
{F1036C9C-3919-47ac-8494-366778CF10F9};Use integrated Waveform Seeker
```

15 scripts read it, and `cbuttons.maki` is the one that actually drives the surfaces
(`wdh.waveseeker`, `waveseeker.rounder`, `waveseeker.rounder.bg`). So hosting a real waveform seeker
there would need **no dialect concept at all** — it is the ordinary hosted-surface path.

**But it is unreachable today, and the blocker is the skin.** `WINAMP_MODERN_RENDER_SETTINGS=1` on a
non-WACUP host shows that setting is **not registered at all**: `wacup_checker.maki` only creates the
option when the koopa.ini probe succeeds. So the user cannot switch it on, `cbuttons.maki` never
reveals the holder, and a surface hosted there would be inert. Making it reachable means answering the
probe affirmatively — which the section above rules out.

Anyone picking this up needs a design for offering the capability *without* impersonating WACUP.
NullPlayer already has the engine for it (`Waveform/WaveformCacheService.swift`, `BaseWaveformView`,
`Windows/ModernWaveform/`).

## What a WACUP-era skin leaves behind on a non-WACUP host

The branches a skin takes when its probe fails are the ones least likely to have been exercised by its
author, so this is where latent skin bugs live. Two measured examples, both in the same 40px strip:

- **`hold="none"` on a plugin holder.** `wdh.waveseeker` is a `<windowholder … autoopen="0"
  hold="none"/>` — the box reserved for the plugin. `none` means *this holder holds nothing*; reading
  it as an unknown component painted an inert slab over the seek bar underneath (BB12). See
  [components.md](components.md) → *Component hosting*.
- **A hide that strands the user.** Big Bento's `seek.maki` hides its only seek slider on mouse-up,
  which on WACUP would be invisible because the waveform seeker occupies that strip anyway (BB16).
  See [scripting.md](scripting.md) → *A layout must not be left with no way to seek*.

Neither was fixed by branching on WACUP; both were fixed by rules that key on what the *layout*
declares. Prefer that shape.
