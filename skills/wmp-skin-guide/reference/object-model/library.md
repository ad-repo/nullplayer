# `.wmz` object model: the library

Moved verbatim from `reference/object-model.md` on 2026-09-25; that file is the router. Read it first.

## The library: `playlistCollection` and `mediaCollection` (W136)

**Decided 2026-09-24: a skin sees the source the library browser has selected, read-only.** In
NullPlayer "the library" is contextual — Local Files, a Plex, Navidrome/Subsonic, Jellyfin or Emby
server — so `player.playlistCollection` and `player.mediaCollection` answer from whichever one the
browser's source picker is on (`ModernBrowserSource`, persisted as `BrowserSource`). Writes that would
change the library (`newPlaylist` into the collection, `add`, `remove`, `importPlaylist`) stay
unrecognised. This closed W66 (the empty `plListBox1/2`) and W136 (`deleteAll` and the list-box fill).

**What reads it.** 18 of 179 archives call one of the two collections; the calls, by corpus count, are
`getMediaAtom` 45, `getByName` 27, `getByAttribute` 22, `getAll` 13+12, `newPlaylist` 9,
`getAttributeStringCollection` 5, `getByAlbum` 4. The three shapes that matter:
`WoW`/`NVIDIA`'s playlist chooser (`playlistCollection.getAll()` → a `<LISTBOX>` row per playlist,
`getByName` on click, `player.currentPlaylist = …` on double-click), `digitaldj`'s genre/artist/album
pickers (`getAttributeStringCollection`, `getByGenre`/`getByAlbum`), and the search box every Skins
Factory player carries (below).

### How it is built

- **`WMPLibraryCatalog`** (`WMPSkin/`) is an immutable value the host hands the runtime whole
  (`WMPScriptRuntime.setLibrary`). The object model reads it and never touches a store, a file or a
  network. It holds tracks, the library proper (`libraryTracks`), playlists by **id**, fetched query
  answers (`queryResults`) and, for a server, the artist/album/genre name lists (`strings`).
- **`WMPLibrarySource`** (`Windows/WMPSkin/WMPLibraryCatalogBuilder.swift`) builds it. **Local Files**
  is held whole — every scanned track and movie, every saved `.m3u` parsed — so `isComplete` is true
  and every query is a filter. **A server** is not: the catalog starts as what its manager already has
  cached (playlist names; artist, album and genre lists), `isComplete` is false, `libraryTracks` is
  **empty**, and tracks are fetched on demand through one `WMPLibraryProvider` per server (the same
  manager calls the browser makes: `fetchPlaylistSongs`, `fetchSongs(forAlbum:)`, `convertToTracks`).
  Plex lists its playlists only when the browser's Playlists tab asks, so the provider fetches them
  itself when the cache is empty, and drops smart playlists that query another Plex library section
  (Plex answers 500, then 404 — they can never play).
- **Every object a collection hands out is a path, not an allocation** — `library.playlists:all`,
  `library.playlist:<id>`, `library.query:<attribute>:<value>`, `library.scratch:<n>`,
  `library.media:<index>` — so a reference a skin keeps in `playlist1.playlist` still resolves in a
  later transaction. A proxy handed back as a *value* (`x.playlist = pl`) crosses `__wmpSet` as
  `WMPObjectModel.objectReferencePrefix` + its path (`WMPScriptContext.jsonValue`) and reads back as
  the object.
- **Playlists are referenced by id, never by position**: a server re-lists its playlists whenever it
  reloads, and a reference by position named whichever playlist moved into the slot.
- **Only the selected source's own events rebuild it**: `MediaLibrary.libraryDidChangeNotification`
  for Local Files, the server's `libraryContentDidPreloadNotification` for a server, and a change of
  `BrowserSource` in defaults. A source switch is a different library (`catalog.sourceID`): every pane
  goes back to the live queue and every search result is dropped.

### Answered from what is loaded, then refreshed

WMP's collections are synchronous; a server is not. **A question the catalog cannot answer yet is
answered empty and recorded as a demand** (`WMPObjectModel.libraryDemands`: `playlist:<id>`,
`query:<attribute>:<value>`, `play:<playlist path>`), which the runtime hands the host with the view and
event that asked (`setLibraryDemandHandler`). The host fetches it (`WMPLibrarySource.fetch`, one
request per demand — a second asker awaits the first), hands back the fuller catalog, and refreshes:

- **a view whose `onLoad` read the library is loaded again** when the playlist list changes (a source
  switch, a server finishing its preload) — the load it would have run had the library been there;
  the runtime records which views those are (`viewsThatFillFromLibrary`);
- **a view that authors `CdromMediaChange` raises it instead, with the view's own `onResize` after
  it in the same transaction** (W274). A chooser filled from a click — `NVIDIA`'s `plModeToggle()` —
  is never refilled by a reload, and re-dispatching the click toggles the mode back off. All nine
  `<LISTBOX>` skins author `CdromMediaChange="onCdRomChange()"`, and its body is their refill:
  `fillListBox(); fillCopyListBox();` in eight, and in `NVIDIA` the fill when the list is showing
  and a reset of its `loadList` latch when it is not. The `onResize` is for `NVIDIA`, the one
  whose `fillListBox()` does not size the list; the other eight do it inside the fill. No CD ever
  raises the event, so `cdrommediachange` is in `handlerNames` and not `supportedEvents`;
- **every other open view runs a handler-less `librarychange` transaction**, which is what redraws a
  pane whose playlist's tracks just arrived.

`getAttributeStringCollection` on a server answers from the manager's lists; `getByAlbum`/`getByGenre`
fetch at most **25 albums** per query, `getByAuthor` the artist's albums; `getByAttribute("MediaType", …)`
and titles filter only what is loaded.

### `player.currentPlaylist = …`

The assignment replaces the queue with the playlist's tracks — `setPlaylistTracks`, then
`playTrack(at:)` — carried as **catalog indices** (`loadLibraryTracks`), because `sourceURL` is WMP's
`C:\…` spelling for the skin to read, not a location. From then on that playlist *is* the current one
(`currentLibraryPlaylist`): a pane showing it shows the live queue, and `player.currentPlaylist.name`
answers its name, which is how `WoW` finds it again (`nList` → `getByName`).

**A playlist with no tracks yet never becomes current, and the `play()` after it is withheld** in that
transaction. Before this, a server playlist still loading was adopted anyway and every skin's
`player.controls.play()` straight after it played the previous queue under the new name. A loading
playlist is played when its fetch lands (`play:` demand); a failed one plays nothing. **Only the latest
request plays**: each pending play takes a ticket, and a later request, or any other change to the
queue while it loads, makes it stale.

### `<PLAYLIST>` panes and `<LISTBOX>` choosers

- **A `<PLAYLIST>` pointed at a library playlist or a search result shows it** (`WMPWidgetScriptState`,
  read on the script queue with the rows) **until the queue next changes from anywhere** — adding an
  artist from the browser puts the live queue back (`WMPObjectModel.queueGeneration`). A double-click
  or Return in it plays that playlist from the row; delete and reorder are refused, a skin may not edit
  the library. Rows are cached per catalog so a library-sized playlist (Plex's "All Music") is not
  rebuilt every tick.
- **A `<LISTBOX>`** answers `appendItem`, `deleteAll`, `insertItem`, `deleteItem`, `getItem`, `itemCount`,
  scrolls, and shows the highlight the script **wrote in that transaction** — reported as state on every
  transaction, one that started before a fast click put the old row back. **That write is handed to the
  chooser ahead of the scene** (W300): a write is reported by one transaction only, and the one that
  carries `playSelPlaylist()`'s `plListBox1.selectedItem = 0` also posts the `play()` whose host
  refresh starts the next transaction, which cancels the scene's presentation every time. Dropped
  with the scene, the played row stayed highlighted instead of "Now Playing".
- **A click and a double-click are queued per window** (`enqueueListEvent`): the click writes
  `selectedItem` and raises `selectedItem_onChange`; the double-click writes the **clicked row** and
  raises `onDblClick`, after the click's transaction has finished. Dispatched independently,
  `WoW`'s `playSelPlaylist()` ran before `getSelPlaylist()` and played the playlist chosen before.
- **`ondblclick`, `onfocus` and `onblur` are classified** (`WMPAttributeParser.handlerNames`) and raised by
  a `<LISTBOX>` and an `<EDITBOX>` only, so they stay off `supportedEvents`. An `<EDITBOX>` shows the
  `value` its script holds (the "Search..." placeholder its own `onFocus` clears) except while the user is
  typing, and Return raises `onKeyUp` with `event.keyCode` 13.

### Search

Every Skins Factory search box (`WoW`, `NVIDIA` and their family) is the same script:
`onMlSearch(value)` calls `player.mediaCollection.getAll()`, makes `player.newPlaylist("", "")`, walks
every item testing `Author`, `Title`, `WM/AlbumTitle`, `WM/AlbumArtist` and `WM/Genre` (via
`getMediaAtom`/`getItemInfoByAtom`) for the text, `appendItem`s each hit, and assigns the result to the
pane. **On Local Files that runs as written**: `getAll()` is the whole library and the skin's own loop is
the search.

**A server's whole library cannot be handed over** — tens of thousands of tracks walked inside the
0.25 s handler limit — **so on a server `getAll()` becomes the server's track search** for the text in
the view's search box:

1. **When it applies**: an incomplete source, a transaction raised by the user's own act (`click`,
   `dblclick`, `keyup`/`keydown`/`keypress`, `mousedown`/`mouseup`), and exactly one `<EDITBOX>` in the
   view with text in it. Anywhere else — `onLoad`, a timer, the refresh after a source switch —
   `getAll()` is the (empty) library proper, so a term left in the box is never searched again on its own.
2. **First run**: `getAll()` answers empty and demands `query:search:<text, lower-cased>`; the skin's
   loop finds nothing and the pane shows the empty result for a moment.
3. **The host asks the server**, through the same search the browser's Search tab uses, keeping the
   tracks only:

   | Server | Call | What becomes the result | Cap |
   |---|---|---|---|
   | Plex | `/hubs/search`, `type: .track` | the track hub | 50 |
   | Jellyfin, Emby | `searchTerm`, `IncludeItemTypes` incl. `Audio` | the `Audio` items | 50 |
   | Navidrome/Subsonic | `search3` | the songs | 20 |

4. **When the results land, the host runs the same event again, once** (the Return, or the click on the
   search button). `getAll()` now answers with them, and the skin's own loop filters and lists them as
   it would the library — so a server match whose author/title/album/genre does not contain the text
   is dropped, exactly as WMP would. The second run finds the answer cached and asks for nothing.
5. The answer is cached per term for the source's life; a source switch drops it.

The result is a scratch playlist (`library.scratch:<n>`, at most 16 kept) that exists only for the
session — `newPlaylist` does not add to the library, which is the write a skin is refused. It plays
like any library playlist.

**Fetched server tracks are not the library proper.** They are in `tracks` so a playlist or a search can
name them, but never in `libraryTracks`: counting them made `getAll()` and "All Music" answer with
whatever had been searched for or opened earlier, which is how a `WoW` search came back in `NVIDIA`
after a skin and a source switch.

### The 0.25 s budget, measured

`WoW`'s `fillListBox()` makes about four script→host calls per playlist inside one `onLoad`, and the
Jellyfin server this was built against has **1,850 playlists**. A per-call scan of the playlist list
made that quadratic and ran the handler past `WMPPhase0Limits.scriptExecutionSeconds`, which
terminates it right after `deleteAll()` and leaves the chooser empty
(`[wmp/script] handler-error: load[0]: JavaScript execution terminated`). Lookups by id are a dictionary
(`WMPLibraryCatalog.playlistIndexByID`) and `getAll()`'s `count`/`item(i)` never build the list. **A
new per-playlist call has to stay O(1)**, or the largest libraries lose their chooser again. The same
rule on the host side: `WMPLibrarySource.append` finds tracks by URL in a dictionary — scanning
`playables` for each fetched track beachballed the app on Plex's "All Music".

### Pitfalls this surface taught

- **Anything read after the runtime's `await` can belong to another window.** `WoW`'s `plView` and
  `mainView` both transact on every position tick; list rows read after `context.run` returned were
  whichever view the context had swapped in, and the chooser flashed empty several times a second.
  List items and widget state are read on the script queue, in the block that ran the handlers
  (`WMPScriptRunResult.listItems`/`widgetState`).
- **`playNow` inserts after the current track**; a playlist assignment replaces the queue, so it is
  `setPlaylistTracks` + `playTrack(at:)`.
- **Only a member that needs a playlist's tracks may demand them** (W274). Resolving *any* member of
  a `library.playlist:` object used to read its tracks first, so the fill loop's
  `item(i).getItemInfo("Title")` demanded every server playlist — 1,850 serial fetches on Jellyfin
  for a list of names, from `WoW` as much as `NVIDIA`. `count` and `item(i)` read the tracks; `name`
  and `getItemInfo` do not.
- **The JS proxy caches only an object's own shape** (W274). Every element global is one proxy
  for the session, and it used to cache every object-valued member it answered — so
  `playlist1.playlist` kept answering the first playlist ever stored there. `Alienware Invader`'s
  `playSelPlaylist()` then assigned the playing playlist back to itself (inert), or after a source
  switch a playlist the new catalog does not hold, and a second choice never played. Now a member
  is cached only when its answer is its own child path (`player` → `player.controls`); one that
  answers any other object is a stored value and is asked again on every read. A render sweep
  moved nothing (528/529 identical, the other `Scooby-Doo_2/infoView`).
- **A widget hosted after its rows arrived has to start with them.** The transaction path hands the
  view its list items and widget state and *then* presents, and the present is where a widget is
  first created. `NVIDIA`'s chooser and search box are first hosted in the frame that sizes them, so
  both came up empty — no rows, no "Search for" — and nothing refilled them until some later
  transaction changed the rows. `WMPMainView` keeps the last of each and applies them on creation.
- **A user's input is written into its own view's elements, never the installed ones** (W284). The
  context holds only the view that transacted last, and `Batman Begins`' `controlView` transacts
  every 100 ms, so a chooser click usually landed while `plView` was stashed: `setElementSelection`
  found no element, the row was dropped, and `getSelPlaylist()` read "Now Playing" — an empty
  preview, and a double-click that played nothing. It is a race, so it looked like a synthetic-click
  fault (a reporter's own first double-click lost it too). `setWidgetSelection` now takes the view
  id and writes into that view's registry when another is installed. `setElementValue`, `Text` and
  `Down` still look only in the installed view; nothing has been measured failing through them.

`WMPLibraryTests` and `WMPLibrarySurfaceTests` pin all of the above.
