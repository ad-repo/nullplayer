# Fix Search for Jellyfin, Navidrome/Subsonic, and Emby

- [x] Add cached search result properties (jellyfinSearchResults, subsonicSearchResults, embySearchResults) near line 327
- [x] Replace Subsonic search stub with manager.search() call + buildSubsonicSearchItems() (line 5910)
- [x] Replace Jellyfin search stub with manager.search() call + buildJellyfinSearchItems() (line 5993)
- [x] Replace Emby search stub with manager.search() call + buildEmbySearchItems() (line 6083)
- [x] Add buildSubsonicSearchItems() function
- [x] Add buildJellyfinSearchItems() function
- [x] Add buildEmbySearchItems() function
- [x] Add .search case to Subsonic switch in rebuildCurrentModeItems()
- [x] Add .search case to Jellyfin switch in rebuildCurrentModeItems()
- [x] Add .search case to Emby switch in rebuildCurrentModeItems()
- [x] Build and verify no compile errors
