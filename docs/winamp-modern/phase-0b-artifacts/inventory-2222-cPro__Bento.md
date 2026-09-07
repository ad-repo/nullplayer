# Winamp Modern .wal inventory — 2222-cPro__Bento
_generated 2026-08-15T17:41:00Z_

## 1. Bounded archive
- entries: **47** (cap 5000)
- total uncompressed: **249 KB** (cap 512 MB)
- entry types: png×40, xml×5, txt×1, maki×1

## 2. Mount
- synthetic root: `/var/folders/jj/djjmkdd169x5gz7s3bh9cq8w0000gn/T/winamp-inv-D190834D-C0F2-4119-8A83-74AEA6B1437B`
- skin.xml: `/Skins/2222-cPro__Bento/skin.xml`
- engine mounted at `/Plugins/classicPro/engine` → `/private/tmp/claude-501/-Users-ad-Projects-nullplayer--claude-worktrees-fix-modern-alphabet-picker/60a978ed-2fa6-40f1-affd-9cb14d5d3ff9/scratchpad/cpro-engine/Plugins/ClassicPro/engine`

## 3. XML include graph + inventory
- files visited (include-expanded): **40**
- `@VAR@` tokens resolved: @COLORTHEMESPATH@
- groupdefs: **129** (xuitag registrations: **24**)
- containers: **9**, layouts: **11**
- windowholders / component buckets: **10**
- scripts attached: **47**
- resources: bitmaps=630, fonts=2, colors=38, gamma=300

### Custom XUI class registrations (`groupdef xuitag=`)
| xuitag | groupdef id | inherit | embed_xui | source |
|---|---|---|---|---|
| `SC:FadeText` | sc.FadeText | - | - | /Plugins/classicPro/engine/xui/FadeText/FadeText.xml:1 |
| `Wasabi:Text` | wasabi.text.group | - | wasabi.text | /Plugins/classicPro/engine/xui/FadeText/FadeText.xml:1 |
| `Wasabi:Button` | wasabi.button.group | - | wasabi.button | /Plugins/classicPro/engine/xui/WasabiButton/WasabiButton.xml:1 |
| `Wasabi:ToggleButton` | wasabi.togglebutton.group | - | wasabi.button | /Plugins/classicPro/engine/xui/WasabiButton/WasabiButton.xml:1 |
| `SC:ProgressGrid` | sc.seekProgress | - | main.albumart | /Plugins/classicPro/engine/xui/SC-ProgressGrid/SC-ProgressGrid.xml:1 |
| `Wasabi:AlbumArt` | Wasabi.AlbumArt | - | main.albumart | /Plugins/classicPro/engine/xui/AlbumArt/AlbumArt.xml:1 |
| `SC:Channels` | SC.Channels | - | sc.main.ch | /Plugins/classicPro/engine/xui/SC-Channels/sc-channels.xml:1 |
| `Wasabi:Ratings` | Wasabi.Ratings | - | - | /Plugins/classicPro/engine/xui/Ratings/Ratings.xml:1 |
| `Wasabi:EditBox` | wasabi.edit | wasabi.objectframe.group | wasabi.edit.box | /Plugins/classicPro/engine/xui/editbox/editbox.xml:1 |
| `Wasabi:EditBox2` | wasabi.edits | - | wasabi.edit.box | /Plugins/classicPro/engine/xui/PlaylistPro/_v1/PlaylistPro.xml:1 |
| `PlaylistPro` | PlaylistPro.xui | - | PlaylistPro.wdh | /Plugins/classicPro/engine/xui/PlaylistPro/_v1/PlaylistPro.xml:1 |
| `Cpro:Tab` | cpro.tab | - | cpro.tab.button | /Plugins/classicPro/engine/xui/CentroSUI/_v1/CproTabs/CproTabButton.xml:1 |
| `Cpro:Tabs` | cprotabs.xui | - | - | /Plugins/classicPro/engine/xui/CentroSUI/_v1/CproTabs/CproTabs.xml:1 |
| `Centro:SUI` | centro.main | - | - | /Plugins/classicPro/engine/xui/CentroSUI/_v1/CentroSUI.xml:1 |
| `ModernSongticker` | m.songticker | - | - | /Plugins/classicPro/engine/xui/ModernSongticker/ModernSongticker.xml:1 |
| `SC:UpdateSystem` | sc.updatesystem.xuidef | - | - | /Plugins/classicPro/engine/xui/updateSystem/updateSystem.xml:1 |
| `SC:VScrollBar` | sc.xui.vscrollbar | - | slider | /Plugins/classicPro/engine/xui/ScrollBar/vscrollbar.xml:1 |
| `SC:NowPlaying` | sc.nowplaying | - | - | /Plugins/classicPro/engine/widgets/Data/NowPlaying/NowPlaying.xml:1 |
| `Bento:InfoLine` | bento.infodisplay.line | - | text | /Plugins/classicPro/engine/one/xml/player-normal-group.xml:1 |
| `Wasabi:StandardFrame:Status` | wasabi.standardframe.statusbar | - | - | /Plugins/classicPro/engine/one/xml/standardframe.xml:1 |
| `Wasabi:StandardFrame:NoStatus` | wasabi.standardframe.nostatusbar | - | - | /Plugins/classicPro/engine/one/xml/standardframe.xml:1 |
| `Wasabi:StandardFrame:Modal` | wasabi.standardframe.modal | wasabi.standardframe.nostatusbar | - | /Plugins/classicPro/engine/one/xml/standardframe.xml:1 |
| `Wasabi:StandardFrame:Static` | wasabi.standardframe.static | wasabi.standardframe.nostatusbar | - | /Plugins/classicPro/engine/one/xml/standardframe.xml:1 |
| `cPro:About` | cpro.about.xui | - | - | /Plugins/classicPro/engine/xml/about.xml:1 |

### Component hosting surfaces (windowholders / buckets → native GUIDs)
| id | holds | source |
|---|---|---|
| PlaylistPro.wdh | `guid:{45f3f7c1-a6f3-4ee6-a15e-125e92fc3f8d}` | /Plugins/classicPro/engine/xui/PlaylistPro/_v1/PlaylistPro.xml:1 |
| widget.loader | `componentbucket:centro.widgets.main` | /Plugins/classicPro/engine/xui/CentroSUI/_v1/CproTabs/CproTabs.xml:1 |
| centro.windowholder.library | `guid:{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}` | /Plugins/classicPro/engine/xui/CentroSUI/_v1/CentroSUI.xml:1 |
| centro.windowholder.video | `guid:{F0816D7B-FFFC-4343-80F2-E8199AA15CC3}` | /Plugins/classicPro/engine/xui/CentroSUI/_v1/CentroSUI.xml:1 |
| centro.windowholder.visualization | `guid:{0000000A-000C-0010-FF7B-01014263450C}` | /Plugins/classicPro/engine/xui/CentroSUI/_v1/CentroSUI.xml:1 |
| centro.windowholder.other | `@all@` | /Plugins/classicPro/engine/xui/CentroSUI/_v1/CentroSUI.xml:1 |
| - | `guid:{F0816D7B-FFFC-4343-80F2-E8199AA15CC3}` | /Plugins/classicPro/engine/xui/CentroSUI/_v1/CentroSUI.xml:1 |
| - | `guid:{0000000A-000C-0010-FF7B-01014263450C}` | /Plugins/classicPro/engine/xui/CentroSUI/_v1/CentroSUI.xml:1 |
| widget.loader.mini | `componentbucket:centro.widgets.mini` | /Plugins/classicPro/engine/xui/CentroSUI/_v1/CentroSUI.xml:1 |
| widget.loader | `componentbucket:centro.widgets.drawer` | /Plugins/classicPro/engine/one/xml/player-normal-group.xml:1 |

### Containers / layouts (top-level windows)
- container `searchresults` name=Search Results — /Plugins/classicPro/engine/xui/PlaylistPro/_v1/PlaylistPro.xml:1
- container `browserpro` name=BrowserPro Providers — /Plugins/classicPro/engine/widgets/load/browserpro.xml:1
- container `notifier` name=Notifier — /Plugins/classicPro/engine/xml/notifier.xml:1
- container `main` name=Main Window — /Plugins/classicPro/engine/one/xml/player.xml:1
- container `MLibrary` name=Media Library — /Plugins/classicPro/engine/one/xml/window-overrides.xml:1
- container `AVS` name=Visualizations — /Plugins/classicPro/engine/one/xml/window-overrides.xml:1
- container `Video` name=Video — /Plugins/classicPro/engine/one/xml/window-overrides.xml:1
- container `Pledit` name=Playlist Editor — /Plugins/classicPro/engine/one/xml/window-overrides.xml:1
- container `widgets.manager` name=Widgets Manager — /Plugins/classicPro/engine/xml/widgets-manager.xml:1

## 4. MAKI corpus inventory
- `.maki` files parsed: **91** valid, 0 invalid
- header versions seen: 0x0403
- distinct imported class GUIDs across corpus: **59**
- distinct API method names referenced: **635**

### Top 40 MAKI API methods (by files referencing them)
| method | files | method | files |
|---|--:|---|--:|
| `getPrivateInt` | 91 | `getRuntimeVersion` | 91 |
| `getSkinName` | 91 | `getTimeOfDay` | 91 |
| `integerToString` | 91 | `messageBox` | 91 |
| `onScriptLoaded` | 91 | `runtimecheck` | 91 |
| `setPrivateInt` | 91 | `getScriptGroup` | 77 |
| `setXmlParam` | 67 | `findObject` | 61 |
| `show` | 51 | `hide` | 47 |
| `strlower` | 44 | `getWidth` | 41 |
| `getToken` | 40 | `onTimer` | 38 |
| `setDelay` | 38 | `start` | 37 |
| `stop` | 37 | `stringToInteger` | 35 |
| `getHeight` | 34 | `onSetVisible` | 34 |
| `getObject` | 33 | `onLeftClick` | 32 |
| `getParam` | 31 | `onScriptUnloading` | 31 |
| `getContainer` | 29 | `getLayout` | 29 |
| `getPublicInt` | 29 | `isVisible` | 29 |
| `loadMap` | 29 | `onResize` | 29 |
| `getLeft` | 28 | `setText` | 28 |
| `gotoTarget` | 26 | `main` | 26 |
| `onLeftButtonDown` | 26 | `setTargetSpeed` | 26 |

