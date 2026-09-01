# Windows Media Player skin guide

NullPlayer can use user-supplied Windows Media Player `.wmz` skins. It does not bundle Microsoft or
community skins. A fresh installation opens in NullPlayer's own unskinned WMP player, which provides
transport, mute, time, minimize, close, and **Import WMZ…** controls without reading artwork or
preferences from another NullPlayer skin family.

## Import, select, and remove

1. Choose **Import WMZ…** on the unskinned player, or open **UI > Windows Media Player > Load WMZ
   Skin…**.
2. Select a `.wmz` file. NullPlayer validates the complete archive before installing it under
   `~/Library/Application Support/NullPlayer/WMPSkins/` and switches to WMP mode.
3. Use **UI > Windows Media Player** to select any installed skin. If it defines multiple views, use
   the **Views** submenu. Skin-authored compact/full buttons can also request a supported view.
4. Choose **Remove “name”…** to delete NullPlayer's installed copy of the selected skin. This never
   deletes the original file you downloaded.

Choose **Unskinned Default Player** at any time to clear the selection without deleting installed
skins. Classic, Original, Original-Metal, and Windows Media Player can be selected live from the
**UI** menu.

## Recovery and reset

- A missing, corrupt, rejected, or deleted selected skin leaves the app in WMP mode and shows the
  unskinned player with a named diagnostic. Import the skin again, choose another installed skin, or
  select **Unskinned Default Player**.
- Skin script preferences are isolated by the archive's content hash. Re-importing different bytes
  does not inherit another skin's namespace.
- To reset the WMP selection manually, choose **Unskinned Default Player**. To remove all installed
  copies, use the menu once per selected skin or open the WMP skins folder and remove only `.wmz`
  files while they are not selected.
- Existing users retain their persisted Classic, Original, Original-Metal, or WMP mode after an
  upgrade. Only a profile with no current or legacy mode preference gets the new WMP default.

## Compatibility reports and support

With a valid skin loaded, choose **Save Compatibility Report…**. The JSON report inventories tags,
attributes, resources, scripts, object-model members, events, and typed diagnostics. It contains no
archive payload, source text, pixels, screenshot, or local input path. Include this file and any
visible `WMPnnnn` diagnostic code in a support report; do not redistribute a skin unless its license
allows it.

For a packaged-build reproduction, advanced users can launch the GUI with the diagnostic hook:

```bash
/Applications/NullPlayer.app/Contents/MacOS/NullPlayer \
  -uiMode wmp -wmpSkinPath /absolute/path/to/skin.wmz
```

The file still passes through the normal validation and installer. The option does not grant skin
script filesystem access.

## Supported format and deliberate limitations

NullPlayer accepts ZIP-based `.wmz` archives containing the XML/JScript `.wms` format associated
with Windows Media Player 7 through 12, subject to the implemented subset in
[`compatibility.md`](compatibility.md). Compatibility is capability-based, not guaranteed by a skin's
claimed player version. Definitions may use UTF-8, UTF-16LE, UTF-16BE, or legacy Windows-1252.

ActiveX, registry and shell access, DLLs, WMP plug-ins, arbitrary filesystem/network access,
skin-authored HTML, native-object reflection, and Windows media effects are unsupported. Video tags
show a NullPlayer-owned placeholder and effects use a safe NullPlayer surface. Script runs in a
separate killable helper with bounded messages and deadlines; a script failure keeps the last valid
static scene and disables script for that skin session.

Auxiliary NullPlayer windows without WMP-owned chrome remain unavailable in WMP mode. Switch to
Classic, Original, or Original-Metal to use those windows.
