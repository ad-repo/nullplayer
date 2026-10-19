import AppKit
import NullPlayerCore

/// Internet Radio's actions: stations, folders, smart folders and playlist import, and the
/// YouTube source's Add Channel.
extension LibraryBrowserActions {

    // MARK: - Stations

    func addStation() {
        radioStationSheet = AddRadioStationSheet(station: nil)
        radioStationSheet?.showDialog { [weak self] station in
            guard let self else { return }
            self.radioStationSheet = nil
            guard let station else { return }
            RadioManager.shared.addStation(station)
            self.showRadioSource()
        }
    }

    func editStation(_ station: RadioStation) {
        radioStationSheet = AddRadioStationSheet(station: station)
        radioStationSheet?.showDialog { [weak self] updated in
            guard let self else { return }
            self.radioStationSheet = nil
            guard let updated else { return }
            RadioManager.shared.updateStation(updated)
            self.model.reloadInternetRadioForCurrentMode()
        }
    }

    func deleteStation(_ station: RadioStation) {
        guard Self.confirm("Delete radio station?", "Are you sure you want to delete '\(station.name)'?",
                           confirmTitle: "Delete") else { return }
        RadioManager.shared.removeStation(station)
        model.reloadInternetRadioForCurrentMode()
    }

    func addMissingDefaultStations() {
        RadioManager.shared.addMissingDefaults()
        if case .radio = model.currentSource { model.reloadInternetRadioForCurrentMode() }
    }

    func resetStationsToDefaults() {
        guard Self.confirm("Reset to Defaults",
                           "This will remove all your saved radio stations and replace them with the default stations. Are you sure?",
                           confirmTitle: "Reset") else { return }
        RadioManager.shared.resetToDefaults()
        if case .radio = model.currentSource { model.reloadInternetRadioForCurrentMode() }
    }

    /// After adding stations, show them: switch to Internet Radio, or reload it.
    private func showRadioSource() {
        if case .radio = model.currentSource {
            model.reloadInternetRadioForCurrentMode()
        } else {
            model.currentSource = .radio
        }
    }

    // MARK: - Folders

    func createFolder() {
        guard let name = Self.promptForFolderName(title: "New Folder", message: "Enter a folder name for Internet Radio:",
                                                  confirmTitle: "Create") else { return }
        guard RadioManager.shared.createUserFolder(named: name) != nil else {
            Self.warn("Unable to Create Folder", "Use a unique, non-empty folder name.")
            return
        }
        model.reloadInternetRadioForCurrentMode()
    }

    func createFolder(adding station: RadioStation) {
        guard let name = Self.promptForFolderName(title: "New Folder", message: "Create a folder and add '\(station.name)' to it:",
                                                  confirmTitle: "Create") else { return }
        guard let folder = RadioManager.shared.createUserFolder(named: name) else {
            Self.warn("Unable to Create Folder", "Use a unique, non-empty folder name.")
            return
        }
        _ = RadioManager.shared.addStation(station, toUserFolderID: folder.id)
        model.reloadInternetRadioForCurrentMode()
    }

    func renameFolder(_ folderID: UUID) {
        guard let existing = RadioManager.shared.userRadioFolders().first(where: { $0.id == folderID }),
              let name = Self.promptForFolderName(title: "Rename Folder", message: "Enter a new name:",
                                                  confirmTitle: "Rename", defaultValue: existing.name) else { return }
        guard RadioManager.shared.renameUserFolder(id: folderID, to: name) else {
            Self.warn("Unable to Rename Folder", "Use a unique, non-empty folder name.")
            return
        }
        model.reloadInternetRadioForCurrentMode()
    }

    func deleteFolder(_ folderID: UUID) {
        guard let existing = RadioManager.shared.userRadioFolders().first(where: { $0.id == folderID }),
              Self.confirm("Delete Folder?", "Delete '\(existing.name)' and its station memberships?",
                           confirmTitle: "Delete") else { return }
        _ = RadioManager.shared.deleteUserFolder(id: folderID)
        model.reloadInternetRadioForCurrentMode()
    }

    func toggleMembership(of station: RadioStation, inFolder folderID: UUID) {
        if RadioManager.shared.isStation(station, inUserFolderID: folderID) {
            _ = RadioManager.shared.removeStation(station, fromUserFolderID: folderID)
        } else {
            _ = RadioManager.shared.addStation(station, toUserFolderID: folderID)
        }
        model.reloadInternetRadioForCurrentMode()
    }

    func setSmartGenre(_ genre: String?, for station: RadioStation) {
        _ = RadioManager.shared.setSmartGenreOverride(genre, for: station)
        model.reloadInternetRadioForCurrentMode()
    }

    func setSmartRegion(_ region: String?, for station: RadioStation) {
        _ = RadioManager.shared.setSmartRegionOverride(region, for: station)
        model.reloadInternetRadioForCurrentMode()
    }

    private static func promptForFolderName(title: String, message: String, confirmTitle: String,
                                            defaultValue: String = "") -> String? {
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        textField.stringValue = defaultValue
        guard confirm(title, message, confirmTitle: confirmTitle, accessory: textField) else { return nil }
        let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    // MARK: - Playlist import

    func importRadioPlaylistURL() {
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = "https://example.com/playlist.m3u"
        guard Self.confirm("Import Playlist URL", "Enter the URL of a .m3u or .pls playlist file containing radio streams:",
                           confirmTitle: "Import", accessory: textField) else { return }
        let urlString = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            Self.warn("Invalid URL", "Please enter a valid URL.")
            return
        }
        Task { @MainActor [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let content = String(data: data, encoding: .utf8) else {
                    Self.warn("Playlist Error", "Could not read playlist content")
                    return
                }
                let stations = RadioStation.stations(inPlaylist: content, sourceURL: url)
                guard !stations.isEmpty else {
                    Self.warn("Playlist Error", "No valid streams found in playlist")
                    return
                }
                stations.forEach { RadioManager.shared.addStation($0) }
                self?.showRadioSource()
                Self.warn("Playlist Added", "Added \(stations.count) station\(stations.count == 1 ? "" : "s") from the playlist.")
            } catch {
                Self.warn("Playlist Error", "Failed to fetch playlist: \(error.localizedDescription.redactingSensitiveURLQueryItems)")
            }
        }
    }

    func importRadioPlaylistFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["m3u", "m3u8", "pls"].compactMap { .init(filenameExtension: $0) }
        panel.message = "Select playlist files containing radio streams"
        guard panel.runModal() == .OK else { return }
        importRadioPlaylistFiles(panel.urls, reportEmpty: true)
    }

    /// Add every stream in the playlist files as a station, then show Internet Radio.
    func importRadioPlaylistFiles(_ urls: [URL], reportEmpty: Bool) {
        var added = 0
        for url in urls {
            do {
                let stations = RadioStation.stations(inPlaylist: try String(contentsOf: url, encoding: .utf8), sourceURL: url)
                stations.forEach { RadioManager.shared.addStation($0) }
                added += stations.count
            } catch {
                NSLog("Failed to read playlist file %@: %@", url.path, error.localizedDescription.redactingSensitiveURLQueryItems)
            }
        }
        guard added > 0 else {
            if reportEmpty { Self.warn("Playlist Error", "No valid radio streams found in the selected file(s)") }
            return
        }
        showRadioSource()
        Self.warn("Playlist Imported",
                  "Added \(added) station\(added == 1 ? "" : "s") from the playlist\(urls.count == 1 ? "" : "s").")
    }

    // MARK: - YouTube

    func addYouTubeChannel() {
        youtubeChannelSheet = AddYouTubeChannelSheet()
        youtubeChannelSheet?.showDialog { [weak self] channel in
            guard let self else { return }
            self.youtubeChannelSheet = nil
            guard channel != nil else { return }
            if case .youtube = self.model.currentSource {
                self.model.rebuildCurrentModeItems()
            } else {
                self.model.currentSource = .youtube
            }
        }
    }
}
