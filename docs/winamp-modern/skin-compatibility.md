# Winamp Modern (`.wal`) skin compatibility

Every Winamp 5.x Modern skin NullPlayer has been tested against, what grade it gets, and what is
known to be outstanding on it. **Measured 2026-09-06** against `a916b38a`, over the 79 archives
installed on the test machine — **75 distinct skins**, because four archives are byte-identical copies
circulating under a second filename.

Current picture: **47 B · 25 C · 3 F**, of which 6 letters come from a
person using the skin and 69 are provisional (below).

## How the grades were arrived at, and how far to trust them

The rubric is in `.claude/skills/wal-skin-report/SKILL.md`. It grades **the user's experience of the
skin** — does every surface draw, are the controls live, do the animations run, do the menus work.
Two kinds of letter appear in the table and they are not equally good:

- **live** — someone drove the skin and filled in the full report. Six skins. These are authoritative.
  They publish **"as of"** their date, because all six were measured before 77 changes landed in the
  skin engine, and under the staleness rule a grade goes stale when the engine moves under it.
- **provisional** — derived from a headless pass: the skin is loaded, every container and layout it
  declares is rendered to an image, its scripts are started, and its artwork lookups, unimplemented
  method calls and surface routing are recorded. No one has clicked anything.

**A provisional letter is worth about ±1 letter.** That is measured, not a guess: on the six skins
that have both, the headless method and the human disagreed four times — three times it was one letter
*harsher* than the person (cPro Insomnis, Insomnis v2, das-skin-prev) and once it was one letter
*kinder* (LOBE, headless B against a driven C). So read a provisional B as "B or C" and a provisional
C as "C, possibly B". Where both exist, **the live letter is the one shown**.

**No skin can earn an A here.** The rubric's A bar is "nothing a user would report", and nothing but a
user can establish that. The best a headless pass awards is B.

What each letter means in this table:

| | Bar | What settles it headlessly |
|---|---|---|
| **B** | Fully usable; gaps are cosmetic or confined to one non-essential subsystem | Every surface it declares has a home, and it calls no unimplemented script method |
| **C** | Usable with visible defects | A surface has no window in the skin and a standard NullPlayer window stands in for it, **or** it calls a MAKI method NullPlayer does not implement — dispatch is fail-closed, so each such call abandons its whole handler, not just that step |
| **D** | A whole window, tab or pane is blank or unreachable | A container the skin declares renders an empty image |
| **F** | Fails to load, or renders nothing | The archive will not open, or the main player window is blank |

Two things deliberately do **not** move the letter, because they were tested and do not track quality:

- **Unresolved artwork.** cPro Insomnis is a driven **B** with 13 of its own bitmap ids unresolved;
  cPro T2T is a driven **C** with 15. Many "missing" ids are also deliberate — a skin points an
  element at `none`, `null` or `window.background.hidden` precisely so that nothing draws. Unresolved
  art is listed per skin under *Known outstanding* and is left out of the grade.
- **The internal compatibility level** (`full` / `degraded` / `unsupported`). It counts diagnostics
  emitted while loading, not what you see: Itemskin reads `unsupported` and draws correctly.

The **Skinned** column is a separate, purely structural measurement from
`scripts/wal_skin_census.sh`: *Fully skinned* means every surface the skin declares has a home and
NullPlayer's own windows wear its border; *Player skinned* means our windows fall back to the plain
frame because the skin ships no reusable border; *Partly skinned* means a surface has no window in
this skin at all — usually because the skin predates the feature, not because anything is wrong.

## The skins

| Skin | Author | Grade | Skinned | Known outstanding |
|---|---|:--:|:--|---|
| **3D**<br>`Darjah 1.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `play/on.png` |
| **AlienPADD**<br>`PaddPreview.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `player.normal.button.menu.btn`, `player.shade.shade`; 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Anaheim Player 01**<br>`Anaheim_Player_01.wal` | Anaheim Electronics Japan | B<br><sub>provisional</sub> | Fully skinned | 2 error-severity load finding(s) |
| **Anexa**<br>`Anexa.wal` | nynako / skin-zone | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Big Bento Modern**<br>`Big Bento Modern.wal` | Victhor, Martin Pöhlmann, Ben Allison | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `frame.center`, `infocomp.button.icon.bg`, `infocomp.button.icon.lyricfinder`, `infocomp.button.icon.searchvideo`, `player.button.repeat.normal`; 1 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `config.button.hover`; 27 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Big Bento Modern - Windows 10 edition**<br>`Big Bento Modern Windows 10 edition.wal` | Victhor, Martin Pöhlmann, Ben Allison | B<br><sub>provisional</sub> | Fully skinned | 6 bitmap id(s) it references do not resolve, leaving a visible gap: `frame.center`, `infocomp.button.icon.bg`, `infocomp.button.icon.lyricfinder`, `infocomp.button.icon.searchvideo`, `player.button.repeat.normal`, `wtf`; 1 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `config.button.hover`; 27 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Big Bento Modern - Windows 10 edition Light**<br>`Big Bento Modern Windows 10 edition Light.wal` | Victhor, Martin Pöhlmann, Ben Allison | B<br><sub>provisional</sub> | Fully skinned | 6 bitmap id(s) it references do not resolve, leaving a visible gap: `frame.center`, `infocomp.button.icon.bg`, `infocomp.button.icon.lyricfinder`, `infocomp.button.icon.searchvideo`, `player.button.repeat.normal`, `wtf`; 1 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `config.button.hover`; 27 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Big Bento Modern Light**<br>`Big Bento Modern Light.wal` | Victhor, Martin Pöhlmann, Ben Allison | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `frame.center`, `infocomp.button.icon.bg`, `infocomp.button.icon.lyricfinder`, `infocomp.button.icon.searchvideo`, `player.button.repeat.normal`; 1 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `config.button.hover`; 27 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **BLAKK**<br>`BLAKK.wal` | Dwight Robinson aka Vica. | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.remote-toggles-ml-text-off`; 5 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Canum**<br>`canum_winamp_by_burnsplayguitar_d2xhizu.wal` | burnsplayguitar | C<br><sub>provisional</sub> | Partly skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `displayscreen`; no library, playlist window of its own; 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140) |
| **Core X5**<br>`Core-X5.wal` | Skin Consortium | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **CornerAmp Redux**<br>`corneramp_redux.wal` | 9 of Nine, Evil Pumpkin, RazorZero | B<br><sub>provisional</sub> | Fully skinned | 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **cPro - Bento**<br>`2222-cPro__Bento.wal` | — | C<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `custom.repeat.0`, `custom.shuffle.0`; unimplemented MAKI: `enumitem` ×4; 13 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro - Bento**<br>`cpro_interface_by_jinghis_d301whe.wal` | — | C<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `custom.repeat.0`, `custom.shuffle.0`, `custom.winamp`, `size.khzkbps`; unimplemented MAKI: `enumitem` ×4; 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro - Das Skin**<br>`cpro-das-skin-prev.wal` | — | **B**<br><sub>live, as of 2026-08-31</sub> | Fully skinned | unimplemented MAKI: `enumitem` ×4; 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro - Insomnic**<br>`cPro_Insomnis_v2_by_zrco.wal` | — | **B**<br><sub>live, as of 2026-08-31</sub> | Fully skinned | unimplemented MAKI: `enumitem` ×4; 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro - MMD**<br>`221721-cPro_MMD.wal` | — | C<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `beat.0.right`, `player.led.off`; unimplemented MAKI: `enumitem` ×4; 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro - Venus ALPHA Port**<br>`cPro_Venus_Alpha_port_by_Victhor_v1.3.1.wal` | RPeterClark - Victhor | C<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `info.vol.bg`, `vol.bg`, `volume.bg2`; unimplemented MAKI: `enumitem` ×4; 10 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro - WMP12**<br>`221955-cPro__Winamp_Media_Player_12.wal` | — | C<br><sub>provisional</sub> | Fully skinned | unimplemented MAKI: `enumitem` ×4; 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro - XPS**<br>`cPro_T2T-by-MAC.wal` | — | **C**<br><sub>live, as of 2026-08-31</sub> | Fully skinned | 15 bitmap id(s) it references do not resolve, leaving a visible gap: `custom.repeat.0`, `custom.shuffle.0`, `custom.winamp`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`…; unimplemented MAKI: `enumitem` ×4; 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro2 - Dark Aluminum**<br>`cpro2_dark_aluminum_final_by_victhor_d6necra.wal` | Victor Brocaz | C<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `cpro2.eq.auto.overlay.0`, `cpro2.eq.on.overlay.0`, `cpro2.xfade.overlay.0`; 1 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `s.button.mute.over.0`; unimplemented MAKI: `enumitem` ×2, `enumobject` ×26, `getnumobjects` ×4; 8 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 3 error-severity load finding(s) |
| **cPro2 - Styler**<br>`cPro2_Styler_by_Victhor.wal` | Victor Brocaz | C<br><sub>provisional</sub> | Fully skinned | 6 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `playback.button.mute.over.0`, `playback.button.rep.over.0`, `playback.button.shuf.over.0`, `s.button.mute.over.0`; unimplemented MAKI: `enumitem` ×2, `enumobject` ×14, `getnumobjects` ×4; 9 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 3 error-severity load finding(s) |
| **cPro2 - Styler // Radiance version**<br>`cPro2_Styler_Radiance_by_Victhor.wal` | Victor Brocaz | C<br><sub>provisional</sub> | Fully skinned | 6 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `playback.button.mute.over.0`, `playback.button.rep.over.0`, `playback.button.shuf.over.0`, `s.button.mute.over.0`; unimplemented MAKI: `enumitem` ×2, `enumobject` ×14, `getnumobjects` ×4; 9 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 3 error-severity load finding(s) |
| **cPro2 - Styler // Touchscreen version**<br>`cPro2_Styler_Touchscreen_by_Victhor.wal` | Victor Brocaz | C<br><sub>provisional</sub> | Fully skinned | 6 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `playback.button.mute.over.0`, `playback.button.rep.over.0`, `playback.button.shuf.over.0`, `s.button.mute.over.0`; unimplemented MAKI: `enumitem` ×2, `enumobject` ×14, `getnumobjects` ×4; 9 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 3 error-severity load finding(s) |
| **cPro_Insomnic**<br>`cPro_Insomnis_by_zrco.wal` | — | **B**<br><sub>live, as of 2026-08-31</sub> | Fully skinned | 13 bitmap id(s) it references do not resolve, leaving a visible gap: `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`…; unimplemented MAKI: `enumitem` ×4; 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro_Winamp Modern**<br>`211786-Cpro_Winamp_Modern.wal` | — | C<br><sub>provisional</sub> | Fully skinned | 13 bitmap id(s) it references do not resolve, leaving a visible gap: `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`…; unimplemented MAKI: `enumitem` ×4; 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **D-Reliction**<br>`4-drelictionreleasepic.wal` | — | C<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `Layer`, `notifier.bg.inner`, `player.Beat`; unimplemented MAKI: `isobjectvalid` ×6; 30 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 3 error-severity load finding(s) |
| **Defix Hi-End 200**<br>`Defix Hi-END 200.WAL` | Tankevich Denis | **B**<br><sub>live, as of 2026-08-18</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `FRAMING_GLASS.window`, `Lighting.Element`; 14 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **DewyTears**<br>`DewyTears_BlackGlassV2.5.wal`<br><sub>also installed as `dewytears_v2_5_by_dewytear_d2yn025_BlackGlass.wal`</sub> | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **DewyTears**<br>`DewyTears_PinkGlassV2.5.wal`<br><sub>also installed as `dewytears_v2_5_by_dewytear_d2yn025_PinkGlass.wal`</sub> | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **DewyTears**<br>`DewyTears_TransparentV2.5.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Diablo 4 Skills V2**<br>`Diablo IV Skills V2.wal` | sambaneko | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `paragon.seeker.point` |
| **Ebonite**<br>`Ebonite_2_1.wal` | WinstonGFX and SLoB | C<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `brightness.bg1`; unimplemented MAKI: `enumgammagroup` ×2, `setchecked` ×2; 7 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 4 error-severity load finding(s) |
| **Enkera**<br>`Enkera.wal` | 883 | B<br><sub>provisional</sub> | Fully skinned | 4 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **EPS (Egor Petrov Systems)**<br>`EPS_High-End_System_v1_test.wal` | Egor Petrov | C<br><sub>provisional</sub> | Player skinned | 9 bitmap id(s) it references do not resolve, leaving a visible gap: `meterback`, `pausetip`, `peak`, `playtip`, `shade.bg.met`, `speaker3`…; unimplemented MAKI: `setchecked` ×2; 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140); 13 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **Firefox**<br>`Firefox.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Formamp**<br>`Formamp.wal` | coronerss | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Hal's Eye**<br>`1-Hal__s_Eye_v1_2.wal` | -=RoNtZ=- | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `about.bg`; 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Hatsune Miku 5 Winamp Skin**<br>`hatsune_miku_5_winamp_by_kaza_sou_d6izotp.wal` | kazasou feat. msdzero | F<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **HeadAMP**<br>`HeadAMP.wal` | sambaneko | B<br><sub>provisional</sub> | Fully skinned | 27 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Impulse**<br>`impulse_by_a_t_o_m_i_c_d4wcub.wal` | a-t-o-m-i-c | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `window.normal.resizer`; 13 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Itemskin**<br>`Itemskin.wal` | — | C<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `player.main.extras.textbox.left`, `player.songinfo.stereo`, `player.songinfo.stereomono`; unimplemented MAKI: `setchecked` ×4; 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 2 error-severity load finding(s) |
| **JVC Tape**<br>`jvc.tape.v0.5.wal` | — | C<br><sub>provisional</sub> | Partly skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `pl.button.bg`, `pl.button.small`; no library window of its own; 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140); 3 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **K-jr**<br>`K-jr.wal`<br><sub>also installed as `k_jr_winamp_skin_by_marisa85_d329ymw.wal`</sub> | Marisa85 | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `img/bt_crf.png`, `img/bt_none.png` |
| **LOBE**<br>`Lobe.wal` | graphics and coding: boostr29 | **C**<br><sub>live, as of 2026-08-21</sub> | Fully skinned | 14 bitmap id(s) it references do not resolve, leaving a visible gap: `border`, `drawer.left.bg`, `drawer.right.bg`, `main.00002`, `main.attatchment`, `main.glass.lower`…; 1 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `thinger.over`; 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Love is War Miku Hatsune Winamp Skin**<br>`Love is War Miku.wal` | — | F<br><sub>provisional</sub> | Fully skinned | 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Love is War Miku v2 Winamp Skin**<br>`Love Is War Miku V2.wal` | maxim cryseria | F<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `player.volbg`, `player.volume`; 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Meridian**<br>`meridian.wal` | Neuroskins | B<br><sub>provisional</sub> | Fully skinned | 18 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **micro**<br>`micro.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `component.region.bottom.left`, `component.region.bottom.right`, `component.region.top.left`, `component.region.top.right`; 4 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **MMD3**<br>`MMD3-4-5.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `pledit.buttonbg.add`, `pledit.buttonbg.misc`, `pledit.buttonbg.options`, `pledit.buttonbg.rem`, `pledit.buttonbg.sel`; 22 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **MMD3**<br>`mmd3.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 23 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **MoonLight**<br>`MoonLight.wal` | Marisa85 | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Multipass**<br>`multipass_1_4_by_rpeterclark_d5lwjv.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Nokia_5220**<br>`The_Nokia_5220_XpressMusic.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Nullsoft Winamp 2000 SP4**<br>`Nullsoft.Winamp.2000.SP4.Lite.wal` | Initial Graphics by Zsolt Vajda // Coding by Victor Brocaz // Modified by Gordon Freeman | B<br><sub>provisional</sub> | Fully skinned | 7 bitmap id(s) it references do not resolve, leaving a visible gap: `window.normal.left2`, `window.normal.middle2`, `window.plvis.display.bg`, `window.shade.region.bottom.left`, `window.shade.region.bottom.right`, `window.shade.region.top.left`…; 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Overdrive 2**<br>`Overdrive_2.wal` | Ian Novack aka Spoonman aka Novispoon | C<br><sub>provisional</sub> | Partly skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.anim.volume`; no library window of its own; 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140); 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Pokemon DS**<br>`PokemonDS.wal` | SpaceKitty | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Pure Inspired for Winamp**<br>`Pure Inspired.wal`<br><sub>also installed as `pure_inspired_for_winamp_by_marisa85_d35ix2r.wal`</sub> | Marisa85 | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `img/bt_caN.png` |
| **S7Reflex**<br>`S7Reflex.wal` | daniel sioneanu | B<br><sub>provisional</sub> | Fully skinned | 22 bitmap id(s) it references do not resolve, leaving a visible gap: `drawer.button.close.bg`, `player.button.repeat.bg`, `player.button.shuffle.bg`, `player.display.bg.center`, `player.display.bg.left`, `player.display.bg.right`…; 6 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Shield_AMP**<br>`Shield_Amp.wal` | team skinconsortium [graphic by Mike a.k.a WistonGFX coding by Faris Wijaya a.k.a Faris18787 and SLoB] | C<br><sub>provisional</sub> | Fully skinned | unimplemented MAKI: `setchecked` ×2, `setxmlparam` ×2; 6 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 3 error-severity load finding(s) |
| **Sing it, Kitty**<br>`SingItKitty.wal` | SpaceKitty | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Sony**<br>`Sony_Walkman.wal` | Petrol Designs | C<br><sub>provisional</sub> | Partly skinned | no library, playlist window of its own; 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140); 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Styx**<br>`Styx.wal` | — | C<br><sub>provisional</sub> | Fully skinned | unimplemented MAKI: `getmode` ×2, `setchecked` ×12; 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 7 error-severity load finding(s) |
| **T-800**<br>`Bio-Nid.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **T-800**<br>`Rika.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **T-800**<br>`T800.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.main.pause`; 1 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `player.over` |
| **Tom**<br>`TomK.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | 3 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **TRON___Legacy**<br>`TRON___Legacy.wal` | — | C<br><sub>provisional</sub> | Partly skinned | no library window of its own; 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140); 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Ujola Cat**<br>`Ujola Cat.wal` | sambaneko | B<br><sub>provisional</sub> | Fully skinned | 7 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Wiimote**<br>`Wiimote.wal` | SpaceKitty | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Winamp3 Base Skin**<br>`Winamp 3.0 Default.wal` | — | C<br><sub>provisional</sub> | Partly skinned | no library window of its own; 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140); 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Winamp5 Base Skin**<br>`nullsoft_media_player_10_forked_by_hb860-d7h03zd.wal` | — | C<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `component.bottom.left.corner`, `component.bottom.right.corner`, `component.bottom.stretch`, `component.top.right.corner`; unimplemented MAKI: `getmode` ×2, `onleftbuttondown` ×2; 3 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 2 error-severity load finding(s) |
| **Winamp5 Base Skin**<br>`winampmodern566.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 10 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Windpws Media Player 11 BlueVU**<br>`WMP11-BlueVU.wal` | X - Man | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `seeker.bg.vertical.right`; 5 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 3 error-severity load finding(s) |
| **ZDL-AMP SIX-TRACK REEL-TO-REEL WA-3**<br>`ZDL_Reel-To-Reel_Analog_Tape_Machine.wal` | Mike Zee | B<br><sub>provisional</sub> | Fully skinned | 4 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |

## Known issues that affect every skin

These are open items in the skin engine, not faults in any particular skin. A skin graded B can still
show any of them.

**Windows and borders**

- NullPlayer's own windows — the library and the video pane — can only be dragged by their title
  strip, not by their body, the way a skin's own windows can (B60).
- A skin whose window border is built by a second, overlapping window can load its inner layout before
  that border has a client area to sit in, leaving the border half-built until something else redraws
  it. Seen on Defix's detached visualizer (B71).
- At UI sizes that are not a whole multiple — 105%, for instance — hairline seams can appear along the
  boundaries between bands of the player window when only part of it repaints (B80).

**Controls and interaction**

- Clicking once on a visualization area built into the player window does nothing; the click is
  swallowed before it reaches the skin (B58).
- A skin that reads the mouse position gets it relative to its own window, where Winamp answers
  relative to the screen. Skins using it to detect a screen edge will misfire (B123).
- Skins offering several memory or preset slots can find them all writing to the same one (B74).
- A skin that includes the same script file twice runs each of its handlers twice (B75).

**Things that stay blank or dead**

- A widget brought up part-way through a session is not told what is already playing, so anything it
  draws from the track — cover art, title, elapsed time — stays blank until the next track (B82).
- A visualization pane embedded inside a larger panel may never start its engine (BB34).
- Some ClassicPro skins' information panel is empty: it walks its own object list with two script
  calls NullPlayer does not implement, and an unimplemented call abandons the whole handler (B99).
- One arithmetic fault inside a script — a division by zero, which Winamp tolerates — abandons the
  rest of that handler here. Seen on Shield_Amp's song ticker (B65).
- A group sized from a picture rather than a text label collapses to nothing and takes its contents
  with it. This is why the stock Winamp Modern skin's title-bar menus do not open (B79).
- The Options entry in a skin's menu bar opens a thin NullPlayer menu rather than the full set of
  player options (B84).
- Three Miku-family skins draw an empty main player window while every other window works (B145).

**Performance and animation**

- WMP11-BlueVU repaints its warped display layers slowly enough to be visible; roughly half the cost
  has been fixed and the rest is open (B119).
- Layout and tab changes cut straight to the new state; Winamp animates the transition (BB14).

## How this page was produced

1. `scripts/wal_skin_census.sh` renders every installed archive headlessly, probes the
   NullPlayer-owned windows, and writes one row per archive stamped with the git rev it measured at.
   Run twice on an unchanged tree it produced identical output.
2. A full-corpus probe pass rendered all **674 layouts** across the 79 archives and recorded, per
   skin, its script programs and their failures, its unimplemented-method calls, its artwork lookups
   and its surface routing. Every provisional grade and every *Known outstanding* entry comes from
   that pass.
3. Every rendered layout was measured for how much of its canvas it actually paints — which is what
   found the three empty main windows, and what distinguishes them from the irregular silhouettes
   (Bio-Nid 22%, HeadAMP 30%, Ujola Cat 34%) that are meant to look like that.
4. The 36 archives shipping the author's own `screenshot.png` had it compared against our render,
   asking only whether it is recognisably the same skin and ignoring playback state, track text and
   which windows are open. Nine were flagged; five were the author shipping a cropped or shade-mode
   promo shot, one was a fault in the pairing, and three were real.
5. The six live letters come from `/wal-skin-report` sessions driven by a person and are unchanged.

Per-skin engineering notes live in `skills/winamp-modern-skin-guide/skins/` — one file per skin, all
75 covered; the index is `skills/winamp-modern-skin-guide/skins.md`.
