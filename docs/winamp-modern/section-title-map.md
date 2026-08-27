# Winamp Modern section-title map

Historical handoffs cite the subsystem guide by section title. Every title below remains verbatim and resolves to its current focused reference.

| Section title | Now in |
|---|---|
| VFS mounts | [reference/loading.md](../../skills/winamp-modern-skin-guide/reference/loading.md) |
| Initialization passes | [reference/loading.md](../../skills/winamp-modern-skin-guide/reference/loading.md) |
| Retained graph and coordinates | [reference/loading.md](../../skills/winamp-modern-skin-guide/reference/loading.md) |
| The protective window minimum | [reference/loading.md](../../skills/winamp-modern-skin-guide/reference/loading.md) |
| The two y-origin conventions (source of a whole class of bugs) | [reference/loading.md](../../skills/winamp-modern-skin-guide/reference/loading.md) |
| Region clipping | [reference/rendering/hit-testing.md](../../skills/winamp-modern-skin-guide/reference/rendering/hit-testing.md) |
| Hit testing: who owns a point | [reference/rendering/hit-testing.md](../../skills/winamp-modern-skin-guide/reference/rendering/hit-testing.md) |
| Dragging the window | [reference/rendering/hit-testing.md](../../skills/winamp-modern-skin-guide/reference/rendering/hit-testing.md) |
| `<vis mode>` — the skin says whether it wants a visualization at all | [reference/rendering/vis.md](../../skills/winamp-modern-skin-guide/reference/rendering/vis.md) |
| The oscilloscope reads PCM, and the host has always had it (B51) | [reference/rendering/vis.md](../../skills/winamp-modern-skin-guide/reference/rendering/vis.md) |
| The visualization has a clock of its own, because the audio's rate is not a frame rate (B51) | [reference/performance.md](../../skills/winamp-modern-skin-guide/reference/performance.md) |
| NullPlayer's own analyzers (Cava, vis_classic) in a skin's `<vis>` box, and **where the gain is tuned** (B53) | [reference/rendering/vis.md](../../skills/winamp-modern-skin-guide/reference/rendering/vis.md) |
| `<Wasabi:Frame>` — the splitter that builds its own children | [reference/rendering/frame-splitter.md](../../skills/winamp-modern-skin-guide/reference/rendering/frame-splitter.md) |
| Text width is a layout input, not just a drawing detail | [reference/rendering/text.md](../../skills/winamp-modern-skin-guide/reference/rendering/text.md) |
| How big the font is, and which one | [reference/rendering/text.md](../../skills/winamp-modern-skin-guide/reference/rendering/text.md) |
| A bitmap font's `file=` is an id **or** a path | [reference/rendering/text.md](../../skills/winamp-modern-skin-guide/reference/rendering/text.md) |
| What a `<text>` shows | [reference/rendering/text.md](../../skills/winamp-modern-skin-guide/reference/rendering/text.md) |
| A `cfgattrib` control has no `action` — the binding *is* what it does | [reference/rendering.md](../../skills/winamp-modern-skin-guide/reference/rendering.md) |
| Some `cfgattrib` values are the **host's**, not the skin's — and a bound control keeps no state of its own | [reference/rendering.md](../../skills/winamp-modern-skin-guide/reference/rendering.md) |
| `onActivate` — how a skin shows that a toggle is on | [reference/rendering.md](../../skills/winamp-modern-skin-guide/reference/rendering.md) |
| `<AlbumArt>` needs a host that actually has the cover | [reference/rendering.md](../../skills/winamp-modern-skin-guide/reference/rendering.md) |
| `alpha` belongs to the object, not to one kind of drawing | [reference/rendering.md](../../skills/winamp-modern-skin-guide/reference/rendering.md) |
| An image param is a *load*, and a failed load changes nothing | [reference/rendering.md](../../skills/winamp-modern-skin-guide/reference/rendering.md) |
| Layer fill modes | [reference/rendering.md](../../skills/winamp-modern-skin-guide/reference/rendering.md) |
| `<ProgressGrid>` — the bar's *filled* part | [reference/rendering.md](../../skills/winamp-modern-skin-guide/reference/rendering.md) |
| A skin's own right-click menus | [reference/rendering.md](../../skills/winamp-modern-skin-guide/reference/rendering.md) |
| The three action attributes (Phase 36) | [reference/rendering/hit-testing.md](../../skills/winamp-modern-skin-guide/reference/rendering/hit-testing.md) |
| A resolved colour is not yet a *readable* one (B48) | [reference/rendering/colour.md](../../skills/winamp-modern-skin-guide/reference/rendering/colour.md) |
| Colour themes (`gammaset` / `gammagroup`) | [reference/rendering/colour.md](../../skills/winamp-modern-skin-guide/reference/rendering/colour.md) |
| Colour theme screen is empty / will not switch | [reference/rendering/colour.md](../../skills/winamp-modern-skin-guide/reference/rendering/colour.md) §*The picker* |
| Animated layers are played as a range | [reference/rendering.md](../../skills/winamp-modern-skin-guide/reference/rendering.md) |
| The frame budget: what repaints, and what it costs | [reference/performance.md](../../skills/winamp-modern-skin-guide/reference/performance.md) |
| MAKI | [reference/scripting.md](../../skills/winamp-modern-skin-guide/reference/scripting.md) |
| Script-built UI: `onSetXuiParam` and `System.newGroup` | [reference/scripting.md](../../skills/winamp-modern-skin-guide/reference/scripting.md) |
| Rotary controls: `Map` | [reference/scripting.md](../../skills/winamp-modern-skin-guide/reference/scripting.md) |
| Asking a skin what it actually shipped | [reference/scripting.md](../../skills/winamp-modern-skin-guide/reference/scripting.md) |
| Track metadata the skins actually read | [reference/scripting.md](../../skills/winamp-modern-skin-guide/reference/scripting.md) |
| A file-info line is blank / `getPlayItemMetaDataString` keys and units | [compatibility/maki-surface.md](../../skills/winamp-modern-skin-guide/compatibility/maki-surface.md) |
| Star ratings (`getCurrentTrackRating` and its 0–5 vs 0–10 scale) | [compatibility/maki-surface.md](../../skills/winamp-modern-skin-guide/compatibility/maki-surface.md) |
| `onTextChanged` is how a skin learns a host readout moved | [reference/scripting.md](../../skills/winamp-modern-skin-guide/reference/scripting.md) |
| The equalizer tells the skin it moved | [reference/scripting.md](../../skills/winamp-modern-skin-guide/reference/scripting.md) |
| The keyboard is a string, and a borderless window has to ask for it | [reference/scripting.md](../../skills/winamp-modern-skin-guide/reference/scripting.md) |
| The mouse wheel is a *layout* event, and it carries two arguments | [reference/scripting.md](../../skills/winamp-modern-skin-guide/reference/scripting.md) |
| `embed_xui` — the wrapper **is** the control, and must not keep a second copy of its value | [reference/scripting.md](../../skills/winamp-modern-skin-guide/reference/scripting.md) |
| `getAutoWidth()` / `getAutoHeight()` measure the string; they never read the box back | [reference/scripting.md](../../skills/winamp-modern-skin-guide/reference/scripting.md) |
| Scrolling: `scrollToPercent` is a viewport offset, not a layout change | [reference/scripting.md](../../skills/winamp-modern-skin-guide/reference/scripting.md) |
| A skin spells the axis two ways, and `"v"` is not a typo | [reference/rendering.md](../../skills/winamp-modern-skin-guide/reference/rendering.md) |
| Ask for the live trace first, not fourth | [reference/harness.md](../../skills/winamp-modern-skin-guide/reference/harness.md) |
| Which layout a container opens in | [reference/components.md](../../skills/winamp-modern-skin-guide/reference/components.md) |
| `TOGGLE`'s parameter is a component **or a container id** | [reference/components.md](../../skills/winamp-modern-skin-guide/reference/components.md) |
| `default_visible="1"` — the windows a skin opens with itself | [reference/components.md](../../skills/winamp-modern-skin-guide/reference/components.md) |
| Component hosting | [reference/components.md](../../skills/winamp-modern-skin-guide/reference/components.md) |
| The component bucket — Winamp's thinger (B34) | [reference/components.md](../../skills/winamp-modern-skin-guide/reference/components.md) |
| The four routes a skin reaches the web by (B40) | [reference/components/browser.md](../../skills/winamp-modern-skin-guide/reference/components/browser.md) |
| The window layer these views sit in | [reference/components.md](../../skills/winamp-modern-skin-guide/reference/components.md) |
| Where a surface lives | [reference/components.md](../../skills/winamp-modern-skin-guide/reference/components.md) |
| Synthesizing a missing window | [reference/components.md](../../skills/winamp-modern-skin-guide/reference/components.md) |
| NullPlayer-owned hosted windows are lazy | [reference/components.md](../../skills/winamp-modern-skin-guide/reference/components.md) |
| Container-scoped layout callbacks | [reference/components.md](../../skills/winamp-modern-skin-guide/reference/components.md) |
| Resize, and why a skin needs it | [reference/components.md](../../skills/winamp-modern-skin-guide/reference/components.md) |
| How large NullPlayer draws its own text | [reference/components.md](../../skills/winamp-modern-skin-guide/reference/components.md) |
| Colours and hosted AppKit content | [reference/components.md](../../skills/winamp-modern-skin-guide/reference/components.md) |
| Repaint routes are per-window, and scripts are not | [reference/components.md](../../skills/winamp-modern-skin-guide/reference/components.md) |
| Teardown order | [reference/components.md](../../skills/winamp-modern-skin-guide/reference/components.md) |
| Mode integration | [reference/components.md](../../skills/winamp-modern-skin-guide/reference/components.md) |
| Notifier — track-change toast | [reference/components/notifier.md](../../skills/winamp-modern-skin-guide/reference/components/notifier.md) |
| ClassicPro engine | [reference/classicpro.md](../../skills/winamp-modern-skin-guide/reference/classicpro.md) |
| WACUP-era skins | [reference/wacup.md](../../skills/winamp-modern-skin-guide/reference/wacup.md) |
| An `<animatedlayer>` is one frame, not one sheet | [reference/rendering.md](../../skills/winamp-modern-skin-guide/reference/rendering.md) |
| Debugging a skin | [reference/harness.md](../../skills/winamp-modern-skin-guide/reference/harness.md) |
| The order that made Phase 33 cheap | [reference/harness.md](../../skills/winamp-modern-skin-guide/reference/harness.md) |
| The golden images | [reference/harness.md](../../skills/winamp-modern-skin-guide/reference/harness.md) |
| What is open right now, ranked | `TASKS.md` (the only live backlog); [triage-playbook.md](../../skills/winamp-modern-skin-guide/triage-playbook.md) §4b is historical |
