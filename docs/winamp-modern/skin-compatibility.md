# Winamp Modern (`.wal`) skin compatibility

Every Winamp 5.x Modern skin NullPlayer has been tested against, what grade it gets, and what is
known to be outstanding on it. **Measured 2026-09-06** against `a916b38a`, over the 79 archives
installed on the test machine — **75 distinct skins**, because four archives are byte-identical copies
circulating under a second filename. Two more, PiOnNeR_AMP2 and XENERGY (the #556 reporting skins),
were added on 2026-10-14 from the same kind of headless pass, at `5578de74`, and eight more on
2026-10-17 at `9f4388cc` (cPro_Ayon Port, Megurine Luka, Motorhead, Onyx, Study Skinning, Tekken
Lili, TOX Milla, and Hatsune Miku x Megurine Luka). Those eight come from `wal_skin_census.sh` plus
the paint measurement only: the probe that counts mouse-hooked objects hit-testing rejects was not
run on them, so their *Known outstanding* never lists that. Four of them (Megurine Luka, Tekken
Lili, TOX Milla, Hatsune Miku x Megurine Luka) render a near-empty main window headless — 0–6% of
the canvas — and draw in full in the running app, so they are graded from the live window, not F. Twenty-five more joined on 2026-10-22, the first
corpus intake promoted to gold (`admitted_rev` 69dbc2ee), from the same headless probes plus a live
look at each; 1010 Fullscreen is graded from that live look. Twenty-five more joined on 2026-10-24, corpus
intake #2 (`admitted_rev` 2987be4e), graded the same way from a `wal_skin_census.sh`
pass at promotion; the user passed all 25 in the app. Their *Known outstanding* comes from the census
only, so it never lists unimplemented MAKI calls or mouse-hooked objects hit-testing rejects.
Twenty-five more joined on 2026-10-26, corpus intake #3 (`admitted_rev` fc3043cf), graded the same
way and passed by the user in the app. Twenty-five more joined on 2026-10-27, corpus intake #4
(`admitted_rev` 18622d92), graded the same way (`wal_skin_census.sh` at promotion) and passed by the
user in the app; five carry an open backlog row, named in *Known outstanding*. Twenty-seven more joined on
2026-10-31, corpus intake #5 (`admitted_rev` adfef300), graded the same way and passed by the user in the app. Twenty-five more joined on
2026-11-06, corpus intake #6, graded from the intake ledger's notes and backlog rows (no census at
promotion) and passed by the user in the app; three are C for NullPlayer windows in plain chrome or a
composite player the tiler cannot place, with open rows named in *Known outstanding*. Twenty-five more joined on
2026-11-08, corpus intake #7, graded the same way and passed by the user in the app; four are C for a
Media Library in NullPlayer's plain chrome (open B366). Twenty-five more joined on 2026-11-09, corpus
intake #8, graded the same way and passed by the user in the app; seven are C for a Media Library in
NullPlayer's plain chrome (open B366) or no library window of the skin's own. Twenty-five more joined
on 2026-11-10, corpus intake #9, graded the same way and passed by the user in the app; one is C for a
Media Library in NullPlayer's plain chrome (LiquidStar declares no frame of its own). Forty-nine more joined on 2026-11-11, corpus intake #10, graded the same way and passed by the user in the app; three are C for a Media Library in NullPlayer's plain chrome (SleekyXtra, Overdrive, RayPlayer declare no frame of their own). Fifty more joined on 2026-11-11, corpus intake #11, graded the same way and passed by the user in the app; one is C for a Media Library in NullPlayer's plain chrome (Skimple declares no frame of its own), and five carry open rows named in *Known outstanding* (B431, B434, B436, B438, B439), as do the nine cPro skins (B396) and two more (B403). One hundred more joined on 2026-11-16, corpus intake #12, graded the same way and passed by the user in the app; all are B, and YST carries an open row named in *Known outstanding* (B446). One hundred and fifty more joined on 2026-11-17, corpus intake #13, graded the same way and passed by the user in the app; four are C for a Media Library in NullPlayer's plain chrome (Juke_Box_1950, Macosx, remote-2 and arachnid declare no frame of their own), and Azenis_2 and WM_Player share YST's open row (B446). Two hundred more joined on 2026-11-17, corpus intake #14, graded the same way and accepted by the user; three are C (iAmp and Macosx-2 open their Media Library in NullPlayer's plain chrome, declaring no frame of their own; Trance_Critic_v2_0's frame plate covers its windows' content, open B464), and Center_Fresh, EGG and Anime_Shogo carry an open row named in *Known outstanding* (B465). One hundred and twenty-nine more joined on 2026-11-23, corpus intake #15, graded the same way and accepted by the user; two are C (capsule opens its Media Library and Playlist, and Winamp3_Default_Skin its Media Library, in NullPlayer's plain chrome, declaring no frame of their own), and Official_Coldplay_skin carries an open row named in *Known outstanding* (B475). Thirty-four more moved to gold on 2026-11-24 with corpus intake #16: the 33 listed here from the first headless passes, whose grades stand, and Wurlitzer_v2, which joins as C for its skin frame drawn short on NullPlayer's own windows (open B422); the user accepted the batch without a hand-over round. B366's fix moved twelve earlier skins from C
to B (intake #8: Narnia, Thanog, Lara Flynn Boyle, FreddyvsJason, Fast And The Furious 4, Pax;
intakes #6–#7: AniTransformers, Java Duke, NightWing II, Powerade, Star Wars Player, The Sims): their
Media Library and Playlist now open in the skin's own frame, checked by the user in the app.

Current picture: **928 B · 63 C**, of which 7 letters come from a
person using the skin and 984 are provisional (below).

## How the grades were arrived at, and how far to trust them

The rubric is in `.claude/skills/wal-skin-report/SKILL.md`. It grades **the user's experience of the
skin** — does every surface draw, are the controls live, do the animations run, do the menus work.
Two kinds of letter appear in the table and they are not equally good:

- **live** — someone drove the skin and filled in the full report. Seven skins. These are authoritative.
  Six publish **"as of"** their date, because they were measured before 77 changes landed in the
  skin engine, and under the staleness rule a grade goes stale when the engine moves under it.
- **provisional** — derived from a headless pass: the skin is loaded, every container and layout it
  declares is rendered to an image, its scripts are started, and its artwork lookups, unimplemented
  method calls and surface routing are recorded. No one has clicked anything. Skins from corpus
  intake #6 on are the exception: their provisional letter comes from the intake's ledger notes and
  backlog rows, from a live scripted scan (every main-window control clicked, the Library opened) and
  the user passing the skin in the app, not from the full live report a **live** letter needs.

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
| **(M)XP Blue Flavour**<br>`MXP_Blue_Flavour.wal` | Michael Soutar aka (M)Rated | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **(M)XP Green Flavour**<br>`MXP_Green_Flavour.wal` | Michael Soutar aka (M)Rated | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **(M)XP Rainbow Flavour**<br>`MXP_Rainbow_Flavour.wal` | Michael Soutar aka (M)Rated | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **(M)XP Silver Flavour**<br>`MXP_Silver_Flavour.wal` | Michael Soutar aka (M)Rated | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **--Vortex--**<br>`--Vortex--.wal` | Quadhelix + hammerhead + rohan2kool + deimos + SLoB+ Leechbite | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.mainframe.display.center`; 15 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **..::crysis wars::..**<br>`crysis_modern_skin.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `player.normal.display.cover`, `player.shade.Close`, `player.shade.Minimize`, `player.shade.Shade`, `player.shade.SpeakerLeft`, `player.shade.SpeakerRight`, `player.shade.VolumeDec`, `player.shade.VolumeInc` |
| **..::crysis wars::..**<br>`Eva_Longoria.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `player.normal.display.cover`, `player.shade.Close`, `player.shade.Minimize`, `player.shade.Shade`, `player.shade.SpeakerLeft`, `player.shade.SpeakerRight`, `player.shade.VolumeDec`, `player.shade.VolumeInc` |
| **..::modern_warfare_2::..**<br>`modern_warfare_2.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `player.normal.display.cover`, `player.shade.Close`, `player.shade.Minimize`, `player.shade.Shade`, `player.shade.SpeakerLeft`, `player.shade.SpeakerRight`, `player.shade.VolumeDec`, `player.shade.VolumeInc` |
| **1 Giant Leap**<br>`1_Giant_Leap.wal` | Petrol Designs and JT | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **10-10-220**<br>`Toby_Keith_Live_from_10-10-220_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **1010 - Fullscreen**<br>`1010_Fullscreen.wal` | Martin Poehlmann (martin.deimos) | C<br><sub>live, 2026-10-22</sub> | Fully skinned | The song title and the clock overlap in the display strip: the title draws ~12px below the 18px band the skin fades it under (`over.png`, y=15), onto the clock's digits (y=34–60). The clock itself is placed right; what lifts Winamp's title is unknown — aligning skin-shipped TrueType by its cap top fixed it here but moved ~50 other skins wrong, so it was rolled back. In the skin's 800 × 600 Screen Resolution its 380px clock box cannot hold the 11-glyph Sonique clock, and the title does not show; Viewport (the default) shows both |
| **15 June**<br>`15_June.wal` | Nur Akbar Mappaleo (www.metalgrin-blog.tk) for www.15june.com | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `button`, `songcover` |
| **1933 Philco Cathedral**<br>`1933_Philco.wal` | The Kratz | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **1936 Zenith Stratosphere**<br>`1936_Zenith_Stratosphere.wal` | The Kratz | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **28 Days Later**<br>`Official_28_Days_Later_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `win.center` |
| **3D**<br>`Darjah 1.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `play/on.png` |
| **:... Xplod ...:**<br>`Xplod-Speaker-Sony.wal` | .. wish_4innocent@hotmail.com .. walikaker@hotmail.com .. | B<br><sub>provisional</sub> | Fully skinned | the song ticker clips its last glyph by a pixel; 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **_Hand ComputerV2**<br>`HandComputerV2_1.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.winshadeAnim` |
| **_SD777_**<br>`SD777z.wal` | daniel sioneanu | B<br><sub>provisional</sub> | Partly skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `player.button.repeat.bg`, `player.button.shuffle.bg`, `player.button.status.play`, `player.display.bg.center`, `player.display.bg.left`, `player.display.bg.right`, `player.display.center`, `player.display.left` |
| **_SD_**<br>`sd1.wal` | daniel sioneanu | B<br><sub>provisional</sub> | Partly skinned | 24 bitmap id(s) it references do not resolve, leaving a visible gap: `player.button.repeat.bg`, `player.button.shuffle.bg`, `player.button.status.play`, `player.display.bg.center`, `player.display.bg.left`, `player.display.bg.right`, `player.display.center`, `player.display.left` and 16 more |
| **A Man Apart**<br>`Official_A_Man_Apart_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **A NEW SKIN**<br>`ModernClassic_1_1.wal` | Mike Ludwig | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **A NEW SKIN**<br>`ORBAMP.wal` | Mike Ludwig | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `wasabi.frame.basetexture` |
| **Abducted**<br>`Abducted.wal` | SLoB | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `stick.main.plct_joinbarallenbolt` |
| **ABPlayer**<br>`ABPlayer.wal` | Mike Ludwig | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `eq.button`, `player.button.exit`, `wasabi.frame.basetexture` |
| **absurd**<br>`absurd_5.wal` | Till Haldimann | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Act 3 Scene 1**<br>`Act_3_Scene_1_.wal` | Skinarmory | B<br><sub>provisional</sub> | Partly skinned | nothing outstanding that a headless pass can see |
| **Act 3 Scene 2**<br>`Act3scene2_-_prototype.wal` | Skinarmory | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Aircel Skin**<br>`AIRCELDialer_Tunes.wal` | Pradeep.K.R | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Aircel Skin**<br>`Fc_Vaslui.wal` | Pradeep.K.R | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Airtel**<br>`agulial_del_america_skin.wal` | Saravanan K Sivanathan, Hithendra Rangaswamy | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Airtel**<br>`Airtel__Hello_Tunes.wal` | Saravanan K Sivanathan, Hithendra Rangaswamy | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Airtel SongCatcher**<br>`Airtel__Song_Catcher.wal` | Pradeep K R, Santhosh R | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Airtel SongCatcher**<br>`SCCT__DigitalWinamp2011.wal` | Pradeep K R, Santhosh R | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `normal.songcatcher.logo` |
| **AkbankBuyukEv**<br>`Big_Red_House_.wal` | Ersin Arar | B<br><sub>provisional</sub> | Fully skinned | its shade button names an undeclared layout `pinkmini` (the skin's) |
| **Alfa Romeo History**<br>`Alfa_Romeo_History.wal` | Toni Davila | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **Alien Skin**<br>`Syncrosect_01.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **AlienPADD**<br>`PaddPreview.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `player.normal.button.menu.btn`, `player.shade.shade`; 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **All Seeing Eye**<br>`ROBODRONRobert_V_Padron_1.wal` | Robodron | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Allsurf.fr**<br>`Allsurf_-_Official_Skin.wal` | Seb | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Almin Agic Skin**<br>`Almin_Agic_Skin.wal` | Almin Agic | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Alpha Media Player X5**<br>`Alpha_Media_Player_X5.wal` | Dmitry Pozdniakov | B<br><sub>provisional</sub> | Player skinned | 3 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Alpine amp V2.0**<br>`Alpine9243R.wal` | Ben_SisTeck | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `ALPINE` |
| **Alpine amp V2.0**<br>`S-teck.wal` | Ben_SisTeck | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Alyson Hannigan Hottie AMP**<br>`Alyson_Hannigan_Hottie_AMP.wal` | James Nikolai | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Amber**<br>`amber.wal` | lypnjtu | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `blue-player.button.eq.hidden`, `displayscreen`, `player.VolumeKnob.blank`, `player.button.Openhidden`, `player.button.opacity.hidden` |
| **American Rag / Lollapalooza**<br>`American_Rag.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Amp3LCD**<br>`Amp3LCD.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **AmpTunes III (WinTunes)**<br>`AmpTunes_III.wal` | Jay Spannerz | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Anaheim Player 01**<br>`Anaheim_Player_01.wal` | Anaheim Electronics Japan | B<br><sub>provisional</sub> | Fully skinned | 2 error-severity load finding(s) |
| **analogaudio**<br>`lexicon2.wal` | me | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **Ancient Powers**<br>`Ancient_Powers_by_Robodron_1.wal` | Robodron | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **ANDROMEDA WINAMP5 SKIN**<br>`Andromeda_Winamp5_Skin.wal` | LEGION | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Anexa**<br>`Anexa.wal` | nynako / skin-zone | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Angel**<br>`Official_Angel_Series_Winamp5_Skin.wal` | Petrol Designs, Kinwashi and Lucas | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Angel Beats!**<br>`Angel_Beats!.wal` | RainSteve | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Angelic Blessings**<br>`Angelic_Blessings_by_ROBODRON.wal` | Robodron | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Angelic Light**<br>`Angelic_Light_by_ROBODRON.wal` | Robodron | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Anging Mammiri Winamp Skin**<br>`Gisel_Idol_.wal` | Caesarleo (http://metalgrin.fluxide.com) makassar terkini social network | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `button`, `songcover` |
| **Angren Thoron**<br>`Angrenthoron.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Anime Shogo**<br>`Anime_Shogo.wal` | Excelsior and UUL | B<br><sub>provisional</sub> | Fully skinned | some hosted windows intermittently open without the skin's frame (B465) |
| **AniTransformers Skin**<br>`AniTransformers.wal` | Jeremy Eble | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **AntiqueRadio**<br>`AntiqueRadio.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `wasabi.frame.basetexture` |
| **Anunaki**<br>`Anunaki.wal` | Leechbite | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`; 29 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **AOL Broadband Winamp5 Skin**<br>`AOL_Broadband_Winamp5_Skin_.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Apill**<br>`Apill.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **AQUA V1**<br>`Aqua_x1.wal` | SAIF,BANGLADESH | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **AR-7**<br>`AR-7.wal` | Metaskins | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **AR-7**<br>`ar7.wal` | Metaskins | B<br><sub>provisional</sub> | Fully skinned | 9 bitmap id(s) it references do not resolve, leaving a visible gap: `component.titlebar-lcd`, `ct.left`, `ct.right`, `metaskins.logo`, `middle.buttons.screen.layer`, `middle.buttons.screen.layer.under`, `middle.buttons.screen.layer.under2`, `region.bottom.left` and 1 more |
| **arachnid**<br>`arachnid.wal` | — | **C**<br><sub>provisional</sub> | Partly skinned | the Media Library opens in NullPlayer's plain chrome: the skin declares no frame of its own |
| **Aria of the Soul**<br>`Aria_of_the_Soul.wal` | Saek | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **ArmorAMP**<br>`ArmorAmp.wal` | Graphics: faris / Code: krcko, martin | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **ARTZAR**<br>`Artzar.wal` | Mike McCaffrey | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **AS Fx21 EVO**<br>`ASfx21Evo.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **AS Fx21 Skin**<br>`AS-FxS.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **Ashen Player**<br>`Ashen_Player_for_Winamp_1_1.wal` | iron2000 | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **asnw player**<br>`asnw.wal` | Jean-Nan | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **Assmosis**<br>`Assmosis.wal` | Steve Gedikian and Mathieu Pellerin. WA5 version by Mr Jones. Open Source Notifier by iPlayTheSpoons. | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **ATL**<br>`The_ATL_Winamp5_Skin.wal` | PetrolDesigns | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Atomic**<br>`Atomic_v1-1.wal` | Bahmet | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Auburn University**<br>`Auburn_.wal` | Daniel Kolenich | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **AudioRack**<br>`AudioRack.wal` | Thomas Michgelsen | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Auriga V5**<br>`Auriga_V5.wal` | Kinwashi | B<br><sub>provisional</sub> | Fully skinned | open B403 (a video/browser toggle does nothing, no video surface declared) |
| **Austin Powers(tm) in Goldmember**<br>`Official_Austin_Powers_3_Skin.wal` | Kinwashi, Reed and Lucas for Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | open B436 (the drawer opens on a black panel (the skin's own video is not played)) |
| **Avalon**<br>`Avalon_Winamp_Modern.wal` | Jorge Mancheno | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Axess**<br>`Akbank.wal` | Ersin Arar | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **AxessTeknoPuan**<br>`Akbank_TP_.wal` | Ersin Arar | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Aya Kiguchi**<br>`Aya_Kiguchi.wal` | DJ Spike | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Ayanami Rei the Fifth**<br>`MD_-_Ayanami_Rei_the_Fifth_v1.wal` | Indra Furatama a.k.a. Asakura Rantisi kay | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `thinger.bucket`, `thinger.bucket.mask`, `thinger.ticker`, `wasabi.frame.basetexture` |
| **Ayumi Hamasaki**<br>`Ayum_Hamasaki.wal` | Hikari Hendri | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `back`, `component.basetexture` |
| **Azenis mimi**<br>`Azenis_mimi.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `eq/EQSet.png`, `player.songinfo.stereo`, `player.songinfo.stereomono`, `set` |
| **Azenis_2**<br>`Azenis_2.wal` | — | B<br><sub>provisional</sub> | Fully skinned | open B446 (each content window has a paired frame window; not yet seen on screen); 5 bitmap id(s) it references do not resolve, leaving a visible gap: `eq/EQSet.png`, `player.songinfo.stereo`, `player.songinfo.stereomono`, `player\Volbar.png`, `set` |
| **AZUMANGA WINAMP5 SKIN**<br>`Azumanga_Winamp5_Skin.wal` | LEGION | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **B*L*E*A*C*H**<br>`Modern_Bleach.wal` | Lee Trudgeon | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Bad Syntax by Norbika**<br>`BadSyntax.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `frame.cut.bot.left`, `frame.cut.bot.right`, `frame.cut.top.left`, `frame.cut.top.right` |
| **Baroque**<br>`Baroque_1.0.wal` | Corwin of Amber | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Barracuda**<br>`Barracuda.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `drawer.eq.crossfade.display`, `wasabi.frame.basetexture` |
| **Batmain Movie**<br>`Batman_Begins.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Batman**<br>`Official_Batman_Winamp5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Batman Arkham Inspiration**<br>`Batman_Arkham_Inspiration.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `1x`, `2x`, `fs`, `options`, `player.songinfo.stereo`, `player.songinfo.stereomono`, `random`, `randomback` |
| **Batman on the move**<br>`batman_on_the_move.wal` | ivan gomez | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **BattleAMP**<br>`Battlefield_Vietnam.wal` | D4rkchill3r | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Beat-Sugar**<br>`BeatSugar.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `wasabi.frame.basetexture` |
| **Beer Fest**<br>`The_Beerfest_Winamp_skin.wal` | Warner Bros. Studios | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Ben Tjibe - SM**<br>`Ben_Tjibe__SM.wal` | Ben Tjibe | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Big Bento Modern**<br>`Big Bento Modern.wal` | Victhor, Martin Pöhlmann, Ben Allison | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `frame.center`, `infocomp.button.icon.bg`, `infocomp.button.icon.lyricfinder`, `infocomp.button.icon.searchvideo`, `player.button.repeat.normal`; 1 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `config.button.hover`; 27 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Big Bento Modern - Windows 10 edition**<br>`Big Bento Modern Windows 10 edition.wal` | Victhor, Martin Pöhlmann, Ben Allison | B<br><sub>provisional</sub> | Fully skinned | 6 bitmap id(s) it references do not resolve, leaving a visible gap: `frame.center`, `infocomp.button.icon.bg`, `infocomp.button.icon.lyricfinder`, `infocomp.button.icon.searchvideo`, `player.button.repeat.normal`, `wtf`; 1 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `config.button.hover`; 27 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Big Bento Modern - Windows 10 edition Light**<br>`Big Bento Modern Windows 10 edition Light.wal` | Victhor, Martin Pöhlmann, Ben Allison | B<br><sub>provisional</sub> | Fully skinned | 6 bitmap id(s) it references do not resolve, leaving a visible gap: `frame.center`, `infocomp.button.icon.bg`, `infocomp.button.icon.lyricfinder`, `infocomp.button.icon.searchvideo`, `player.button.repeat.normal`, `wtf`; 1 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `config.button.hover`; 27 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Big Bento Modern Light**<br>`Big Bento Modern Light.wal` | Victhor, Martin Pöhlmann, Ben Allison | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `frame.center`, `infocomp.button.icon.bg`, `infocomp.button.icon.lyricfinder`, `infocomp.button.icon.searchvideo`, `player.button.repeat.normal`; 1 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `config.button.hover`; 27 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **BIG PROOF skin**<br>`BIG_PROOF_2.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **BigBerthaSanctuary**<br>`BigBerthaSanctuary_1_1_1.wal` | Rukasuzu | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Bingo Red Chilli Bijli Skin**<br>`Bingo!_Red_Chilli_Bijli.wal` | Pradeep.K.R,Balasundarrao | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `close.normal` |
| **Biohazard**<br>`Biohazard_V2.wal` | Bahmet | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **BLACK SONG**<br>`Black_Song.wal` | Ramin Mousavi | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **BLACK SONG**<br>`English_Premier_League.wal` | Ramin Mousavi | B<br><sub>provisional</sub> | Fully skinned | 12 bitmap id(s) it references do not resolve, leaving a visible gap: `main.display.vis.mask`, `shade.background`, `shade.eject`, `shade.next`, `shade.pause`, `shade.play`, `shade.prev`, `shade.seek.empty` and 4 more |
| **blackwhite**<br>`blackwhite_version1.wal` | Fabiolo Jose Gatbonton | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **BLAKK**<br>`BLAKK.wal` | Dwight Robinson aka Vica. | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.remote-toggles-ml-text-off`; 5 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Bleuthing**<br>`Bleu_Thing_V3.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Blink 182 - Feel This**<br>`blink182_feeling_this.wal` | Anthony Rocchio | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **BlockedWIRE 1.0**<br>`BlockedWIRE.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **blue tech**<br>`redsmoke2.wal` | Madpeter | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Boarding House**<br>`Boarding_House_Winamp3_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Bon Jovi**<br>`Bon_Jovi_-_Bounce_-__Winamp_3_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Boneless Knight**<br>`Boneless_Knight.wal` | DJ Spike | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **BOOM**<br>`BOOM.wal` | Adil Ait el hassan(gfx) and Will Fisher(coding) | B<br><sub>provisional</sub> | Fully skinned | 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **boxOr!**<br>`boxOr.wal` | Morgan aka. 'Splif' THOMAS. WA5 version by Mr Jones. Open Source Notifier by iPlayTheSpoons. | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Braun CC 4**<br>`Braun_CC_42.wal` | Thomas Fensky, mit freundlicher Unterstuetzung durch FrisbeeMonkey, Volker J. und Sven Kistner | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Braun CC 50**<br>`Braun_CC_50.wal` | Thomas Fensky | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `mass.main`, `window.normal.middle.abuse` |
| **Brown Sherina**<br>`Brown_Sherina.wal` | Firmansyah | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Bubble Tea**<br>`Bubble_Tea_-_Updated.wal` | — | C<br><sub>provisional</sub> | Partly skinned | no window of its own for the library: a NullPlayer window stands in |
| **buffy the vampire slayer**<br>`buffy_the_vampire_slayer.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `component.region.bottom`, `component.region.bottom.left`, `component.region.bottom.right`, `wasabi.frame.basetexture` |
| **Buffy_the_vampire_slayer__the_codex**<br>`Buffy_the_vampire_slayer__the_codex.wal` | — | B<br><sub>provisional</sub> | Fully skinned | open B403 (a video/browser toggle does nothing, no video surface declared) |
| **BumbleBee**<br>`BumbleBee.wal` | Rukasuzu | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **BUSTER**<br>`BusterVer2.wal` | Rain Pikner and Nikita Mokhirev | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `border`, `component.basetexture`, `player.comp-right-bottom` |
| **BWA**<br>`BWA.wal` | -=Vovan=- | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Calm Mind**<br>`Calm_Mind_by_ROBODRON.wal` | Robodron | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **candybar**<br>`candybar.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `component.region.bottom.left`, `component.region.bottom.right`, `component.region.top.left`, `component.region.top.right`, `eq.normal.auto_normal`, `eq.normal.on_normal`, `player.normal.display_lights`, `wasabi.frame.basetexture` |
| **Canister 01**<br>`Canister_01.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Cannes**<br>`Cannes.wal` | Graphics by monaux (Karl Kwasny), Design by Kinwashi, scripting by nIRV (Mathieu Pellerin) | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Canum**<br>`canum_winamp_by_burnsplayguitar_d2xhizu.wal` | burnsplayguitar | C<br><sub>provisional</sub> | Partly skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `displayscreen`; no library, playlist window of its own; 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140) |
| **capsule**<br>`Capsule_II.wal` | boostr29 | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **capsule**<br>`capsuleII.wal` | boostr29 | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **capsule**<br>`capsule.wal` | boostr29 | C<br><sub>provisional</sub> | Partly skinned | the Media Library and Playlist open in NullPlayer's plain chrome (the skin declares no frame of its own) |
| **Cardium II**<br>`CardiumII.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `component.region.bottom`, `component.region.top`, `wasabi.frame.basetexture` |
| **Carma Clearing**<br>`Carma_Clearing_by_ROBODRON.wal` | Robodron | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Casio G Shocked**<br>`Casio-G-Shocked-V2.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Catwoman**<br>`Catwoman_Winamp5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **CCPC**<br>`ccpc.wal` | Twan Verstegen | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **CCZ**<br>`CCZ-45.wal` | Creditcardzone | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Celica Amp**<br>`Celica_Amp.wal` | James Nikolai | C<br><sub>provisional</sub> | Partly skinned | no window of its own for the library: a NullPlayer window stands in |
| **CELL**<br>`Cell.wal` | graphic and coding by faris18787 MAKI script by http://frisbeemonkey.com, Notifier using opensource_notifier | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `component.bg`, `wasabi.frame.basetexture` |
| **Center Fresh Winamp Skin**<br>`Center_Fresh.wal` | Kamal Kannan, Balasundarrao | B<br><sub>provisional</sub> | Fully skinned | some hosted windows intermittently open without the skin's frame (B465) |
| **Channel 1**<br>`Official_Channel_One_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **Charmed**<br>`Official_Charmed_TV_Series_WA_5_skin.wal` | Petrol Designs, Andy and Lucas | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Chasing Liberty**<br>`Chasing_Liberty_Winamp5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Chevy - Gold**<br>`Chevy_Number_29_Car.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `win.center` |
| **Chevy - Red**<br>`Chevy_Number_8_Car.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `win.center` |
| **Chicken Little**<br>`Chicken_Little.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Chronabie**<br>`Chronabie.wal` | Vica | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **CindY v 1.0**<br>`cindy1.wal` | Malik Trey | B<br><sub>provisional</sub> | Fully skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `background.display.left.outline`, `background.display.middle`, `background.display.right.outline`, `button.control`, `button.control.outline`, `button.list.outline`, `options.button`, `options.button.outline` |
| **CircloTroniC**<br>`Circlo_T_roniC.wal` | — | C<br><sub>provisional</sub> | Partly skinned | no window of its own for the library or the playlist: a NullPlayer window stands in |
| **Classic Grafiti**<br>`Classic_Grafiti.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Classic Sara Aspen**<br>`Classic_Sara_Aspen.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Classic_KilJaeden_The_Deciever**<br>`Classic_KilJaeden_The_Deciever.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Classix 10k**<br>`Classix_10k_Modern.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Classix Player**<br>`Classix_Player_1_1.wal` | iron2000 | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **CleanAMP**<br>`Clean_AMP.wal` | ROBO Design | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **CLIENT V2 Winamp5 audio player skin.**<br>`Client_V2.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **CLIENT V3 Winamp5 audio player skin.**<br>`Client_V3.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **CLIENT Winamp5 audio player skin.**<br>`CLIENT.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **ClipUp**<br>`ClipUp_101.wal` | Andrew Mackowski | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Clock**<br>`Clock V2.76.wal` | Corwin of Amber | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **Club Dread**<br>`Club_Dread.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **CNY**<br>`CNYforWinamp.wal` | lypnjtu | B<br><sub>provisional</sub> | Fully skinned | 23 bitmap id(s) it references do not resolve, leaving a visible gap: `Component.Back.Bottom`, `Component.Back.BottomLeft`, `Component.Back.BottomRight`, `Component.Back.Left`, `Component.Back.Middle`, `Component.Back.Right`, `Component.Back.Top`, `Component.Back.TopLeft` and 15 more |
| **Coca Cola**<br>`Coca_Cola__My_Coke_Music.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Coca-Cola Musica**<br>`CocaCola_Musica_Winamp5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **COD-BLACK-OPS**<br>`CALL_OF_DUTY_BLACK_OPS_'NAZ_PLAYER.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Coldplay - A Rush of Blood to the Head**<br>`Official_Coldplay_skin.wal` | Taber Buhl | B<br><sub>provisional</sub> | Fully skinned | the Thinger window's icons sit low and the status bar cuts them off (B475) |
| **Compact**<br>`Compact.wal` | PercassoWG | B<br><sub>provisional</sub> | Fully skinned | the skin declares no Media Library frame, so it opens in NullPlayer's own chrome |
| **Compact-SE**<br>`CompactSE.wal` | Ben_SisTeck | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Copperdeck II**<br>`CopperdeckII.wal` | Frank Duivenvoorden | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.scrollbar.vertical.button`, `window.topright.region`, `window.header`, `about.winampbolt`; 3 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Copter**<br>`Copter.wal` | UUL | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player` |
| **Core X5**<br>`Core-X5.wal` | Skin Consortium | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **CornerAmp Redux**<br>`corneramp_redux.wal` | 9 of Nine, Evil Pumpkin, RazorZero | B<br><sub>provisional</sub> | Fully skinned | 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Corpse Bride**<br>`Corpse_Bride.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | no EQ on/off control (B377, closed as the skin's) |
| **Cosmic Ray**<br>`Golden_Healer_by_ROBODRON.wal` | Robodron | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Cosmic Ray**<br>`Lazer_Magick_by_ROBODRON.wal` | Robodron | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **cPro - ACDC - Black Ice**<br>`cPro__ACDC__Black_Ice.wal` | — | B<br><sub>provisional</sub> | Player skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `studio.BaseTexture` |
| **cPro - Anunaki**<br>`cPro_Anunaki.wal` | — | B<br><sub>provisional</sub> | Player skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top`, `player.o.topleft` |
| **cPro - Aperture**<br>`cPro_Aperture.wal` | — | B<br><sub>provisional</sub> | Player skinned | 15 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` and 7 more |
| **cPro - Bento**<br>`2222-cPro__Bento.wal` | — | C<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `custom.repeat.0`, `custom.shuffle.0`; unimplemented MAKI: `enumitem` ×4; 13 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro - Bento**<br>`cpro_interface_by_jinghis_d301whe.wal` | — | C<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `custom.repeat.0`, `custom.shuffle.0`, `custom.winamp`, `size.khzkbps`; unimplemented MAKI: `enumitem` ×4; 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro - Bento**<br>`Blue_Tech.wal` | — | B<br><sub>provisional</sub> | Player skinned | 15 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` and 7 more |
| **cPro - Bento**<br>`cPro_Cup_Of_Tea_by_Veroka.wal` | — | B<br><sub>provisional</sub> | Player skinned | 15 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` and 7 more |
| **cPro - Braun atelier**<br>`cPro__Braun_atelier_1.02.wal` | — | B<br><sub>provisional</sub> | Player skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `shade.o.bg.1`, `shade.o.bg.2`, `shade.o.bg.3`, `studio.BaseTexture` |
| **cPro - Canus**<br>`CANUS__by_d4f_Mac.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **cPro - CirQ**<br>`cPro__cirQ.wal` | Fernando Cabanzo Garcia | B<br><sub>provisional</sub> | Fully skinned | open B396 (the window census hangs at the Windows-menu toggle) |
| **cPro - Classix**<br>`cPro__Classix.wal` | — | B<br><sub>provisional</sub> | Player skinned | 14 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` and 6 more |
| **cPro - cMP10**<br>`cPro__cMP10.wal` | iron2000 | B<br><sub>provisional</sub> | Fully skinned | open B396 (the window census hangs at the Windows-menu toggle) |
| **cPro - cMP11**<br>`cPro__cMP11.wal` | SkinConsortium, iron2000 | B<br><sub>provisional</sub> | Fully skinned | open B396 (the window census hangs at the Windows-menu toggle) |
| **cPro - cMP11B**<br>`cPro__cMP11B.wal` | — | B<br><sub>provisional</sub> | Player skinned | 16 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `cpro.status.playing`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right` and 8 more |
| **cPro - cMP12**<br>`cPro__cMP12_1.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **cPro - Contemporary Vision**<br>`cPro__Contemporary_Vision_1_1_1.wal` | — | B<br><sub>provisional</sub> | Player skinned | 15 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` and 7 more |
| **cPro - Creed - Full Circle**<br>`cPro__Creed__Full_Circle.wal` | — | B<br><sub>provisional</sub> | Player skinned | 14 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` and 6 more |
| **cPro - Das Skin**<br>`cpro-das-skin-prev.wal` | — | **B**<br><sub>live, as of 2026-08-31</sub> | Fully skinned | unimplemented MAKI: `enumitem` ×4; 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro - Erbium**<br>`cPro_Erbium.wal` | — | B<br><sub>provisional</sub> | Player skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `size.khzkbps`, `studio.BaseTexture` |
| **cPro - FlaT**<br>`cPro__FlaT.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **cPro - FlaT**<br>`cPro__iRda.wal` | — | B<br><sub>provisional</sub> | Player skinned | 12 bitmap id(s) it references do not resolve, leaving a visible gap: `beat.0.right`, `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right` and 4 more |
| **cPro - FR-19**<br>`cPro_FR19.wal` | Anemovatis | B<br><sub>provisional</sub> | Player skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `beat.0.right`, `player.led.off`, `studio.BaseTexture` |
| **cPro - Fryamp**<br>`cPro__FryAmp.wal` | — | B<br><sub>provisional</sub> | Player skinned | 15 bitmap id(s) it references do not resolve, leaving a visible gap: `beat.0.right`, `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right` and 7 more |
| **cPro - FutureUncertain**<br>`cPro_FutureUncertain.wal` | — | B<br><sub>provisional</sub> | Player skinned | 15 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` and 7 more |
| **cPro - Gothic_metal**<br>`C_Pro_gothic_metal.wal` | — | B<br><sub>provisional</sub> | Player skinned | 14 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` and 6 more |
| **cPro - Gothic_metal-v2.0**<br>`Gothic_Metal_v2_1.wal` | — | B<br><sub>provisional</sub> | Player skinned | 14 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` and 6 more |
| **cPro - HI-FI 73**<br>`cPro__HiFi_73.wal` | — | B<br><sub>provisional</sub> | Player skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `studio.BaseTexture` |
| **cPro - insekticid**<br>`cPro__insekticid.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **cPro - Insomnic**<br>`cPro_Insomnis_v2_by_zrco.wal` | — | **B**<br><sub>live, as of 2026-08-31</sub> | Fully skinned | unimplemented MAKI: `enumitem` ×4; 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro - iPhone3g**<br>`CPro_iPhone3gv2.wal` | — | B<br><sub>provisional</sub> | Player skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `studio.BaseTexture` |
| **cPro - KAO**<br>`cPro__KAO.wal` | — | B<br><sub>provisional</sub> | Player skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `studio.BaseTexture` |
| **cPro - ME**<br>`Marko_Egger.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **cPro - Mecha**<br>`cPro__Mecha_1_1_1_1.wal` | iron2000 | B<br><sub>provisional</sub> | Player skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top`; open: B300 (long tab labels are cut) |
| **cPro - Metallica - Death Magnetic**<br>`cPro_Metallica__Death_Magnetic.wal` | — | B<br><sub>provisional</sub> | Player skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `studio.BaseTexture` |
| **cPro - minimal**<br>`cPro__minimal_1_1_1_1.wal` | iron2000 | B<br><sub>provisional</sub> | Player skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `studio.BaseTexture`, `volume.bg2` |
| **cPro - MMD**<br>`221721-cPro_MMD.wal` | — | C<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `beat.0.right`, `player.led.off`; unimplemented MAKI: `enumitem` ×4; 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro - MPxi remix**<br>`cPro__MPxi_remix.wal` | — | B<br><sub>provisional</sub> | Player skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` |
| **cPro - Opera.v.J**<br>`cPro_Opera.v.J.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **cPro - POP!?**<br>`cPro__POP_1.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **cPro - Satin Carbon v1.1**<br>`cPro__Satin_Carbon_Port_1.wal` | Skinister - Victhor | B<br><sub>provisional</sub> | Player skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `studio.BaseTexture`, `vol.bg` |
| **cPro - Satin v1.1**<br>`cPro__Satin_Port_1.wal` | Skinister - Victhor | B<br><sub>provisional</sub> | Player skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `studio.BaseTexture`, `vol.bg` |
| **cPro - Steam**<br>`Additional_CPro_Steam.wal` | iron2000 | B<br><sub>provisional</sub> | Player skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `shade.o.bg.1`, `shade.o.bg.2`, `shade.o.bg.3`, `studio.BaseTexture` |
| **cPro - Steam**<br>`cPro__Steam_1_1_1_1.wal` | iron2000 | B<br><sub>provisional</sub> | Player skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `shade.o.bg.1`, `shade.o.bg.2`, `shade.o.bg.3`, `studio.BaseTexture` |
| **cPro - Super Black**<br>`SUPER_BLACK.wal` | — | B<br><sub>provisional</sub> | Player skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `custom.repeat.0`, `custom.shuffle.0`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left` |
| **cPro - U2 \| NO LOTH**<br>`U2_No_Line_on_Horizon.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **cPro - Venus ALPHA Port**<br>`cPro_Venus_Alpha_port_by_Victhor_v1.3.1.wal` | RPeterClark - Victhor | C<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `info.vol.bg`, `vol.bg`, `volume.bg2`; unimplemented MAKI: `enumitem` ×4; 10 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro - Venus Port v1.3**<br>`cPro_Venus_Port_1.wal` | RPeterClark - Victhor | B<br><sub>provisional</sub> | Player skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `info.vol.bg`, `studio.BaseTexture`, `vol.bg`, `volume.bg2` |
| **cPro - Winamp Azenis**<br>`cPro__Winamp_Azenis.wal` | — | B<br><sub>provisional</sub> | Player skinned | 14 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` and 6 more |
| **cPro - Winamp Classic**<br>`cPro__Winamp_Classic.wal` | — | B<br><sub>provisional</sub> | Player skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` |
| **cPro - Winamp3000**<br>`CPro_Winamp3000.wal` | — | B<br><sub>provisional</sub> | Player skinned | 15 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` and 7 more |
| **cPro - WMP12**<br>`221955-cPro__Winamp_Media_Player_12.wal` | — | C<br><sub>provisional</sub> | Fully skinned | unimplemented MAKI: `enumitem` ×4; 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro - XPS**<br>`cPro_T2T-by-MAC.wal` | — | **C**<br><sub>live, as of 2026-08-31</sub> | Fully skinned | 15 bitmap id(s) it references do not resolve, leaving a visible gap: `custom.repeat.0`, `custom.shuffle.0`, `custom.winamp`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`…; unimplemented MAKI: `enumitem` ×4; 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro - XPS**<br>`XSP.wal` | — | B<br><sub>provisional</sub> | Player skinned | 17 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `custom.repeat.0`, `custom.shuffle.0`, `custom.winamp`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center` and 9 more |
| **cPro Blue Green Whale Amp**<br>`cPro__Blue_Green_Whale_Amp.wal` | SkinConsortium, Watt | B<br><sub>provisional</sub> | Fully skinned | open B396 (the window census hangs at the Windows-menu toggle) |
| **cPro Pure Winamp**<br>`cPro_Pure.wal` | — | B<br><sub>provisional</sub> | Player skinned | 15 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` and 7 more |
| **cPro Relax**<br>`cPro_Relax.wal` | — | B<br><sub>provisional</sub> | Player skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `size.khzkbps`, `studio.BaseTexture` |
| **cPro Stress**<br>`cPro_Stress.wal` | — | B<br><sub>provisional</sub> | Player skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `size.khzkbps`, `studio.BaseTexture` |
| **Cpro Tokio**<br>`Cpro_Tokio.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **cPro Zen**<br>`cPro_Zen.wal` | — | B<br><sub>provisional</sub> | Player skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `studio.BaseTexture` |
| **cPro2 - Aluminum**<br>`cPro2_Aluminum_1_1.wal` | Victor Brocaz | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `s.button.mute.over.0`, `studio.BaseTexture` |
| **cPro2 - Dark Aluminum**<br>`cpro2_dark_aluminum_final_by_victhor_d6necra.wal` | Victor Brocaz | C<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `cpro2.eq.auto.overlay.0`, `cpro2.eq.on.overlay.0`, `cpro2.xfade.overlay.0`; 1 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `s.button.mute.over.0`; unimplemented MAKI: `enumitem` ×2; 8 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 3 error-severity load finding(s) |
| **cPro2 - HOLOlike**<br>`cPro2__HOLOlike.wal` | iron2000 | B<br><sub>provisional</sub> | Fully skinned | the window census hangs at its Playlist toggle (harness, open B396) |
| **cPro2 - minimal**<br>`cPro2__minimal_1_1.wal` | iron2000 | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `studio.BaseTexture`, `seeker.bg.center.2`, `seeker.bg.left.2`, `seeker.bg.right.2`; 9 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **cPro2 - Styler**<br>`cPro2_Styler_by_Victhor.wal` | Victor Brocaz | C<br><sub>provisional</sub> | Fully skinned | 6 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `playback.button.mute.over.0`, `playback.button.rep.over.0`, `playback.button.shuf.over.0`, `s.button.mute.over.0`; unimplemented MAKI: `enumitem` ×2; 9 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 3 error-severity load finding(s) |
| **cPro2 - Styler // Radiance version**<br>`cPro2_Styler_Radiance_by_Victhor.wal` | Victor Brocaz | C<br><sub>provisional</sub> | Fully skinned | 6 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `playback.button.mute.over.0`, `playback.button.rep.over.0`, `playback.button.shuf.over.0`, `s.button.mute.over.0`; unimplemented MAKI: `enumitem` ×2; 9 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 3 error-severity load finding(s) |
| **cPro2 - Styler // Touchscreen version**<br>`cPro2_Styler_Touchscreen_by_Victhor.wal` | Victor Brocaz | C<br><sub>provisional</sub> | Fully skinned | 6 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `playback.button.mute.over.0`, `playback.button.rep.over.0`, `playback.button.shuf.over.0`, `s.button.mute.over.0`; unimplemented MAKI: `enumitem` ×2; 9 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 3 error-severity load finding(s) |
| **cPro2 - Winamp for Mac Sync**<br>`CPro_Winamp_for_Mac_Sync.wal` | Pieter Nieuwoudt | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `studio.BaseTexture`, `repeat.light.1.0`, `shuffle.light.1.0`; 9 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **cPro: Ashen Tundra**<br>`cPro__Ashen_Tundra.wal` | — | B<br><sub>provisional</sub> | Player skinned | 16 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `cpro.status.playing`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right` and 8 more |
| **cPro: NV7382**<br>`cPro__NV_7382.wal` | — | B<br><sub>provisional</sub> | Player skinned | 16 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `cpro.status.playing`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right` and 8 more |
| **cPro: Royale XP**<br>`cPro__Royale_XP.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **cPro: Wii**<br>`Wii.wal` | — | B<br><sub>provisional</sub> | Fully skinned | the window census hangs at its Library Browser toggle (harness, open B396) |
| **cPro: Windows XP**<br>`cPro__Windows_XP.wal` | iron2000 | B<br><sub>provisional</sub> | Fully skinned | open B396 (the window census hangs at the Windows-menu toggle) |
| **cPro_Ayon Port**<br>`Cpro__Ayon_Port_1.wal` | Victor Brocaz / Victor Barac | C<br><sub>provisional</sub> | Player skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `studio.BaseTexture`; unimplemented MAKI: `enumitem` ×2; 1 error-severity load finding(s) |
| **cPro_Azior**<br>`cPro_Azior.wal` | — | B<br><sub>provisional</sub> | Player skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `beat.0.right`, `beatvis.overlay`, `size.khzkbps`, `studio.BaseTexture` |
| **cPro_Celluloid**<br>`cPro_Celluloid.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **cPro_Celluloid**<br>`CPro_Plasticine.wal` | — | B<br><sub>provisional</sub> | Player skinned | 14 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` and 6 more |
| **cPro_Chinese_Democracy**<br>`cPro_Chinese_Democracy.wal` | — | B<br><sub>provisional</sub> | Player skinned | 15 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` and 7 more |
| **cPro_Colors**<br>`cPro_Colors.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **cPro_Cyanian2010**<br>`Cyanian_2010.wal` | — | B<br><sub>provisional</sub> | Player skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` |
| **cPro_Ebonite**<br>`cPro_Ebonite.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **cPro_Expensive_HiFi**<br>`cPro_Expensive_Hi_Fi.wal` | Veronica Mogni aka Veroka | B<br><sub>provisional</sub> | Fully skinned | open B396 (the window census hangs at the Windows-menu toggle) |
| **cPro_Fluke**<br>`cPro_Fluke.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **cPro_Fluke**<br>`CPro_Fluke_Dark.wal` | — | B<br><sub>provisional</sub> | Player skinned | 15 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` and 7 more |
| **cPro_Fluke**<br>`CPro_Fluke_2.wal` | — | B<br><sub>provisional</sub> | Player skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` |
| **cPro_GUNS N' ROSES**<br>`cPro_GUNS_N'_ROSES.wal` | — | B<br><sub>provisional</sub> | Player skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `studio.BaseTexture` |
| **cPro_Insomnic**<br>`cPro_Insomnis_by_zrco.wal` | — | **B**<br><sub>live, as of 2026-08-31</sub> | Fully skinned | 13 bitmap id(s) it references do not resolve, leaving a visible gap: `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`…; unimplemented MAKI: `enumitem` ×4; 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro_Munchen**<br>`cPromunchenbywilians.wal` | — | B<br><sub>provisional</sub> | Player skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top`, `player.o.topleft` |
| **cPro_Orca**<br>`cPro_Orca.wal` | — | B<br><sub>provisional</sub> | Player skinned | 16 bitmap id(s) it references do not resolve, leaving a visible gap: `beat.0.right`, `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right` and 8 more |
| **cPro_RadioPlay**<br>`cPro_RadioPlay.wal` | — | B<br><sub>provisional</sub> | Player skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `size.khzkbps`, `studio.BaseTexture` |
| **cPro_smpldrk**<br>`cPro_smpldrk.wal` | — | B<br><sub>provisional</sub> | Player skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `beat.0.right`, `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right` |
| **cPro_smplwhite**<br>`cPro_smplwhite.wal` | Veronica Mogni aka Veroka | B<br><sub>provisional</sub> | Fully skinned | open B396 (the window census hangs at the Windows-menu toggle) |
| **cPro_Winamp Modern**<br>`211786-Cpro_Winamp_Modern.wal` | — | C<br><sub>provisional</sub> | Fully skinned | 13 bitmap id(s) it references do not resolve, leaving a visible gap: `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`…; unimplemented MAKI: `enumitem` ×4; 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **cPro_WinampVista**<br>`cPro_WinampVista.wal` | David Wood | B<br><sub>provisional</sub> | Fully skinned | open B396 (the window census hangs at the Windows-menu toggle) |
| **cPro_ZunAmp**<br>`ZunAmp_1.wal` | — | B<br><sub>provisional</sub> | Player skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`, `player.o.top` |
| **CROSSNET**<br>`CROSSNET_Official_skin.wal` | REDKiller | B<br><sub>provisional</sub> | Fully skinned | 22 bitmap id(s) it references do not resolve, leaving a visible gap: `component.Resize`, `player.ToggleButtons.face.ML`, `player.ToggleButtons.face.MUET`, `player.ToggleButtons.face.REPET`, `player.ToggleButtons.face.VID`, `player.ToggleButtons.face.VIS`, `player.ToggleButtons.off`, `player.button.next.face` and 14 more |
| **Cruz Azul**<br>`Cruz_Azul.wal` | Eduardo Iracheta | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Crystal Power**<br>`Crystal_Power_by_ROBODRON.wal` | Robodron | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Crystal_Skin**<br>`Crystal_Skin.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **CSA Skin (Cricket South Africa)**<br>`CSA_skin_v1.wal` | Lucky Melton Kutu | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.no.album.art` |
| **CSL**<br>`CLS-JO.wal` | JO | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **CSL**<br>`SpongeBob_Squarepants.wal` | JO | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `about.fg` |
| **CTI**<br>`Nitrous_Audio_CTI_2_Glass.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **CTI**<br>`Nitrous_Audio_CTI.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **CTI 2**<br>`Nitrous_Audio_CTI2.wal` | — | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **Customize.RU AMP**<br>`Customize.RU_Skin.wal` | Guljay S.V. aka Serg | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `window\bgtimer.png` |
| **CyclopVX-1**<br>`Cyclop_VX1.wal` | Boki | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **D-K9**<br>`D-K9.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **D-Reliction**<br>`4-drelictionreleasepic.wal` | — | C<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `Layer`, `notifier.bg.inner`, `player.Beat`; unimplemented MAKI: `isobjectvalid` ×6; 30 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 3 error-severity load finding(s) |
| **D-Shock**<br>`D-Shock.wal` | Robouk + Vica | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **Daniel Martin Diaz Skin**<br>`Black_Heart.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 7 bitmap id(s) it references do not resolve, leaving a visible gap: `player.cover`, `player.eq.button.resize`, `player.toggler.crossfade.pressed`, `wasabi.button.less`, `wasabi.button.less.pressed`, `wasabi.button.more`, `wasabi.button.more.pressed` |
| **Daniel Martin Diaz Skin**<br>`Sacred_Heart.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 7 bitmap id(s) it references do not resolve, leaving a visible gap: `player.cover`, `player.eq.button.resize`, `player.toggler.crossfade.pressed`, `wasabi.button.less`, `wasabi.button.less.pressed`, `wasabi.button.more`, `wasabi.button.more.pressed` |
| **Danielle Fishel: Double Diamond**<br>`Danielle_Fishel_Double_Diamond_1_1.wal` | flatmatt | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Dark Knight**<br>`The_Dark_Knight_Winamp5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **dark peace skin**<br>`dark_peace_v3.wal` | sinan bahadir "aka" watercolours | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **David Beckham**<br>`David_Beckham_Winamp_3_Skin.wal` | Richard Lee | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Dawn of the Dead**<br>`Dawn_of_the_Dead.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Dawson's Creek**<br>`Official_Dawsons_Creek_Series_Skin.wal` | — | B<br><sub>provisional</sub> | Fully skinned | its video button opens nothing: the skin declares no video window (open B403) |
| **DDTank Glass**<br>`DDtank_Glass_Winamp_Skin.wal` | Donny Indrapati | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `Close2.base_i`, `avs.bg.fill`, `avs.bg.middle`, `back`, `seeker.bg.vertical.right` |
| **Deals And You**<br>`Win_an_iPad!.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `nokia.logo` |
| **Defix Hi-End 200**<br>`Defix Hi-END 200.WAL` | Tankevich Denis | **B**<br><sub>live, as of 2026-08-18</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `FRAMING_GLASS.window`, `Lighting.Element`; 14 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **DEMO**<br>`bali.wal` | Faris Wijaya | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `component.bg`, `wasabi.frame.basetexture` |
| **Desktop Energy**<br>`GNature.wal` | amitsaran | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Devay**<br>`Devay.wal` | Vica. | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `wasabi.frame.basetexture` |
| **Deviantart Tattoo**<br>`Tattoo_Amp.wal` | quadhelix,Jory Compendio | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **DewyTears**<br>`DewyTears_BlackGlassV2.5.wal`<br><sub>also installed as `dewytears_v2_5_by_dewytear_d2yn025_BlackGlass.wal`</sub> | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **DewyTears**<br>`DewyTears_PinkGlassV2.5.wal`<br><sub>also installed as `dewytears_v2_5_by_dewytear_d2yn025_PinkGlass.wal`</sub> | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **DewyTears**<br>`DewyTears_TransparentV2.5.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **DewyTears V4**<br>`YoungJin_Kwak.wal` | Made by Young-Jin Kwak | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **DewyTears V4**<br>`YounJin_Kwak_(dewytear).wal` | Made by Young-Jin Kwak | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Diablo 4 Skills V2**<br>`Diablo IV Skills V2.wal` | sambaneko | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `paragon.seeker.point` |
| **Dill Mill Gaye**<br>`Dill_Mill_Gaye_1.0.wal` | Gurupreet Singh | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Dna Repair-Vibe Machine**<br>`Dna_RepairVM_by_ROBODRON.wal` | Robodron | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Domino Movie**<br>`DOMINO.wal` | VPI | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `player.dukes`, `player.dukes2`, `player.glass`, `player.ws.cover` |
| **donaumarkt.com**<br>`donaumarkt_MP3_Festival.wal` | Stefan M. Sheppard | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Doublehelixes Winamp Skin**<br>`Doublehelix.wal` | Caesarleo (http://metalgrin.fluxide.com) | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Dr Who - Monsters and Villains**<br>`Dr_Who_--_Monsters_and_Villains.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Dr Who - Tenth Doctor Adventures**<br>`Doctor_Who_-_10th_Dr_Adventures.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Dr Who - The Ten Doctors**<br>`Dr_Who_The_Ten_Doctors.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Draculas Helmet**<br>`Draculas_Helmet.wal` | -=RoNtZ=- | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `frame.button.close`, `wasabi.frame.basetexture` |
| **Dragon Skin v2.0**<br>`Dragon_v3.0.wal` | Pan deMonicon | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `titlebar.eq.active`, `titlebar.eq.inactive`, `wasabi.titlebar.overlay`, `xfade.bg`, `xfade.display.bg` |
| **DreddfulAmp**<br>`DreddfulAmp.wal` | Inertia | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Drone**<br>`Dronev11.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 5 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Drone**<br>`Drone_v1.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `window.normal.title.notifier`, `window.normal.title.notifier.inset` |
| **DYNAMIC**<br>`Dynamic.wal` | Sinan | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **E_I**<br>`EI.wal` | Joo' Imre | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Ebonite**<br>`Ebonite_2_1.wal` | WinstonGFX and SLoB | C<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `brightness.bg1`; unimplemented MAKI: `enumgammagroup` ×2, `setchecked` ×2; 7 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 4 error-severity load finding(s) |
| **Ebonite**<br>`Ebonitefix.wal` | Mike Winston aka WinstonGFX and SLoB | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Echerry**<br>`Echerry.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Echo**<br>`Echo.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Eeyore-toy**<br>`Eeyore-toy1.wal` | ivan gomez | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **EGG**<br>`EGG.wal` | — | B<br><sub>provisional</sub> | Fully skinned | some hosted windows intermittently open without the skin's frame (B465); 3 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `player.normal.winclose`, `wasabi.frame.basetexture` |
| **EIV2**<br>`EI_V2.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **ELECTRA WINAMP SKIN**<br>`Electra_Winamp_Skin.wal` | LEGION | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Electric Guitar Skin**<br>`Electric_Guitar_Skin.wal` | Grasshopper | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Electric Guitar Skin**<br>`Bigreds_IOLSC_Bjm_Unofficial_BetaVersion.wal` | Grasshopper | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `component.region.bottom.left`, `component.region.bottom.right`, `component.region.top.left`, `component.region.top.right` |
| **Electrolium**<br>`Electrolium.wal` | jsosic | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Electronica Industriala**<br>`Electronica_Industriala.wal` | Goe | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `speaker.grille`, `speaker.rim`, `win.center` |
| **EMP - Evolved Media Player**<br>`EMP.wal` | Andrew Mackowski | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **EMP - Evolved Media Player**<br>`EMP2.wal` | Andrew Mackowski | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **EndlesS**<br>`EndlesS.wal` | fleschmmeister | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `m_splay` |
| **Energy3**<br>`Energy3.wal` | mc^^^^ - Michael McBriar | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Energy_Hands_by_ROBODRON**<br>`Energy_Hands_by_ROBODRON.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Enkera**<br>`Enkera.wal` | 883 | B<br><sub>provisional</sub> | Fully skinned | 4 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Enter the Matrix**<br>`Enter_the_Matrix.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Enya**<br>`Enya_Winamp_3_Skin.wal` | Jim Joiver Torres | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **EPS (Egor Petrov Systems)**<br>`EPS_High-End_System_v1_test.wal` | Egor Petrov | C<br><sub>provisional</sub> | Player skinned | 9 bitmap id(s) it references do not resolve, leaving a visible gap: `meterback`, `pausetip`, `peak`, `playtip`, `shade.bg.met`, `speaker3`…; unimplemented MAKI: `setchecked` ×2; 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140); 13 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 1 error-severity load finding(s) |
| **Epsilux**<br>`Epsilux.wal` | Fyre (Patrick Li) and scripted by nIRV (Mathieu Pellerin). | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Eve**<br>`Eve_01_Amp.wal` | Nick Wagner | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **EVo**<br>`Pepsi_EVo.wal` | Graphics by: Tien Pham; Programming by: Jay Hough | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **evolver**<br>`evolver.wal` | boostr29 | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **EW**<br>`EW.wal` | Roberto Cuellar Gamez | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **falcon**<br>`cd-FALCON.wal` | DEMONA EVILIVANO | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Fanta**<br>`Official_Fantana_Skin.wal` | Adil and Will for Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | open: B382 (declared boxes overlap; B290 fontsize) |
| **Fast And The Furious**<br>`Tokyo_Drift.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Fast And The Furious 4**<br>`Fast__Furious_Winamp5_Skin.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **FedererAmp**<br>`FedererAmp.wal` | Raghav Venkat | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Fenerbahce_Old_Flag_1907**<br>`Fenerbahce_Old_Flag_1907.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **FierY_GEAr**<br>`_Fiery_Gear_.wal` | Bahmet | B<br><sub>provisional</sub> | Partly skinned | nothing outstanding that a headless pass can see |
| **FIFA World Cup Germany 2006**<br>`FIFA_WorldCup_Germany_2006.wal` | Saeed Azari Tavana (S.A.T.co) | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **Fifi**<br>`Fifi__Modern.wal` | s0meSkunk | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Final-Fantasy X-2**<br>`Final-Fantasy_X2_Unofficial_Skin.wal` | Marshall "WhtieDragon" Radziwilko | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Final-Fantasy X-2**<br>`Final_Fantasy_X-2_II_Skin.wal` | Marshall "WhtieDragon" Radziwilko | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture@winamp3.112` |
| **Firefox**<br>`Firefox.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Flightplan**<br>`FLIGHTPLAN.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **flipclock**<br>`FlipClock.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `wasabi.frame.basetexture` |
| **Flo**<br>`-Flo-.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **fnk 32**<br>`fnk_32v1R10.wal` | Rohan Prabhu | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Foo Fighters**<br>`Official_Foo_Fighter_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `win.center` |
| **Ford GT40 V1.0**<br>`FordGT.wal` | Ben_SisTeck | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Formamp**<br>`Formamp.wal` | coronerss | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **FreddyvsJason**<br>`Freddy_vs_Jason.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Friends**<br>`Friends_nbc.wal` | Sony | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **FRIENDS**<br>`FRIENDS_1_1_1.wal` | GHABRIUS KLEM AND MARTIN DEIMOS | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Funktion**<br>`funktion_v2.wal` | Jason Van Pelt | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `video.playback.placeHolder` |
| **Fuzzy Muffins**<br>`Fuzzy_Muffins.wal` | fuzzy muffins | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **G-tutorials.dap.ro**<br>`gtutorials.dap.ro.wal` | Priscu Vlad | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **G2**<br>`G2.wal` | Whatsitsname | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **Gateway VR 46**<br>`Gateway_Valentino_Rossi_-_46.wal` | caesarleo | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **GC-Skin**<br>`GC_Winamp_Skin.wal` | MinneMedia.com (design), Rontz (coding) | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **GGXX WINAMP5 SKIN**<br>`GUILTY_GEAR_XX_WINAMP5_SKIN.wal` | LEGION | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Ghost Slate**<br>`Ghost_Slate.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `wasabi.frame.basetexture` |
| **Gintama  Gintoki & Katsura**<br>`Gintama__Gintoki_&_Katsura.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **GlassAMP**<br>`GlassAMP2.wal` | jeree01@gmail.com | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **GlassAMP**<br>`GlassAMPfinal.wal` | jeree01@gmail.com | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `displayBGWHITE`, `eq.normal.Balance.Label` |
| **Go Army**<br>`Official_Go_Army_Winamp5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Godsend_Winamp5_Skin**<br>`Godsend_Winamp5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Godsmack**<br>`Godsmack_-_Faceless.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **GOKS**<br>`XP_Blue_ver2.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `component.region.bottom.left`, `component.region.bottom.right`, `component.region.top.left`, `component.region.top.right` |
| **GOKS**<br>`skin_by_GOKS.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **GoldenBeauty**<br>`GoldenBeauty.wal` | Aimz | B<br><sub>provisional</sub> | Fully skinned | open: B327 (floating text below the main window, not reproduced) |
| **Gonchi Skin**<br>`GonchiSkin.wal` | Pablo Armendariz | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Grafika**<br>`grafika.wal` | Twan Verstegen | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **Graviton**<br>`-Graviton-.wal` | Infinil-Daniel Mauch | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **Graviton**<br>`Graviton.wal` | Infinil-Daniel Mauch | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **GrayZ**<br>`Metaskins_net_-_GrayZ.wal` | VAG - Design -- Flo - XML + Scripting | B<br><sub>provisional</sub> | Fully skinned | open: B381 (the skin's `onVolumeChanged` stores 0 during its own mute) |
| **Green Dream**<br>`GreenDream.wal` | David Serrano | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **GREEN MACHINE**<br>`Green_Machine.wal` | Mike Ludwig | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Grind**<br>`The_Official_Grind_Winamp_3_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `win.center` |
| **Gs**<br>`Gs_Skin.wal` | design by myk | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Gunslinger Girl Winamp 5 Skin**<br>`Gunsinger_Girl_Winamp_5_Skin_1.wal` | Fullspeed | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.top.right` |
| **GWlass**<br>`WGlass.wal` | lypnjtu | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **H2O Liquid**<br>`Metaskins_net_-_H2O_Liquid.wal` | VAG, FrisbeeMonkey and -=RoNtZ=- | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Hal's Eye**<br>`1-Hal__s_Eye_v1_2.wal` | -=RoNtZ=- | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `about.bg`; 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Hal's Eye**<br>`Hals_Eye_1_3.wal` | -=RoNtZ=- | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Halloween2003**<br>`Halloween2003.wal` | R. Peter Clark | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **HALO**<br>`HALOAMP.wal` | JJ.Ying | B<br><sub>provisional</sub> | Fully skinned | 18 bitmap id(s) it references do not resolve, leaving a visible gap: `background.display.left.outline`, `background.display.middle`, `background.display.right.outline`, `border.bottom.left`, `border.bottom.middle`, `border.bottom.right`… |
| **HALO-REACH-ELITE-PLAYER**<br>`HALO_REACH_ELITE_AMP_1.2F.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 122 bitmap id(s) it references do not resolve, leaving a visible gap: `component.left-bottom-bg`, `component.right-bottom-bg`, `component.top-left-bg`, `component.top-right-bg`, `player-winshade.toggler.crossfade`, `player-winshade.toggler.repeat`, `player-winshade.toggler.shuffle`, `player.anim.bass` and 114 more |
| **HardHouseCafeAmp**<br>`HardHouseCafeAmp.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Hardware**<br>`Hardware.wal` | Chimpzilla | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Harmoniagh**<br>`HARMONIA.wal` | Behrooz | B<br><sub>provisional</sub> | Partly skinned | 6 bitmap id(s) it references do not resolve, leaving a visible gap: `component.region.bottom.left`, `component.region.bottom.right`, `component.region.top.left`, `component.region.top.right`, `eq.back`, `player.volume` |
| **Harmonized Water**<br>`Harmonized_Water_by_ROBODRON.wal` | Robodron | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Harmonizer**<br>`Harmonizer_by_ROBODRON.wal` | Robodron | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Haruhi WINAMP5 SKIN**<br>`SOS_Brigade_Winamp5_skin.wal` | LEGION | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Hatsune Miku 5 Winamp Skin**<br>`hatsune_miku_5_winamp_by_kaza_sou_d6izotp.wal` | kazasou feat. msdzero | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **HeadAMP**<br>`HeadAMP.wal` | sambaneko | B<br><sub>provisional</sub> | Fully skinned | 27 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Heart of Steel**<br>`Heart_of_Steel.wal` | BriAnna Shultz | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Helios**<br>`Helios.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Hellemium**<br>`Hellemium.wal` | Laurent LM | B<br><sub>provisional</sub> | Fully skinned | its song ticker declares no `ticker`, so a long title is clipped (B379, the skin's) |
| **Helloween**<br>`Helloween.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | the radio stream its nose starts never answers, and no error is shown (open M87) |
| **Herbie**<br>`Herbie.wal` | — | B<br><sub>provisional</sub> | Fully skinned | the round volume knob only follows a drag that starts on its indicator: the skin's own handler (B361, closed as the skin's) |
| **Heroes**<br>`Heroes.wal` | JayEm | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Hitchhikers Guide To the Galaxy**<br>`Hitchhikers_Guide.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | its first-run country-selection window never opens |
| **hm_Touch**<br>`hm_Touch_m_1.wal` | Heiko Mamsch | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Hong Kong Phoo3y!**<br>`Hong_Kong_Phooey_V3.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Hoop Life!**<br>`Hoop_Life_WA3_version.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Hot Action Cop**<br>`Official_Hot_Action_Cop_Skin.wal` | Demian Trimble | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **House of Evil EP (Evil Player)**<br>`House_of_Evil_E.P._Evil_Player.wal` | Ben Tjibe | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **House of Evil Portable**<br>`H.o.E._P.wal` | Ben Tjibe | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **How to Deal**<br>`Official_How_to_Deal_Winamp3_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **HP**<br>`The_HP_Winamp_Skin.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **hpcalc HP49G**<br>`hpcalc_HP49G.wal` | Arne Olav Storflor | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **HUD**<br>`HUD.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Hybrid**<br>`Hybridv10.wal` | Flo/Rontz - Idea, Gfx, XML + Scripting | C<br><sub>provisional</sub> | Partly skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`; a container it declares has no layout to show, so no window of its own |
| **I N D U C E R Version 1.0**<br>`Inducer.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `eq.lght`, `s.repeat.dn`, `stickleftstretch`, `xbuts.repeat.down` |
| **I-M-S**<br>`I-M-S-72.wal` | JO | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `1-SKIN` |
| **iAmp**<br>`iAmp.wal` | Hans Schmucker | C<br><sub>provisional</sub> | Partly skinned | the Media Library opens in NullPlayer's plain chrome (the skin declares no frame of its own) |
| **Ice Bear the Third**<br>`MD_-_Ice_Bear_Lain_the_Third.wal` | Asakura Rantisi Kay | B<br><sub>provisional</sub> | Fully skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `Lain.framedown`, `Lain.frameleft`, `Lain.frameright`, `Lain.frameup`, `Lain.innerborders`, `eq.ticker`, `thinger.bucket`, `thinger.ticker` |
| **Ichigo And Rukia Modern 1.0**<br>`Ichigo_And_Rukia_Modern_Skin.wal` | Rukasuzu | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `m_prev` |
| **Ichigo Mashimaro**<br>`Ichigo_Mashimaro_(Ind1.0).wal` | Indra Rantisi Pratama aka. selain00 | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `ichigo.bg.shade` |
| **Impulse**<br>`impulse_by_a_t_o_m_i_c_d4wcub.wal` | a-t-o-m-i-c | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `window.normal.resizer`; 13 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Impulse**<br>`Impulse.wal` | a-t-o-m-i-c | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **informatika6**<br>`informatika6.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **inima**<br>`heart_.wal` | daniel sioneanu | B<br><sub>provisional</sub> | Fully skinned | open B434 (the Playlist button's press goes to a duplicate layer) |
| **Insomniac V1.2**<br>`Insomniac_v1.wal` | Chimpzilla | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **iNTELLIdesign**<br>`intellidesign.wal` | SarKnagel (Design) and Deimos, SLoB (Advanced coding) | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **iNTELLIdesign**<br>`iNTELLI_design.wal` | SarKnagel (Design) and Deimos, SLoB (Advanced coding) | B<br><sub>provisional</sub> | Fully skinned | 6 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `wasabi.panel.bottom`, `wasabi.panel.bottom.left`, `wasabi.panel.bottom.right`, `wasabi.panel.left`, `wasabi.panel.right` |
| **Intensity 3**<br>`Intensity_3.wal` | Carlos Hdz. | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Inter-Pol.info AMP**<br>`ipamp14.wal` | Guljay Sergey Viktorovich aka Serg from Belarus, Mozur | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Intruder**<br>`Intruder.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Invicta**<br>`Invicta.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **iPhone**<br>`iPhone.wal` | Michael Keiller | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `player.glass`, `player.jeepbt`, `player.linksbt`, `player.picsbt`, `player.ws.jeepbt`. Its markup lays the spectrum box (x 73–243) over the middle of the vertical seek bar (x 75–89), so a press there toggles the vis instead of seeking; seek works above and below it |
| **iPlay**<br>`iPlay.wal` | playboy | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **IPod Skin**<br>`Snow_AMp.wal` | CarlosP | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **iRobot**<br>`iRobot.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **IronCross**<br>`Iron_Cross.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **iSkin**<br>`iCandy-2.wal` | Judge | C<br><sub>provisional</sub> | Partly skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`; no window of its own for the library: a NullPlayer window stands in |
| **iSkin**<br>`i-Skin.wal` | Judge | C<br><sub>provisional</sub> | Partly skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`; no window of its own for the library: a NullPlayer window stands in |
| **iSkin**<br>`iCandy.wal` | Judge | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **Itemskin**<br>`Itemskin.wal` | — | C<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `player.main.extras.textbox.left`, `player.songinfo.stereo`, `player.songinfo.stereomono`; unimplemented MAKI: `setchecked` ×4; 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 2 error-severity load finding(s) |
| **iTunes Mini LabelOS**<br>`iTunesMiniAppleheavenmaliktrey.wal` | newaveCR | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `displayscreen`, `player.VolumeKnob.blank` |
| **iTunes Mini LabelOS**<br>`iTunes_Mini_LabelOS_by_newaveCR.wal` | newaveCR | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `displayscreen`, `player.VolumeKnob.blank` |
| **iTunes PowerMetal2**<br>`iTunes_Mini_PowerMetal2_by_newaveCR.wal` | newaveCR | B<br><sub>provisional</sub> | Fully skinned | open B438 (buttons reported slightly off the art, not reproduced) |
| **iTunes Silvier**<br>`iTunes_Mini_Silvier_by_javier&newaveCR.wal` | newaveCR | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `displayscreen`, `player.VolumeKnob.blank` |
| **iTunes XiAlbook**<br>`iTunes_Mini_XiDGAlbook_by_newaveCR.wal` | newaveCR | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Iwakura Lain the Fourth**<br>`MD_-_Iwakura_Lain_the_Fourth_v1.wal` | Asakura Rantisi Kay | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `eq.ticker`, `thinger.bucket`, `thinger.ticker`, `wasabi.frame.basetexture` |
| **J5**<br>`J5.wal` | FrisbeeMonkey | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **James Kellison**<br>`James_Kellison.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **January 29**<br>`January_29.wal` | Kim,Soo-young | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Java Duke**<br>`Java_Duke.wal` | TheBlackDeath | B<br><sub>provisional</sub> | Fully skinned | no seek control (B380, the skin's) |
| **Jeep**<br>`Jeep_Wrangler_Winamp5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Jelly Fingers**<br>`Jelly_Fingers.wal` | Jared Gummig | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `thinger.main.lcd` |
| **Jelly Fingers**<br>`CD_Amp.wal` | Jared Gummig | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Jelly Fingers**<br>`Stone_Relic.wal` | Jared Gummig | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Jenna loves Mambo**<br>`Jenna_loves_mambo.wal` | Lucignolo | C<br><sub>provisional</sub> | Partly skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.button.close`; no window of its own for the library or the playlist: a NullPlayer window stands in |
| **Jesse McCartney**<br>`Classic_Jesse_McCartney.wal` | Shisse | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Jessica Alba Modern Skin**<br>`Jessica_Alba_Modern_Skin_ver_1.wal` | Silver Lion | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **JetBlue Card**<br>`JetBlue_Card_Winamp5_Skin.wal` | PetrolDesigns | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **JIP**<br>`Ar-Za-Jo.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **JPod**<br>`Jpod.wal` | NeuroSkins | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **JRS**<br>`JRS.wal` | mc^^^^ - Michael McBriar | B<br><sub>provisional</sub> | Fully skinned | 6 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **JSB**<br>`Bach.wal` | NA broths | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Jukebox**<br>`Flashing_Jukebox.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `wasabi.frame.basetexture` |
| **Jukebox**<br>`Juke_Box_1950.wal` | — | **C**<br><sub>provisional</sub> | Partly skinned | the Media Library opens in NullPlayer's plain chrome: the skin declares no frame of its own; 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.button.mute.bg` |
| **Just Buttons**<br>`Just_Buttons.wal` | Phil Atkin | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Justin_Bieber_Skin_Winamp**<br>`Justin_Bieber_Skin_Winamp.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **JVC Tape**<br>`jvc.tape.v0.5.wal` | — | C<br><sub>provisional</sub> | Partly skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `pl.button.bg`, `pl.button.small`; no library window of its own; 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140); 3 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **K-Jofol_V5**<br>`K-Jofol_V5.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **K-jr**<br>`K-jr.wal`<br><sub>also installed as `k_jr_winamp_skin_by_marisa85_d329ymw.wal`</sub> | Marisa85 | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `img/bt_crf.png`, `img/bt_none.png` |
| **K-ON! - Hirasawa Ui Winamp Skin**<br>`KON!__Hirasawa_Ui.wal` | AZN Team | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **K-Tech SFX - 201**<br>`K-Tech_SFX_-_201.wal` | Tibi Ardelean | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Kaolla2**<br>`Koalla_2.wal` | Jason L. , Mathieu P. | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **Kaskus KRKT**<br>`Kaskus_regional_Kalimantan_Tengah.wal` | odie callista | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Kaskus Winamp Skin**<br>`Kaskus_.wal` | Caesarleo (http://metalgrin.fluxide.com) For my lovely Elistia | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Kaskus Winamp Skin**<br>`Kaskus_Black.wal` | Caesarleo (http://metalgrin.fluxide.com) For my lovely Elistia | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `button`, `songcover` |
| **Kaskus Winamp Skin 2010**<br>`Kaskus_Batik_Indonesia.wal` | caesarleo | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Keep on truckin'**<br>`Keep_on_truckin.wal` | ArcticWolf | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Kepler**<br>`Kepler_1.1.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Kids WB**<br>`The_KidsWB_Winamp_3_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Kite-Liberator**<br>`Classic_Yasuomi_Umetsu.wal` | By RagingEdd | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **KMS**<br>`KMS_v104.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **KrazyPlayer**<br>`krazyPlayer.wal` | Skin Consortium | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `makemeblank0`, `layout.volumebar`; 6 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **KTENSION**<br>`KTENSION.wal` | daniel sioneanu | B<br><sub>provisional</sub> | Fully skinned | 16 bitmap id(s) it references do not resolve, leaving a visible gap: `player.button.repeat.bg`, `player.button.shuffle.bg`, `player.display.bg.center`, `player.display.bg.left`, `player.display.bg.right`, `player.display.center`, `player.display.left`, `player.display.left.overlay` and 8 more |
| **Kyoko Fukada**<br>`Kyoko_Fukada.wal` | Hikari Hendri | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Laboratory Clinical Art**<br>`Laboratory_Clinical_Art.wal` | John Bahmet | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `win.back`, `win.next`, `win.play`, `win.stop` |
| **Lapis Lazuli**<br>`Lapis_Lazuli.wal` | Jamie McDonald | B<br><sub>provisional</sub> | Fully skinned | its song title and the band behind it run past the triangle onto the frame's right arm (open B411) |
| **Lara Flynn Boyle - The Devil Inside V3**<br>`Lara_Flynn_Boyle_The_D3vil_Inside.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **LayerONE**<br>`LayerONE.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **LayerONE**<br>`LayerONE-2.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `stick.back` |
| **LCD_hm1m**<br>`LCD_hm1_m.wal` | Heiko Mamsch | B<br><sub>provisional</sub> | Fully skinned | its video button opens nothing: the skin declares no video window (open B403) |
| **LCDx**<br>`LCDx.wal` | — | B<br><sub>provisional</sub> | Player skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.button.label.arrow.left`, `wasabi.button.label.arrow.right` |
| **LelouchvB**<br>`Lelouch_of_Code_Geass.wal` | rainbowxtina | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Leviathan**<br>`Leviathan-1_0_b.wal` | Jorge Mancheno | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **LexAmp**<br>`The_Official_Lex_Luthor_Winamp5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | its `switchskin(LexAmp_Win2.wsz)` names a classic skin the archive does not ship (the skin's) |
| **lexicon**<br>`Lexicon_1.wal` | ssahl | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **LG Cookie**<br>`LG_Free_touch_the_music_.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **LichtenStein**<br>`LichtenStein.wal` | Shri Aniel | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Linkin Park**<br>`Official_Linkin_Park_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `win.center` |
| **LiquidStar**<br>`LiquidStar.wal` | Cory MAnthei | C<br><sub>provisional</sub> | Partly skinned | Media Library opens in NullPlayer's plain chrome: the skin declares no frame of its own |
| **Lithium**<br>`-Lithium-.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Liverpool F.C.**<br>`Liverpool_FC_Winamp_3_Skin.wal` | Richard Lee | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **LOBE**<br>`Lobe.wal` | graphics and coding: boostr29 | **C**<br><sub>live, as of 2026-08-21</sub> | Fully skinned | 14 bitmap id(s) it references do not resolve, leaving a visible gap: `border`, `drawer.left.bg`, `drawer.right.bg`, `main.00002`, `main.attatchment`, `main.glass.lower`…; 1 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `thinger.over`; 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Logicallity**<br>`LogicallityV1_0.wal` | Slobodan Pejic (Slobo972) | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Loonatics**<br>`Loonatics_Unleashed.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Looney Tunes**<br>`Looney_Tunes_Back__in_Action.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Lord of the Rings: The Two Towers**<br>`Official_LOTR_The_Two_Towers_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Lou Reed -The Raven-**<br>`Lou_Reed_-_The_Raven.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Lounge**<br>`Lounge.wal` | Morgan aka. 'Splif' THOMAS. WA5 version by Mr Jones. Open Source Notifier by iPlayTheSpoons. | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Love is War Miku Hatsune Winamp Skin**<br>`Love is War Miku.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Love is War Miku v2 Winamp Skin**<br>`Love Is War Miku V2.wal` | maxim cryseria | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `player.volbg`, `player.volume`; 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Ludwig Bemelmans Madeline**<br>`Ludwig_Bemelmans_Madeline.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **mac os x**<br>`Macosx-2.wal` | nkj | C<br><sub>provisional</sub> | Partly skinned | the Media Library opens in NullPlayer's plain chrome (the skin declares no frame of its own) |
| **Mac OS X - Panther**<br>`Mac_OS_X__-_Panther.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `player.button.Xfade`, `player.button.repeat`, `player.button.shuffle`; 3 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **MacOSesque**<br>`MacOSesque_v1_2.wal` | Nitish Jha and Chris Berry | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Mad Magazine Skin**<br>`Official_Mad_Magazine_Skin.wal` | Taber Buhl | C<br><sub>provisional</sub> | Partly skinned | no window of its own for the library: a NullPlayer window stands in |
| **MalteseXpSkin**<br>`MalteseXpSkin.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Manchester United Football Club: The Red Devils**<br>`Manchester_United_Red_Devils_Skin.wal` | Richard Lee | C<br><sub>provisional</sub> | Partly skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.button.label.arrow.left`, `wasabi.button.label.arrow.right`, `wasabi.button.resize`; no window of its own for the library or the playlist: a NullPlayer window stands in |
| **Manhunt**<br>`Manhunt_Official_Skin.wal` | Anh Tuan Pham, Jerry Luna, Jeff Williams | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Manutd**<br>`Manutd.wal` | Ramin Mousavi | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Massive Attack**<br>`Massive_Attack_100th_Window.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `win.center` |
| **Matrix Online Winamp5 Skin**<br>`Matrix_Online.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Matrix_beta1**<br>`M3.wal` | WA3_skinners | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Max Payne 2**<br>`Max_Payne_2_Official_Skin.wal` | A.Marzan, Jerry Luna, Jeff Williams | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **MBOS**<br>`MBOS.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **MD__Ganbare_Rakkatan_the_Sixth_(fixed)**<br>`MD__Ganbare_Rakkatan_the_Sixth_(fixed).wal` | Indra pratama a.k.a. Asakura Rantisi Kay | B<br><sub>provisional</sub> | Fully skinned | 11 bitmap id(s) it references do not resolve, leaving a visible gap: `player.auto.off`, `player.draw.base`, `player.draw.bottom`, `player.draw.map`, `player.eq.back.or`, `player.eq.n`… |
| **Media Whore**<br>`Media_Whore.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Megan Fox**<br>`Megan_Fox.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Megurine Luka Winamp Skin**<br>`Megurine Luka.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Mein Teil**<br>`Mein-Teil.wal` | Laurent LM | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `wasabi.frame.basetexture` |
| **Mercury**<br>`_Mercury.wal` | R. Peter Clark | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **MERCURY**<br>`MERCURY_1.0F.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Meridian**<br>`meridian.wal` | Neuroskins | B<br><sub>provisional</sub> | Fully skinned | 18 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **MERV_skin_v2**<br>`MERV_skin_v2.wal` | John Bahmet | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `buttons.close` |
| **MetaAlchemyIII**<br>`MetAlchemy_III_Wa3.wal` | — | C<br><sub>provisional</sub> | Partly skinned | no window of its own for the library: a NullPlayer window stands in |
| **Metal Gear Solid 2**<br>`Metal_Gear_Solid_2_Skin.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Metal Vista**<br>`MetalVista.wal` | lypnjtu | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `displayscreen`, `player.VolumeKnob.blank` |
| **MetalEdge**<br>`MetalEdge_v1.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **MFD by Tikvach Alexander aka unl0K**<br>`MFDAMPbyunl0Kv11.wal` | Tikvach Alexander | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **MfS3**<br>`-MfS3-.wal` | Aleksandar Ruzicic | C<br><sub>provisional</sub> | Partly skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `icons.bgd`; no window of its own for the library or the playlist: a NullPlayer window stands in; open: B306 (the oscilloscope shows no trace) |
| **mGen Skin**<br>`mcgen v1.2.wal` | Fritz Mehler | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **micro**<br>`micro.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `component.region.bottom.left`, `component.region.bottom.right`, `component.region.top.left`, `component.region.top.right`; 4 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **MIDISUI**<br>`MIDISUI_1_1.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player/vu_button.PNG` |
| **Midnight Club 2**<br>`Official_Midnight_Club_2_skin.wal` | Jake King, Jerry Luna, Jeff Williams | C<br><sub>provisional</sub> | Partly skinned | no window of its own for the library: a NullPlayer window stands in |
| **Miley Cyrus Gray line 1**<br>`Miley_Cyrus_Gray_line_1.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **MINCH YODA**<br>`MINCH_YODA_1.0F.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `player.enos-off`, `player.meeler-off`, `player.sh.bg`, `player.sh.next`, `player.sh.pause`, `player.sh.play`, `player.sh.prev`, `player.sh.stop` |
| **Mini iPod**<br>`MIni_Ipod.wal` | Fore | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Minim3 2003**<br>`Mini_Me.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Minima**<br>`Minima.wal` | PercassoWG | B<br><sub>provisional</sub> | Fully skinned | its display panel is black where its screenshot shows navy (open B404) |
| **Minime IV - Resurrection**<br>`Mini_Me_IV.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Minime2 - Reloaded**<br>`Mini_Me_2_-_Reloaded.wal` | Mr Jones and Friends | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Minime3 - Revolutions**<br>`Mini_Me_III_Revolutions.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **MiniModern**<br>`MiniModern.wal` | Walter Mulder | B<br><sub>provisional</sub> | Fully skinned | no EQ, playlist or library toggles on the main layout (the skin's) |
| **miniPlayer**<br>`miniplayer.wal` | Skin Consortium | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Minus**<br>`Minus.wal` | Graphics: Skryingbreath --- Coding: Rohan Prabhu, Martin Poehlmann, SLoB, NickMikh | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **MiPod**<br>`MIPOD.wal` | SkinConsortium | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Miyabiskin**<br>`Miyabi_Skin.wal` | Nur Akbar Mappaleo (http://metalgrin.fluxide.com) For my lovely Elistia | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **MIZUHO WINAMP SKIN**<br>`Mizuho_Winamp_Skin.wal` | LEGION | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **MMD3**<br>`MMD3-4-5.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `pledit.buttonbg.add`, `pledit.buttonbg.misc`, `pledit.buttonbg.options`, `pledit.buttonbg.rem`, `pledit.buttonbg.sel`; 22 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **MMD3**<br>`mmd3.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 23 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Mogyoro**<br>`Mogyoro.wal` | Mogyoro | B<br><sub>provisional</sub> | Partly skinned | nothing outstanding that a headless pass can see |
| **MoodLogic 2.1**<br>`MoodLogic_Skin.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Moon Groove**<br>`Moon_Groove_1-1.wal` | Pascal Getreuer | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **Moonkore**<br>`Moonkore.wal` | hammerhead (aka kabir chanrai) | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `studio.seekbar.left`, `studio.seekbar.middle`, `studio.seekbar.right`; Windows → Equalizer is inert; the EQ opens from the skin's own drawer (B253) |
| **MoonLight**<br>`MoonLight.wal` | Marisa85 | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Morlock**<br>`Morlock.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Morning - 27**<br>`Morning_27.wal` | Hikari Hendri | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **Mortal Kombat Deadly Alliance Amp**<br>`Official_MK_Deadly_Alliance_Amp.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Motorcycle**<br>`Motorcycle.wal` | Dennis Scheffler | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Motorhead**<br>`motorhead_by_remib.wal` | remib | B<br><sub>provisional</sub> | Fully skinned | 8 bitmap id(s) it references do not resolve: `player.normal.display.cover` and seven `player.shade.*` ids; the shade bar's minimize, shade and close draw as NullPlayer glyphs because the skin never declares their art |
| **MSkin RyokoAsakura_ID000 WinampSkin**<br>`Ryoko_Asakura__Winamp_Skin_1_1.wal` | Mraven | B<br><sub>provisional</sub> | Player skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.mainbg.ghost` |
| **MSkin YukiMorikawa_ID001 WinampSkin**<br>`Winamp_Skin_Yuki_Morikawa.wal` | raven_of_death | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **MultiButtons**<br>`MultiButtons_v0.02.wal` | Cip | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.resizer`; open: B290 (a fontsize-less song title draws smaller than the reference) |
| **Multipass**<br>`multipass_1_4_by_rpeterclark_d5lwjv.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Multiplastic**<br>`Multiplastic.wal` | Bahmet | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Music Show**<br>`MusicshowB_version.wal` | Skin Consortium | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `onegd`, `resizel`, `resizer` |
| **Musica**<br>`Musica_by_pictoratus.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **MusicPad Classic**<br>`MusicPadClassic.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `player.normal.volumebar`, `wasabi.frame.basetexture` |
| **Musique Macabre**<br>`Musique_Macabre.wal` | Alexandru Pitea | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `m_splay` |
| **My Skin Name**<br>`cPro_SC.wal` | — | B<br><sub>provisional</sub> | Fully skinned | the window census timed out on it (harness, open B396) |
| **My Skin Name**<br>`cpro__City_Night.wal` | — | B<br><sub>provisional</sub> | Player skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `about.gfx`, `beatvis.overlay`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right` |
| **Narnia**<br>`The_Chronicles_of_Narnia.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Nascar 3D**<br>`IMAX_Nascar_3D.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Nathalie Hayashi**<br>`Nathalie_Hayashi.wal` | Andy Kobayashi | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.button.minimize` |
| **National Treasure**<br>`NationalTreasure.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `main.window.left` |
| **naturallz**<br>`NaturallZ.wal` | DaphatOne and Pimousse38 | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Nebular**<br>`Nebular.wal` | Vica. | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **nematic**<br>`nematicfinal.wal` | boostr29 | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **NEO**<br>`NEO.wal` | Corwin of Amber | B<br><sub>provisional</sub> | Player skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `dummy0` |
| **NEO CLASSIC**<br>`NEO_CLASSIC.wal` | Corwin of Amber | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `dummy0`, `wasabi.frame.bottom`, `text.vis`, `wasabi.button.close`, `wasabi.button.close.pressed` |
| **Neo iPod**<br>`Neo_iPod.wal` | JoshuaTree | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Neo Kaskus Winamp Skin**<br>`Kaskus_v_1.wal` | caesarleo | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `child1` |
| **Neon**<br>`Mehmet_Akar.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Neptune**<br>`_Neptune.wal` | R. Peter Clark | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **New Night**<br>`New_Night_v_2.wal` | Bahmet | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **NewAMP**<br>`NewAmp.wal` | Slawek Nowak | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **NewYorkMinute**<br>`New_York_Minute_Winamp5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **NightWing II**<br>`NightWing_II.wal` | Don Johnson | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **NIKE TOTAL 90 AEROW**<br>`Nike_total_90_aerow.wal` | Ramin Mousavi | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Nikki Nova V3**<br>`Nikki_Nova_V3.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **NINJA STAR**<br>`The_Ninja_Star.wal` | Mike Ludwig | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Nintendo**<br>`Nintendo.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **no-vita**<br>`No-Vita.wal` | UUL | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Noinc**<br>`Noinc.wal` | Noah Kim | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `player.normal.button.shade.overlay`, `wasabi.frame.basetexture` |
| **Noir's Kirika**<br>`Noir_Kirika_Modern.wal` | Lee Trudgeon | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Noir's Merielle**<br>`Noir_Merielle.wal` | Lee Trudgeon | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Nokia**<br>`Nokia_3650____Version_2.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Nokia**<br>`Nokia_5800_Xpress_Music.wal` | Saravanan K Sivanathan, Hithendra Rangaswamy | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `shade.volume` |
| **Nokia 3200**<br>`Nokia_3200_Winamp5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Nokia 3300**<br>`Nokia_3300_Winamp3_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Nokia 3650 Amp**<br>`CarlosPs_Nokia_3650.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **Nokia 5800 XpressMusic**<br>`Nokia_5800_XPressMusic_by_techmafia_1.wal` | The CyberWizard | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Nokia 5800 XpressMusic**<br>`Nokia_5800_XpressMusic.wal` | Jonathan Becker - www.denkwerk.com | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `player.main.eq`, `player.pl.time`, `player.pl.time.display` |
| **Nokia 6600 Skin**<br>`Nokia_6600_AWK.wal` | Wali "KAKAR" | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Nokia 7210 Amp**<br>`Nokia_7210_Amp.wal` | — | B<br><sub>provisional</sub> | Fully skinned | its video button opens nothing: the skin declares no video window (open B403) |
| **Nokia Mobile**<br>`Nokia_Xpress_Music.wal` | Saravanan K Sivanathan | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Nokia X6 Winamp Skin**<br>`Nokia_X6_Winamp_Skin_by_Brump3.com.wal` | The CyberWizard | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `display.back.line`, `player.main.eq`, `player.pl.time`, `player.pl.time.display`, `shade.web.normal` |
| **Nokia_5220**<br>`The_Nokia_5220_XpressMusic.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Non \| Step**<br>`Nonstep.wal` | ertmann\|CPH(Graphics) and Adam Boatright aka Da_Pipe(Xml and Maki) | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Nullsoft Winamp 2000 SP4**<br>`Nullsoft.Winamp.2000.SP4.Lite.wal` | Initial Graphics by Zsolt Vajda // Coding by Victor Brocaz // Modified by Gordon Freeman | B<br><sub>provisional</sub> | Fully skinned | 7 bitmap id(s) it references do not resolve, leaving a visible gap: `window.normal.left2`, `window.normal.middle2`, `window.plvis.display.bg`, `window.shade.region.bottom.left`, `window.shade.region.bottom.right`, `window.shade.region.top.left`…; 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Obscene.Helicopter.Extension.Part.3-SiNK**<br>`OHE3.wal` | Graphics by monaux (Karl Kwasny), scripting by nIRV (Mathieu Pellerin) | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **ocrana skin**<br>`ocrana.wal` | vorph | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Oddworld_Stranger's_Wrath_1**<br>`Oddworld_Stranger's_Wrath_1.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Offical Honda Element Skin**<br>`Official_Honda_Element_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Official Digizaar.com Skin**<br>`Digizaar.wal` | Naamloos | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Official Rolling Stones skin in support of their new Greatest Hits album "40 Licks" in stores now!**<br>`Official_Rolling_Stones_skin_.wal` | Trey Williams | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Official The Music Skin**<br>`The_Music_-_Official_Skin.wal` | Trey Williams | C<br><sub>provisional</sub> | Partly skinned | 8 bitmap id(s) it references do not resolve, leaving a visible gap: `player.eq.button.resize`, `video.playback.placeHolder`, `video.seekbar.placeholder.left`, `video.seekbar.placeholder.middle`, `video.seekbar.placeholder.right`, `wasabi.button.less`, `wasabi.button.less.pressed`, `wasabi.button.more`; no window of its own for the library: a NullPlayer window stands in |
| **Official Tom Petty and the Heartbreakers skin in support of their new album "The Last DJ" in stores now!**<br>`Official_Tom_Petty_Skin.wal` | Trey Williams | B<br><sub>provisional</sub> | Fully skinned | 12 bitmap id(s) it references do not resolve, leaving a visible gap: `player.eq.button.resize`, `player.winshade.highlight.center`, `player.winshade.highlight.left`, `player.winshade.highlight.right`, `video.playback.placeHolder`, `video.seekbar.placeholder.left`, `video.seekbar.placeholder.middle`, `video.seekbar.placeholder.right` and 4 more |
| **Official Trapt Skin**<br>`Official_Trapt_Skin.wal` | Gfx by Karl K. and scripted by Mathieu P. | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **Official Tristania Winamp5 Skin**<br>`Official_Tristania_Skin.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 11 bitmap id(s) it references do not resolve, leaving a visible gap: `player.button.Xfade`, `player.button.repeat`, `player.button.shuffle`, `wasabi.groupbox.bottom`, `wasabi.groupbox.bottom.left`, `wasabi.groupbox.bottom.right`…; 3 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Official_FreeAmp_Skin**<br>`Official_FreeAmp_Skin.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Official_Merv4_Skin**<br>`Official_Merv_4_Skin.wal` | John Bahmet | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `buttons.close`, `win.back`, `win.next`, `win.play`, `win.stop` |
| **Olimpiadas**<br>`Olimpiadas.wal` | Matt Adams aka Sunshine (GFX and CODING) | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **One piece winamp**<br>`One_piece_winamp.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **OnePieceLover Winamp Skin 2012**<br>`One_Piece_Lover.wal` | bayuhades(edited) | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Onyx**<br>`ONYX V2.wal` | Parisienne17 | C<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `compact.equalizer.led.off`; unimplemented MAKI: `oneqchanged` ×6; 1 error-severity load finding(s) |
| **Opal Redemption**<br>`OpalRedemption01.wal` | GFX: onemerci (Merci Oner) -- XML and Maki: ThePlague (Linus Brolin) | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Optimus Prime Transformer**<br>`Optimus_Prime_Transformer.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **OPulent Records Player**<br>`Opulent_Records_Player.wal` | quadhelix | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **OrbFace**<br>`OrbFace.wal` | Michael Kantor | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `studio.config.textbg` |
| **Orbis**<br>`Orbis.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Orbital**<br>`Orbital.wal` | Faris Wijaya [Graphic - xml code] | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `component.bg`, `wasabi.frame.basetexture` |
| **Orion**<br>`--Orion--.wal` | Aaron Spuler | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **Oven Winamp**<br>`Oven Winamp.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `player.normal.rscbg`, `wasabi.frame.basetexture` |
| **Overdrive**<br>`Overdrive.wal` | Ian Novack aka Spoonman aka Novispoon | C<br><sub>provisional</sub> | Partly skinned | Media Library opens in NullPlayer's plain chrome: the skin declares no frame of its own |
| **Overdrive 2**<br>`Overdrive_2.wal` | Ian Novack aka Spoonman aka Novispoon | C<br><sub>provisional</sub> | Partly skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.anim.volume`; no library window of its own; 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140); 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **OXAmp**<br>`OXAmp.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `player.normal.glass`, `wasabi.frame.basetexture` |
| **P!nk**<br>`Pink_Alicia_Moore.wal` | Fatz | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **PAD**<br>`PAD.wal` | Ryan F. (graphics), iPlayTheSpoons (scripting) | C<br><sub>provisional</sub> | Partly skinned | no window of its own for the library: a NullPlayer window stands in |
| **Padd Musical Interface Mk7**<br>`PADD_Musical_Inteface_mk7.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.main.shine` |
| **Palillo**<br>`Palillo.wal` | Matt Adams aka Sunshine (GFX and CODING) | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Pax**<br>`Pax_Amp.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **PDU**<br>`Get_Connected.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **PDU Blog**<br>`Blogz.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **PDU Fridge**<br>`ProjectDU_Fridge.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `main.window.left` |
| **Peanut ALPHA**<br>`Peanut.wal` | Darron Thornbury | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **Pebble**<br>`Pebble.wal` | Paul Vince | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **Pebble_England**<br>`Pebble_-_England.wal` | Paul Vince | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **phaze one small**<br>`Macosx.wal` | nkj | **C**<br><sub>provisional</sub> | Partly skinned | the Media Library opens in NullPlayer's plain chrome: the skin declares no frame of its own |
| **Pimeer**<br>`Technics_SA_-_712_X.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `about.pimeer`, `player.speakers.pied` |
| **Pimeer**<br>`Pimeer_v2-2_Ultime.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **PiOnNeR_AMP2**<br>`PionNer_AMP2.wal` | Marcelo Caetano Martins Muniz | B<br><sub>provisional</sub> | Fully skinned | 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; its synthesized playlist and library windows may draw plain (synthesis reads its standard frame as artwork-less) |
| **PiOnNeR_AMP2**<br>`Pioneer_Stereo_V1.wal` | Marcelo Caetano Martins Muniz | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **PiOnNeR_AMP3**<br>`PioNner3.wal` | Marcelo Caetano Martins Muniz | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Pixelated**<br>`Pixelated.wal` | UUL | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **PlastAmp**<br>`PlastAmp_2.wal` | Hamid Reza Mohammadi | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Point Blank**<br>`Point_Blank.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Pokemon DS**<br>`PokemonDS.wal` | SpaceKitty | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **PokerGods**<br>`PokerRoyalFlush.wal` | DeathBurn | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Powerade**<br>`Official_Powerade_Skin.wal` | Powerade | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **POWERPAK**<br>`PowerPak_007_Deluxe.wal` | E-Blackadder | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.button.close` |
| **Pro Stak II**<br>`ProStak_II.wal` | Butch Kratzer | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **Probe for Winamp 5**<br>`Probe_V5.wal` | Kinwashi and Lucas | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Project D.U.**<br>`More_Blogz.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Project D.U. #3**<br>`Project_DU_Television.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Project DU**<br>`Project_DU.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Proper Records**<br>`Proper_Records.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **ProStak 1**<br>`Pro_Stak_1A.wal` | The Kratz | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `eq.resize` |
| **ProtoType**<br>`ProtoType.wal` | Graphics, Design, Scripting(mostly) by ASTRI001 | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **Psonidelic Skin**<br>`Psonidelic.wal` | — | B<br><sub>provisional</sub> | Fully skinned | the archive ships no `player-winshade/` artwork, so the EQ and shade layouts lack their background and buttons (the skin's) |
| **Psonidelic Skin**<br>`Psonidelic_v2.wal` | gisleo | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Puma**<br>`PUMA_v1.08_Speed_Boot_Winamp5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Puma Skin**<br>`pumaSKIN.wal` | Puma DesignS | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **Punisher**<br>`The_Punisher_Winamp_5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Pure Inspired for Winamp**<br>`Pure Inspired.wal`<br><sub>also installed as `pure_inspired_for_winamp_by_marisa85_d35ix2r.wal`</sub> | Marisa85 | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `img/bt_caN.png` |
| **QuadCore**<br>`Quadcore.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.main.animbut` |
| **Quadelic**<br>`Quadelic.wal` | takanory | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Queen eLisabeth II**<br>`QL2.wal` | ANIEL SHRI | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `component.region.bottom.left`, `component.region.bottom.right`, `component.region.right`, `component.region.top.right`, `m06` |
| **Queensryche**<br>`Queensryche.wal` | Mark Miller | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Quinto**<br>`Quinto.wal` | peter_ka | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Qwest**<br>`Qwest_V2.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Qwest**<br>`Qwest_Amp.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `win.center` |
| **Radiance Corrected version**<br>`Radiance_Corrected_version.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `frame.bottom.left`, `frame.bottom.middle`, `frame.bottom.right` |
| **Radiate**<br>`RADIATE.wal` | JO | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `background.glass`, `background.glasslight` |
| **RadioHead**<br>`Radiohead__Hail_to_the_Thief.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Rammstein**<br>`Rammstein_Reise_Reise.wal` | La Matrake | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Rapid Bucuresti**<br>`Rapid_Bucuresti_2.0.wal` | CKQ | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `vid.bg`, `wasabi.frame.basetexture` |
| **Ray Skin**<br>`RayPlayer.wal` | Hareesh.N.Nampoothiri | C<br><sub>provisional</sub> | Partly skinned | Media Library opens in NullPlayer's plain chrome: the skin declares no frame of its own |
| **RazorEdge V1**<br>`RazorEdge_V1.wal` | Daniel B | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **Rectangular**<br>`Rectangular.wal` | Thomas Michgelsen | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Red Alert 2**<br>`CC_Red_Aler_2.wal` | 2good4you | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Red Button**<br>`RedButton.wal` | Paul Vince | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Red Hot Chili Peppers - By The Way**<br>`Official_Red_Hot_Winamp3_Skin.wal` | Taber Buhl | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **reflexion dark w**<br>`reflexion w.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `player.normal.volume_overlay`, `player.normal.volume_overlay2`, `wasabi.frame.basetexture` |
| **reflexion.mini**<br>`reflexion.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **Reliance**<br>`Vodafone_Zoozoo.wal` | Pradeep.K.R,Balasundarrao | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `sm.next`, `sm.pause`, `sm.play`, `sm.pre`, `sm.stop` |
| **Reliance Skin**<br>`Reliance_Mobile.wal` | Saravanan, Balasundarrao | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **REM**<br>`REM_-_Morning_Team_-.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Remote**<br>`remote.wal` | nkj | C<br><sub>provisional</sub> | Partly skinned | no window of its own for the library: a NullPlayer window stands in |
| **Remote**<br>`remote-2.wal` | nkj | **C**<br><sub>provisional</sub> | Partly skinned | the Media Library opens in NullPlayer's plain chrome: the skin declares no frame of its own |
| **Remote Sensing**<br>`RemoteSensing.wal` | Mike McCaffrey | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Resin**<br>`Resin.wal` | Skin Consortium | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Resurgence**<br>`Resurgence-2.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Resurgence**<br>`Resurgence.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **REVIVAL**<br>`REVIVAL_1.0F.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **REVIVAL-XMAS**<br>`REVIVAL1.0F.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **RNZ X666X**<br>`666HIM666.wal` | renz0r | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **RODE 3 Lite**<br>`RODE_3_Lite.wal` | ROBO Design | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `component.bottom-right-resize`, `studio.config.textbg` |
| **Roy Keane**<br>`Roy_Keane_Winamp3_Skin.wal` | Richard Lee | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **rpg-club Winamp skin**<br>`RpgClubRussia.wal` | Lucer | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Rumbling Amp**<br>`Rumbling_Amp.wal` | Alfredo Vega | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **S**<br>`SKooool.wal` | Mosharaf, Bonni, Raki | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **S3**<br>`S3.wal` | daniel sioneanu | B<br><sub>provisional</sub> | Fully skinned | 21 bitmap id(s) it references do not resolve, leaving a visible gap: `drawer.button.close.bg`, `player.button.repeat.bg`, `player.button.shuffle.bg`, `player.display.bg.center`, `player.display.bg.left`, `player.display.bg.right`, `player.display.center`, `player.display.left` and 13 more |
| **S7Reflex**<br>`S7Reflex.wal` | daniel sioneanu | B<br><sub>provisional</sub> | Fully skinned | 22 bitmap id(s) it references do not resolve, leaving a visible gap: `drawer.button.close.bg`, `player.button.repeat.bg`, `player.button.shuffle.bg`, `player.display.bg.center`, `player.display.bg.left`, `player.display.bg.right`…; 6 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **SA**<br>`SA-2.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **Sailor Moon Modern**<br>`Sailor_Moon_Modern_version_1.wal` | Tobias Bosma | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Samsung Corby Skin**<br>`Samsung_Corby.wal` | Ajay Muralidhar,Balasundarrao | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Samurai Champloo Modern**<br>`Samurai_Champloo_Modern.wal` | Design :-Luigihann - LuigiHann@hotmail.com Codemonkey :-Jones - mr.jonesy@gmail.com | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Saphire_Glass_m**<br>`Saphire_Glass_m.wal` | Heiko Mamsch | B<br><sub>provisional</sub> | Fully skinned | 15 bitmap id(s) it references do not resolve, leaving a visible gap: `player.display.songticker.bg.center`, `player.main.left.region`, `player.main.right.region`, `player.visualization.overlay`, `sd.region.top.left`, `sd.region.top.right`, `wasabi.frame.resizer`, `wasabi.frame.top.left.region` and 7 more |
| **Scattershot**<br>`Scattershot.wal` | flatmatt | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **SCCT DigitalWinamp**<br>`MerryChristmas.wal` | R.K and G.K | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **SCCT-it**<br>`3Sat_Digital_Winamp_1_1_1.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Scooby Doo 2**<br>`Scooby_Doo_2.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Scythe**<br>`_Scythe.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Sencillo**<br>`Sencillo_1_1.wal` | Jonny Rimes | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `player.seek.track.left`, `player.seek.track.middle`, `player.seek.track.right`, `wasabi.frame.basetexture` |
| **Sencillo**<br>`Sencillo.wal` | Jonny Rimes | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `player.seek.track.left`, `player.seek.track.middle`, `player.seek.track.right`, `wasabi.frame.basetexture` |
| **Sepultura**<br>`Sepultura_Dante_XXI.wal` | Coding and Grahpics: The Elusive Melon, Additional Graphics: King Shrimp | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `copy`, `player.Active`, `thingie`, `window` |
| **Sero.Overdose**<br>`SERO_OVERDOSE_Official_Skin.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Seta**<br>`Seta.wal` | skryingbreath | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **sh*t the fuu**<br>`Simpsons_Freeform_Skinfinal.wal` | UUL | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `wasabi.button.checkbox`, `wasabi.button.checkbox.pressed`, `wasabi.slider.horizontal.middle` |
| **sh\*t the fuu**<br>`Freeform_Simpsons_Skin.wal` | UUL | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `wasabi.button.checkbox`, `wasabi.button.checkbox.pressed`, `wasabi.slider.horizontal.middle` |
| **Shara Aryo**<br>`Shara_Aryo_in_Red.wal` | ferfer | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **SHARK**<br>`Shark_by_HH.wal` | Hammerhead | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Shark5**<br>`shark5final2.wal` | hammerhead | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Shark5 (Graphics Version)**<br>`shark5.wal` | hammerhead | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture`; 4 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Shield_AMP**<br>`Shield_Amp.wal` | team skinconsortium [graphic by Mike a.k.a WistonGFX coding by Faris Wijaya a.k.a Faris18787 and SLoB] | C<br><sub>provisional</sub> | Fully skinned | unimplemented MAKI: `setchecked` ×2, `setxmlparam` ×2; 6 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 3 error-severity load finding(s) |
| **Side Amp**<br>`sa.wal` | Graphics: Quadhelix - Ralph .:::. Coder: mc^^^^ - Michael McBriar | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Side Amp**<br>`Scare-amp.wal` | Graphics: Quadhelix - Ralph .:::. Coders: mc^^^^ - Michael McBriar and Plague - Linus Brolin | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **SILVERSKIN3**<br>`Silverskin_3.wal` | Martin P. alias bigHIPPIE | B<br><sub>provisional</sub> | Fully skinned | open: B282 (frame titles wider than their windows lose both ends) |
| **Simple**<br>`Simple.wal` | R. Peter Clark | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `studio.basetexture`, `component.basetexture` |
| **Simple Amp**<br>`Simple_Amp_.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **SimpleSkin**<br>`SimpleSkin_1.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 9 bitmap id(s) it references do not resolve, leaving a visible gap: `player.led.off`, `player.led.off0`, `wasabi.button.bg.title`, `wasabi.titlebar.center.active`, `wasabi.titlebar.center.inactive`, `wasabi.titlebar.left.active`, `wasabi.titlebar.left.inactive`, `wasabi.titlebar.right.active` and 1 more |
| **Simplistic Vision**<br>`Simplistic_Vision_2.wal` | DrunkenMaster | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Sing it, Kitty**<br>`SingItKitty.wal` | SpaceKitty | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Sirius skin**<br>`Angel_skin.wal` | Mortimer | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Six Feet Under**<br>`Official_Six_Feet_Under_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Six Feet Under**<br>`Red_Pearl.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Six Flags**<br>`Official_Six_Flags_Theme_Parks_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Six Miller FTF (Forget The Face)**<br>`Six_Miller_FTF.wal` | Ben Tjibe | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Skimple**<br>`Skimple.wal` | Flame Reaper "aka" Henry Stratton | C<br><sub>provisional</sub> | Partly skinned | Media Library opens in NullPlayer's plain chrome: the skin declares no frame of its own; open B439 (spectrum sits left of its well, as the skin's XML places it) |
| **Skinit.net**<br>`Skinit-net.wal` | R. Peter Clark | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Sleeky Xtra**<br>`SleekyXtra.wal` | Hareesh.N.Nampoothiri | C<br><sub>provisional</sub> | Partly skinned | Media Library opens in NullPlayer's plain chrome: the skin declares no frame of its own |
| **Slim**<br>`Slim.wal` | Graphics, Design, Scripting by ASTRI001 | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **SLIMLINE**<br>`Slimline_XP_final.wal` | E-Blackadder | C<br><sub>provisional</sub> | Partly skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.button.close`; no window of its own for the library or the playlist: a NullPlayer window stands in |
| **Slither**<br>`The_Official_Slither_Winamp5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Smallville**<br>`Official_Smallville_Winamp5_Skin.wal` | Petrol Designs, Kinwashi and Lucas | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Smallville**<br>`Official_Smallville_Skin_-_The_WB.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Smallville Digital Album**<br>`Smallville_Digital_Album.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Smallville Metropolis**<br>`Smallville_Metropolis_Winamp3_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Smokin' Aces**<br>`Smokin_Aces.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Snapxynith**<br>`Tuneup_v1.wal` | — | B<br><sub>provisional</sub> | Fully skinned | the skin declares no Media Library frame, so it opens in NullPlayer's own chrome |
| **Snoe Globe X-Mas Skin**<br>`Magic_Snow_Globe.wal` | Martin Poehlmann, Michael Winston, Ralph Barber | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Software**<br>`Software.wal` | Chimpzilla | B<br><sub>provisional</sub> | Fully skinned | open: B389 (the volume bar draws past the art that should clip it) |
| **Sonara**<br>`-Sonara-.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Sonic Skin**<br>`Sonic_Skin.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Sony**<br>`Sony_Walkman.wal` | Petrol Designs | C<br><sub>provisional</sub> | Partly skinned | no library, playlist window of its own; 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140); 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Sony Media Tower**<br>`Sony_Media_Tower.wal` | Stemybacsi | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `studio.blue` |
| **Sony Mobile**<br>`Sony_Ericsson__W595_Sharing_My_Music.wal` | Saravanan K Sivanathan | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Sony MPFX3-WA5**<br>`Sony_MPFX3-WA5x.wal` | Douglas Halamay | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Sony S2 Sports Audio MZ-S2**<br>`Sony_S2_Sports_Audio.wal` | Amit Verma | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **Sony STR VA 555**<br>`3IO.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Sony Walkman Skin**<br>`SONY__WALKMAN.wal` | Saravanan, Balasundarrao | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Sony XPlod Skin**<br>`XPlod.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Soundwave**<br>`Soundwave.wal` | Aaron Spuler | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Space Invaders**<br>`Space_Invaders_by_flatmatt_1.wal` | flatmatt | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Special Forces**<br>`XForces.wal` | quadhelix | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `eq.back` |
| **SpecialClock**<br>`Special_Clock.wal` | carlosp.designs | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **Spiderman Skin**<br>`Spiderman_by_CarlosP.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **SpoonoAmp Modern**<br>`SpoonoAmp_Modern.wal` | Dan Wenner | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Sreet Fighter**<br>`StreetFighterModern.wal` | Fenixxxas (aka Laurynas Maciulis) | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Sreet Fighter v2**<br>`Street_Fighter_Modern_v2.wal` | Fenixxxas (aka Laurynas Maciulis) | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Star Trek LCARS AMP PADD II**<br>`StarTrek_LCARS_AMP_PADD_II.wal` | Jason Chiu | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `player.seek.slider`, `wasabi.frame.basetexture` |
| **Star Wars Player**<br>`Star_Wars_Player.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Stargate:Winamp - SG1 Edition**<br>`Stargate_Winamp_-_SG1_edition.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Starsky and Hutch**<br>`Starsky_and_Hutch.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Steamed**<br>`Steamed up 1.0.wal` | Corwin of Amber | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **SteauaFC**<br>`steaua_bururesti_skin_By_dr_cbg.wal` | Ionut Aanei | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Studiosus**<br>`Studiosus.wal` | Thomas Michgelsen | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Study Skinning**<br>`Study Skinning.wal` | Ariszló | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Stylize - The Upgrade**<br>`Stylize.wal` | matt_69 (GFX and CODING) | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `wasabi.frame.basetexture` |
| **Styx**<br>`Styx.wal` | — | C<br><sub>provisional</sub> | Fully skinned | unimplemented MAKI: `getmode` ×2, `setchecked` ×12; 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 7 error-severity load finding(s) |
| **Suicide Commando Winamp 5 Skin**<br>`--Suicide_Commando_1--.wal` | Norbert M. Sziraki | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture` |
| **Sungmin Ping2**<br>`minnieeee.wal` | pukpik_min Thai | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **sx**<br>`sx.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **sx.pink**<br>`sx-2.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **sxncsucks.com**<br>`sucksdotcomwinamp.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Symplicipod**<br>`Symplicipod.wal` | Sharkwork | B<br><sub>provisional</sub> | Fully skinned | 4 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Sync**<br>`The_Official_Ford_Sync_Winamp5_Skin.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **T-800**<br>`Bio-Nid.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **T-800**<br>`Rika.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **T-800**<br>`T800.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.main.pause`; 1 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `player.over` |
| **t-shirts fc Vaslui**<br>`TShirts_Fc_Vaslui_1.wal` | Zonny | B<br><sub>provisional</sub> | Fully skinned | 9 bitmap id(s) it references do not resolve, leaving a visible gap: `normal.240card`, `normal.240oncard`, `normal.31card`, `normal.31oncard`, `normal.7card`, `normal.7oncard`, `normal.eq.aircel`, `normal.eq.dailTunes` and 1 more |
| **t.a.l. 96**<br>`TKAL96.wal` | sinan bahadir "aka" watercolours | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `common.overimage`, `wasabi.frame.basetexture` |
| **t.a.l. skin**<br>`TAL_96.wal` | sinan bahadir "aka" watercolours | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **T3-Amp**<br>`T3-Amp.wal` | Rain Pikner | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **T_624**<br>`T_624.wal` | Aniel Shri | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **TANKCSApDA by Jo Imre**<br>`TANKCSApDA.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.normal.button.small` |
| **Te iubesc**<br>`True_Blood.wal` | Ankha | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Te iubesc**<br>`Blood.wal` | Ankha | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Te iubesc**<br>`Butterfly.wal` | Ankha | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Te iubesc**<br>`Monochrome_Factor.wal` | Ankha | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Te iubesc**<br>`Sisters.wal` | Ankha | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Te iubesc**<br>`BlackRose.wal` | Ankha | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Te iubesc**<br>`Darkside.wal` | Ankha | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Te iubesc**<br>`Two_sides.wal` | Ankha | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **team mclaren mercedes 06**<br>`team_mclaren_mercedes_mp4-21.wal` | sinan bahadir "aka" watercolours | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **team mclaren mercedes 06**<br>`team_mclaren_mercedes_mp4-22.wal` | sinan bahadir "aka" watercolours | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `player.normal.cbutton.pause.overlay`, `wasabi.frame.basetexture` |
| **team mclaren mercedes 08**<br>`team_mclaren_mercedes_mp423.wal` | sinan bahadir "aka" watercolours | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `player.normal.cbutton.pause.overlay`, `wasabi.frame.basetexture` |
| **Technicalium**<br>`Technicalium.wal` | jsosic | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **technolize**<br>`technolizewinamp.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `component.region.bottom.left`, `component.region.bottom.right`, `component.region.top.left`, `component.region.top.right`, `wasabi.frame.basetexture` |
| **Tekken Lili Winamp Skin**<br>`Tekken Lili.wal` | Maxim Cryseria | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.volpanel` |
| **Tendency**<br>`Prakrit.wal` | Rohan Prabhu / Tritium SkinZ | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **Terminus 3000**<br>`Terminus3000.wal` | flatmatt | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **TESSA WINAMP5 SKIN**<br>`Tessa_Winamp5_Skin.wal` | LEGION | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Test**<br>`machina.wal` | Jason Lange and Frank Schoenmaker aka vrank | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `component.resize` |
| **Tewnz**<br>`Tewnz_2.0.wal` | Corwin of Amber | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Tewnz**<br>`Tewnz.wal` | Corwin of Amber | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **Thanog**<br>`Thanog_.wal` | Antonio Manna | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **The Ben Tjibe Skin**<br>`The_Official_Ben_Tjibe_Skin_v1.wal` | Ben Tjibe | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **The Cap**<br>`Capped.wal` | QuadHelix , Leechbite Technology | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `equalizer.bar`, `equalizer.bar.preamp`, `player.main.eqbutton` |
| **The Chronicles of Riddick**<br>`The_Chronicles_of_Riddick.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **The Control Panel**<br>`The_Control_Panel.wal` | alex kronish | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **The Crow**<br>`The_Crow__v1.wal` | ivan gomez | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **The Duk Side**<br>`The_Duk_Side_V3.wal` | Mr Jones | C<br><sub>provisional</sub> | Partly skinned | no window of its own for the library: a NullPlayer window stands in |
| **The Dukes of Hazzard**<br>`The_Dukes_of_Hazzard.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **The Flames of Hell**<br>`The_Flames_of_Hell_-_Rurouni_Kenshin.wal` | SSJ Heero | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **The Hives**<br>`Official_The_Hives_Skin.wal` | Taber Buhl | C<br><sub>provisional</sub> | Partly skinned | no window of its own for the library: a NullPlayer window stands in |
| **The Hobbit**<br>`The_Hobbit.wal` | PriestGX | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **The Metallica Skin**<br>`Metallica_Metallica.wal` | Steve Oliveira | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **The Official Private Law Unlam Winamp5 Skin**<br>`The_Official_Private_Law_Unlam_0.1_Alpha.wal` | Muhammad Rizali Rizqan for http://catatansangpurna.blogspot.com | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `button`, `songcover` |
| **The Sims**<br>`The_Official_Sims_Online_Skin.wal` | Andy, Adil, Lucas, David S, and jivemouth for Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | its playlist shows neither the playing track nor a selection highlighted (open B373) |
| **The Unauthorized Matrix SKin**<br>`The_Unauthorized_Matrix_Skin.wal` | Jason aka Wes Janson | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **The Wb**<br>`The_WB_Winamp_5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **The WolfPack Clan**<br>`The_WolfPack_Clan.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 6 bitmap id(s) it references do not resolve, leaving a visible gap: `player.eq.button.resize`, `player.toggler.crossfade.pressed`, `wasabi.button.less`, `wasabi.button.less.pressed`, `wasabi.button.more`, `wasabi.button.more.pressed` |
| **The XP Style WinaMP3 Player**<br>`The_XP_Style_WinaMP3_Player.wal` | Yoann Brosseau | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **The_Amityville_Horror_Winamp_Skin**<br>`The_Amityville_Horror_Winamp_Skin.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Times Square Live**<br>`Live_Times_Square.wal` | Dominique Klevinghaus | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **TiMoKi.NET**<br>`TiMoKi_NET.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 23 bitmap id(s) it references do not resolve, leaving a visible gap: `component.system.resize`, `player.eq.button.resize`, `player.eq.slider.horizontal.bar`, `player.eq.slider.horizontal.bar.label`, `player.eq.winshade.bg`, `player.eq.winshade.placeHolder`, `player.winshade.highlight.center`, `player.winshade.highlight.left` and 15 more |
| **TMNT**<br>`Teenage_Mutant_Ninja_Turtles.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Tom**<br>`TomK.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | 3 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Tomb Raider: Angel of Darkness**<br>`The_Official_Lara_Croft_Winamp_Skin.wal` | Core Design Ltd. | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Torque**<br>`Official_Torque_Winamp5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **TOX Milla Maxwell**<br>`TOX Milla.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.logo` |
| **Trance Critic v2.0**<br>`Trance_Critic_v2_0.wal` | Tim Bardenhagen | C<br><sub>provisional</sub> | Fully skinned | its frame's opaque plate covers framed windows' content, leaving an 11 px band (B464); 2 bitmap id(s) it references do not resolve, leaving a visible gap: `component.top.right.glass`, `vis.backlayer.blue` |
| **Triton**<br>`Triton.wal` | Vica. | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **TRON___Legacy**<br>`TRON___Legacy.wal` | — | C<br><sub>provisional</sub> | Partly skinned | no library window of its own; 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140); 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Troy**<br>`Troy.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Turner Classic Movies**<br>`Turner_Classic_Movies_Winamp5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Tutorial Simple Skin**<br>`Mutant1.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Tutorial Simple Skin by Jo Imre**<br>`Simple_skin_V2.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Type-A**<br>`Type-A.wal` | Skryingbreath | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `eq.glare`, `thinger.normal.display.glass`, `wasabi.frame.basetexture` |
| **uDesignIT**<br>`uDesignIT.wal` | ROBO Design | C<br><sub>provisional</sub> | Partly skinned | a composite player of 21 containers placed by `default_x`/`default_y`, which the tiler ignores, so the main window opens as ~20 separate windows: open B367; the playlist is empty (B372, `relatx=40` places the list outside the window) |
| **Ujola Cat**<br>`Ujola Cat.wal` | sambaneko | B<br><sub>provisional</sub> | Fully skinned | 7 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Ultra BM**<br>`UltraBM_v1.wal` | Travis Williams | B<br><sub>provisional</sub> | Fully skinned | Library and Playlist open at 275x154, the skin's frame default |
| **Underscore 3.0**<br>`Underscore.wal` | David Serrano | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Underworld Evolution**<br>`Underworld_Evolution.wal` | Dutchtilt Desktops | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Urban Terror 2.6**<br>`Urban_Terror_2_6.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 6 bitmap id(s) it references do not resolve, leaving a visible gap: `player.eq.button.resize`, `player.toggler.crossfade.pressed`, `wasabi.button.less`, `wasabi.button.less.pressed`, `wasabi.button.more`, `wasabi.button.more.pressed` |
| **Van Helsing**<br>`Van_Helsing.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `main.window.left` |
| **VANDREAD WINAMP5 SKIN**<br>`VANDREAD_WINAMP5_SKIN.wal` | LEGION | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Venom**<br>`venom.wal` | quadhelix | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Venom**<br>`44_Magnum.wal` | quadhelix | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Venus**<br>`Venus.wal` | R. Peter Clark | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Vex**<br>`Vex.wal` | Jason and Naamloos | B<br><sub>provisional</sub> | Fully skinned | no close control but the centre EXIT (B374, closed as the skin's) |
| **Vice City**<br>`Official_GTA_Vice_City_skin.wal` | Futaba Hayashi, Jerry Luna, Jeff Williams | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Vindow**<br>`Vindow3.wal` | Paul Vince | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Virginia Tech Skin**<br>`Virginia_Tech_Winamp3_Skin.wal` | FrisbeeMonkey | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Vision**<br>`Vision.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Vision For Winamp**<br>`Vision_V1.wal` | Michael Landstreet Jr | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `wasabi.frame.basetexture` |
| **VISION WINAMP5 SKIN**<br>`VISION_WINAMP_SKIN_.wal` | LEGION | B<br><sub>provisional</sub> | Fully skinned | open B431 (Playlist Editor rows draw too big for the list) |
| **Vista Green**<br>`Vista_Green.wal` | Slynko Vitaly | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `player/about.png`, `seeker.bg.vertical.right` |
| **Vista Player**<br>`Vista_Player.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.main.ML` |
| **Vocaloid Love is War: Hatsune Miku x Megurine Luka**<br>`Hatsune Miku x Megurine Luka.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Vocaloid Miku Hatsune 2.0 Append**<br>`WinAMPloid_01_Append_1.wal` | MonkeydanceGuy | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `statusunder`, `wasabi.frame.basetexture` |
| **WalkHard**<br>`Walk_Hard_Winamp5_Skin.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Warp**<br>`warp.wal` | QuadHelix (Graphx and Design) and Leechbite (Coding) | B<br><sub>provisional</sub> | Fully skinned | open: B375 (timer holds ~30 ms; VU volatility) |
| **wasabi.player base skin**<br>`wasabi_player_skin.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `about.bg`, `player.status.play`, `wasabi.frame.basetexture` |
| **Washed**<br>`Washed.wal` | Isaac Eckert (IceMan) | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Watchmen**<br>`Watchmen_-_Modern.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `fuck` |
| **Wax-Skin**<br>`Smoking.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **WeeAmp**<br>`WeeAmp_2.wal` | Andreas Svensson and James Hewitt | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **west mclaren mercedes 04**<br>`team_mclaren_mercedes_2004.wal` | sinan bahadir "aka" watercolours | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **west mclaren mercedes 05**<br>`team_mclaren_mercedes_mp4-20.wal` | sinan bahadir "aka" watercolours | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **west mclaren mercedes skin**<br>`team_mclaren_mercedes_mp4-17d.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **What A Girl Wants**<br>`What_a_Girl_Wants.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **White Noise**<br>`White_Noise.wal` | Petrol Designs | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `main.window.left` |
| **Wiimote**<br>`Wiimote.wal` | SpaceKitty | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Wilfrid Laurier University**<br>`WLU.wal` | Kickstand McGee | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Winamp 2006**<br>`Winamp-2006.wal` | — | B<br><sub>provisional</sub> | Fully skinned | the skin declares no Media Library frame, so it opens in NullPlayer's own chrome; its MSPP settings page is for a Windows add-on that cannot run here |
| **Winamp Azenis 2**<br>`WinampAzenis2.wal` | — | B<br><sub>provisional</sub> | Player skinned | 10 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Winamp Holiday Skin, 2005**<br>`Winamp_Modern_Holiday_-_2005.wal` | Taber Buhl | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Winamp iPhone**<br>`IPHONE_THEME_ALBUM_ART_SUPPORT.wal` | Richard Alfaro | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Winamp Media Tower**<br>`Winamp_Media_Tower_v11.wal` | Tibi Ardelean | B<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `component.basetexture`, `pl.button.bg`, `pl.button.small` |
| **Winamp Media Tower**<br>`Winamp_Media_Tower.wal` | Tibi Ardelean | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **Winamp Modern Single GUI**<br>`Winamp_Single_GUI.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Winamp Notif**<br>`GhostSlate.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Winamp Portrait**<br>`Winamp_Portrait__WMP12_1.wal` | Hiveminds | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **Winamp Zune**<br>`Winamp_Zune.wal` | Richard Alfaro | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **WinaMP3**<br>`Arion.wal` | LittleJOE | B<br><sub>provisional</sub> | Fully skinned | 7 bitmap id(s) it references do not resolve, leaving a visible gap: `component.region.bottom`, `component.region.top`, `player.TH`, `player.shade.EQStakl`, `player.songinfo.none`, `text.vis`, `wasabi.frame.basetexture` |
| **Winamp3 Base Skin**<br>`Winamp 3.0 Default.wal` | — | C<br><sub>provisional</sub> | Partly skinned | no library window of its own; 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140); 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Winamp3 Base Skin**<br>`Winamp3_Default_Skin.wal` | — | C<br><sub>provisional</sub> | Partly skinned | the Media Library opens in NullPlayer's plain chrome (the skin declares no frame of its own); 8 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.button.appmenu`, `wasabi.button.appmenu.pressed`, `wasabi.button.close`, `wasabi.button.close.pressed`, `wasabi.button.exit`, `wasabi.button.exit.pressed`, `wasabi.button.label.arrow.left`, `wasabi.button.label.arrow.right` |
| **Winamp5 Base Skin**<br>`nullsoft_media_player_10_forked_by_hb860-d7h03zd.wal` | — | C<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `component.bottom.left.corner`, `component.bottom.right.corner`, `component.bottom.stretch`, `component.top.right.corner`; unimplemented MAKI: `getmode` ×2, `onleftbuttondown` ×2; 3 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 2 error-severity load finding(s) |
| **Winamp5 Base Skin**<br>`winampmodern566.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 10 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Winamp5 Simple Demo Skin**<br>`Simple_Skin_V5.wal` | Christophe Thibault wa5 version by Mr Jones | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Winampple**<br>`Winampple_1_1.wal` | beamcompass | B<br><sub>provisional</sub> | Fully skinned | 2 bitmap id(s) it references do not resolve, leaving a visible gap: `bg.ml.right`, `bg.vis.right` |
| **Winbar**<br>`Blue_and_Silver_Pro.wal` | Zephyris | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Windpws Media Player 11**<br>`Vista.wal` | X - Man | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `seeker.bg.vertical.right` |
| **Windpws Media Player 11**<br>`WMP11.wal` | X - Man | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `seeker.bg.vertical.right` |
| **Windpws Media Player 11 BlueVU**<br>`WMP11-BlueVU.wal` | X - Man | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `seeker.bg.vertical.right`; 5 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click; 3 error-severity load finding(s) |
| **WinPlain All Res**<br>`WinPlain_ALLRES_V1_4b.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **WinPlain All Res**<br>`Radio_Flash_Online.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **WINyaMP3**<br>`WINyaMP3.wal` | ROBO Design | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Witchblade**<br>`Official_Witchblade_TV_Series_Skin.wal` | Petrol Designs, Kinwashi and Lucas | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **WM_Player**<br>`WM_Player.wal` | — | B<br><sub>provisional</sub> | Fully skinned | open B446 (each content window has a paired frame window; not yet seen on screen); 5 bitmap id(s) it references do not resolve, leaving a visible gap: `frame.bottom.left`, `frame.bottom.middle`, `frame.bottom.right`, `player.main.extras.cd.progressBar.left`, `player.main.extras.textbox.left` |
| **WMP Aero**<br>`WMP_Aero.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 5 bitmap id(s) it references do not resolve, leaving a visible gap: `frame.bottom.left`, `frame.bottom.middle`, `frame.bottom.right`, `player.main.extras.cd.progressBar.left`, `player.main.extras.textbox.left` |
| **WooHooFer**<br>`METASKINS-WooHoo-FER.wal` | VAG design (GFX) | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **WoopieAMP**<br>`WoopieAMP3.wal` | Brian M. Sperlongano, '02 EE | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `right-up` |
| **World Cup 2010**<br>`World_Cup_2010.wal` | MoC_X | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Wrigley's Chewing Amp**<br>`ChewingAmp.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **WTM**<br>`WTM.wal` | lypnjtu | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **wTunes**<br>`wTunes.wal` | capnkyle | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `window.region.topright`; 7 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Wurlitzer One More Time**<br>`W%C3%83%C2%BCrlitzer_V3_1.wal` | Corwin of Amber | B<br><sub>provisional</sub> | Fully skinned | open: B392 (high CPU while playing) |
| **Wurlitzer One More Time**<br>`Wurlitzer_v2.wal` | Corwin of Amber | C<br><sub>provisional</sub> | Fully skinned | 3 bitmap id(s) it references do not resolve, leaving a visible gap: `component.MenuButton`, `component.MenuButton.overlay`, `player.flash-right`; open: B422 (its skin frame draws short on NullPlayer's own windows) |
| **X Sphere**<br>`X_Sphere.wal` | SBSM | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **X-Slant**<br>`X-Slant.wal` | GFX: Kriptoner -- XML and Maki: Plague (Linus Brolin) | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **X-Theme**<br>`X-Theme.wal` | Eps | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **Xbox Amp**<br>`Xbox_Amp.wal` | Alex Kronish | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **XENERGY**<br>`XENERGY1.wal` | daniel sioneanu | B<br><sub>provisional</sub> | Fully skinned | 16 bitmap id(s) it references do not resolve, leaving a visible gap: `player.button.repeat.bg`, `player.button.shuffle.bg`, `player.display.bg.center`, `player.display.bg.left`, `player.display.bg.right`, `player.display.center`…; 5 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **Xenon**<br>`Xenon.wal` | Naos | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **XMP**<br>`XMP.wal` | Quadhelix | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Xploit**<br>`Xploit_2.wal` | The Elusive Melon | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.frame.basetexture` |
| **Y.S.T**<br>`YST.wal` | lypnjtu | B<br><sub>provisional</sub> | Fully skinned | open B446 (each content window has a paired frame window; not yet seen on screen) |
| **YANNI, English Ver. by ramin mousavi (raminmousavi.com )**<br>`YANNI_English_version.wal` | Ramin Mousavi | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **yaXay 3**<br>`Yaxay3.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `wasabi.button.resize` |
| **Yo-Yo-Boy**<br>`The_Official_YoYoBoy_Skin.wal` | Ben Tjibe | B<br><sub>provisional</sub> | Player skinned | nothing outstanding that a headless pass can see |
| **ZDL-AMP SIX-TRACK REEL-TO-REEL WA-3**<br>`ZDL_Reel-To-Reel_Analog_Tape_Machine.wal` | Mike Zee | B<br><sub>provisional</sub> | Fully skinned | 4 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **ZDL-ANALOG HOME STUDIO for WINAMP-5**<br>`ReelToReel_Machine__Sony_Edition.wal` | Mike Zee | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **ZDL-ANALOG HOME STUDIO for WINAMP-5**<br>`ZDL_ANALOG_STUDIO-5_for_winamp-5.wal` | Mike Zee | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **ZDL-AUDIOPHILE Stereo System for WINAMP-5**<br>`ZDL-AUDIOPHILE_Stereo-System_5-Plus.wal` | Mike Zee | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **ZDL-GOLD-STACK STEREO SYSTEM for Winamp-5**<br>`ZDL_GOLD_STACK.wal` | Mike Zee | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **ZDL-GOLD-STACK STEREO SYSTEM for Winamp-5**<br>`ZDL_Gold_Stack_mk-II_REEL-TO-REEL.wal` | Mike Zee aka Dr. ZEE | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Zectichoplayer**<br>`zechitoplayer.wal` | asseman and hammerhead | B<br><sub>provisional</sub> | Fully skinned | in vis mode its alpha=1 noclick overlay covers the volume slider (B371, the skin's) |
| **Zelda**<br>`Zelda3-Links-Tools-V1-02.wal` | — | B<br><sub>provisional</sub> | Fully skinned | nothing outstanding that a headless pass can see |
| **Zelda**<br>`Zelda3-Ocarina-V1-02.wal` | — | B<br><sub>provisional</sub> | Fully skinned | 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.songticker.background` |
| **ZWAN**<br>`Official_Zwan_Skin.wal` | Demian Trimble | C<br><sub>provisional</sub> | Partly skinned | no window of its own for the library or the playlist: a NullPlayer window stands in |
| **zygote**<br>`Zygote.wal` | Michael S. , Mathieu P. | B<br><sub>provisional</sub> | Fully skinned | 4 bitmap id(s) it references do not resolve, leaving a visible gap: `studio.seekbar.left`, `studio.seekbar.middle`, `studio.seekbar.right`, `wasabi.frame.basetexture`; 8 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click |
| **\| Candeo \|**<br>`cPro_Candeo.wal` | Andreas Nilsson | B<br><sub>provisional</sub> | Fully skinned | open B396 (the window census hangs at the Windows-menu toggle) |

## Known issues that affect every skin

These are open items in the skin engine, not faults in any particular skin. A skin graded B can still
show any of them.

**Windows and borders**

- NullPlayer's own windows — the library and the video pane — can only be dragged by their title
  strip, not by their body, the way a skin's own windows can (B60).
- A skin whose window border is built by a second, overlapping window can load its inner layout before
  that border has a client area to sit in, leaving the border half-built until something else redraws
  it. Seen on Defix's detached visualizer (B71).

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
- One arithmetic fault inside a script — a division by zero, which Winamp tolerates — abandons the
  rest of that handler here. Seen on Shield_Amp's song ticker (B65).
- A group sized from a picture rather than a text label collapses to nothing and takes its contents
  with it. This is why the stock Winamp Modern skin's title-bar menus do not open (B79).
- The Options entry in a skin's menu bar opens a thin NullPlayer menu rather than the full set of
  player options (B84).

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
   that pass, except for skins from corpus intake #6 on, graded from the intake's ledger and backlog
   rows (above).
3. Every rendered layout was measured for how much of its canvas it actually paints — which is what
   found the three empty main windows, and what distinguishes them from the irregular silhouettes
   (Bio-Nid 22%, HeadAMP 30%, Ujola Cat 34%) that are meant to look like that.
4. The 36 archives shipping the author's own `screenshot.png` had it compared against our render,
   asking only whether it is recognisably the same skin and ignoring playback state, track text and
   which windows are open. Nine were flagged; five were the author shipping a cropped or shade-mode
   promo shot, one was a fault in the pairing, and three were real.
5. The seven live letters come from `/wal-skin-report` sessions driven by a person and are unchanged.

Per-skin engineering notes live in `skills/winamp-modern-skin-guide/skins/` — one file per skin, the
77 graded before 2026-10-17 plus Onyx (the other seven 2026-10-17 additions have none yet); the index is `skills/winamp-modern-skin-guide/skins.md`.
