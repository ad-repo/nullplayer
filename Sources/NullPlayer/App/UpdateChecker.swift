import AppKit

/// "Check for Updates…": compares the latest GitHub release with this build and, when it is newer,
/// downloads its `NullPlayer.dmg` to Downloads and opens it. The user drags the app across themselves.
@MainActor
enum UpdateChecker {
    enum Outcome: Equatable {
        case failed(String)
        case upToDate
        case available(tag: String, dmg: URL)
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }
        let tagName: String
        let assets: [Asset]
    }

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/ad-repo/nullplayer/releases/latest")!
    private static let activityID = "update-download"
    /// Covers the check and any download it starts, so a second click can't stack alerts or downloads.
    private static var busy = false

    static func checkNow() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            var request = URLRequest(url: latestReleaseURL, timeoutInterval: 10)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let result: Outcome
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                result = outcome(data: data, statusCode: status, current: BundleHelper.appVersion)
            } catch {
                result = .failed(error.localizedDescription)
            }
            await present(result)
        }
    }

    /// The pure decision behind the alert, from GitHub's `releases/latest` reply.
    nonisolated static func outcome(data: Data, statusCode: Int, current: String) -> Outcome {
        guard statusCode == 200 else { return .failed("GitHub answered with HTTP \(statusCode).") }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let release = try? decoder.decode(Release.self, from: data) else {
            return .failed("GitHub's reply could not be read.")
        }
        guard isNewer(release.tagName, than: current) else { return .upToDate }
        guard let dmg = release.assets.first(where: { $0.name == "NullPlayer.dmg" }) else {
            return .failed("Release \(release.tagName) has no NullPlayer.dmg.")
        }
        return .available(tag: release.tagName, dmg: dmg.browserDownloadUrl)
    }

    /// True when `latest` is a higher version than `current` ("0.34.10" > "0.34.9"; a leading "v" is ignored).
    /// A suffix like "-rc1" would sort above the plain version; `releases/latest` never returns a prerelease.
    nonisolated static func isNewer(_ latest: String, than current: String) -> Bool {
        let trimmed = latest.hasPrefix("v") ? String(latest.dropFirst()) : latest
        return trimmed.compare(current, options: .numeric) == .orderedDescending
    }

    private static func present(_ outcome: Outcome) async {
        let current = BundleHelper.appVersion
        switch outcome {
        case .failed(let reason):
            showAlert("Couldn't check for updates", reason, style: .warning)
        case .upToDate:
            showAlert("nullPlayer is up to date", "Version \(current) is the latest release.")
        case .available(let tag, let dmg):
            let response = showAlert("nullPlayer \(tag) is available",
                                     "You have version \(current). Homebrew users can run `brew upgrade nullplayer` instead.",
                                     buttons: ["Download", "Later"])
            if response == .alertFirstButtonReturn { await download(dmg, tag: tag) }
        }
    }

    private static func download(_ dmg: URL, tag: String) async {
        ActivityCenter.shared.show(id: activityID, message: "Downloading nullPlayer \(tag)…")
        defer { ActivityCenter.shared.hide(id: activityID) }
        do {
            let (temp, response) = try await URLSession.shared.download(from: dmg)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let downloads = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            let target = downloads.appendingPathComponent("NullPlayer-\(tag).dmg")
            try? FileManager.default.removeItem(at: target)  // an earlier download of this same release
            try FileManager.default.moveItem(at: temp, to: target)
            NSWorkspace.shared.open(target)
        } catch {
            showAlert("Couldn't download nullPlayer \(tag)", error.localizedDescription, style: .warning)
        }
    }

    @discardableResult
    private static func showAlert(_ title: String, _ text: String, style: NSAlert.Style = .informational,
                                  buttons: [String] = []) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        // A bare SPM executable has no bundle icon, so NSAlert would fall back to a folder.
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        buttons.forEach { alert.addButton(withTitle: $0) }
        // Compact mode runs as an accessory app; without this the alert can open behind other windows.
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
