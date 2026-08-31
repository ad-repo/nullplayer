# Reeltone Compatibility

NullPlayer supports Reeltone format versions 1 and 2. Archives are untrusted ZIP input and must
contain `skin.json` at the root. Installation validates paths, entry count, compression ratio,
uncompressed size, image dimensions, aggregate decoded image memory, fonts, and all referenced
resources before the skin enters the store.

## Version 1

Supported theme fields include the published colors and built-in or packaged fonts. Version 1 uses
the Original content implementation with a Reeltone-owned palette and isolated presentation
preferences. Fixed-deck sprites are validated for package safety but are not rendered by that
adapter; each declared sprite produces a structured `unsupportedConstruct` warning instead of
being silently ignored.

## Version 2

The supported component vocabulary is:

`play`, `pause`, `playPause`, `stop`, `prev`, `next`, `seek`, `volume`, `shuffle`,
`repeatMode`, `title`, `elapsed`, `duration`, `artwork`, `trackList`, `visualiser`,
`equaliser`, `close`, `minimise`, `togglePanel`, `decoration`, `library`, and `libraryBack`.

NullPlayer supports rectangular and elliptical clipping; bar, slider, and knob controls; all six
art states; frame animations driven by playback, always, or never; main and named panel surfaces;
all four panel attachment edges; hosted Playlist, Equalizer, Library, artwork, and visualization;
authored playlist/library row heights; scrolling title marquees; accessible text and controls; and
Original fallback windows when a singleton host is absent. Duplicate stateful hosts keep the
first declaration and emit a structured warning with skin, surface, region, and component context.
Top-level fixed-deck sprite slots are likewise validated but not applied to shaped surfaces. The
optional `bodyBold` font source is validated but hosted content uses `body`; both cases emit an
`unsupportedConstruct` warning.

Unknown additive object fields are ignored when safe. Unsupported major versions, unknown enum
vocabulary, invalid references, and unsafe packages fail with structured diagnostics.

## Fixture matrix

| Fixture | Coverage | Evidence |
|---|---|---|
| Generated v1 | Palette, sprite resource, archive lifecycle | `ReeltoneManifestTests`, `ReeltoneArchiveLoaderTests` |
| Generated minimal v2 | Main art, coordinates, clipping, controls, animation | `ReeltoneSurfaceInventoryTests` |
| Generated multi-panel v2 | Four attachment edges, visibility, scaling, topology restoration | `ReeltoneSurfaceInventoryTests` |
| Generated hosted v2 | Playlist, Equalizer, Library, multiple visualizers, singleton policy | `ReeltoneSurfaceInventoryTests` |
| Generated malformed packages | Traversal, symlink, duplicate path, resource and budget failures | `ReeltoneArchiveLoaderTests`, `ReeltoneSkinStoreTests` |
| Aqua Glass 2.0 | 960×384 surface, 22 regions, transport art states, dual visualizers, seek, knob, animation | Official CC0 gallery package; archive and extracted-content integrity verified 2026-08-30 |

The Aqua Glass manifest declares `CC0-1.0` and identifies its author as “Reeltone Example
Gallery.” It was downloaded from the [official Reeltone skin gallery](https://reeltone.iagocavalcante.com/skins.html)
at `https://reeltone.iagocavalcante.com/downloads/skins/aqua-glass.reeltone`. The archive SHA-256 is
`19f93b3de2e3b3880e2c4c140f77d915fa39356ea053be4166337de823dc047f`; its extracted contents
exactly match the local manual acceptance fixture. The third-party package remains uncommitted.

## Intentional deviations

Compact Mode and Compact Window are not offered in Reeltone mode. Reeltone regular surfaces,
docking, scaling, restoration, and teardown remain supported. The application exits a compact
presentation when switching from another UI family into Reeltone.
