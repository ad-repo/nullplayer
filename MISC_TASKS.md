# Miscellaneous — open backlog

Open rows that belong to no skin-subsystem backlog. Read the owning skill before picking one up.

| ID | Item | Notes |
|---|---|---|
| M1 | Local YouTube content in the normal library search | Local source → Search should also match YouTube content, with no YouTube-specific search page. Add a "YouTube" section to `buildLocalSearchItems` (ModernLibraryBrowserView ~L10677) and to its PlexBrowserView twin. It should list subscribed channels whose name matches (`YouTubeManager.channels`), shown as `.youtubeChannel` rows, and downloaded videos whose title matches (manifest `youtube_downloads.json` via a new `YouTubeManager.searchDownloads(query:)`), shown as `.youtubeVideo` rows (double-click plays the local file). Must not double-list downloads that already appear under Tracks because the download folder is also a watch folder: dedupe by file URL. No network calls. Skill: `youtube-source`. |
