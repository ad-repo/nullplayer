import AppKit

/// "Check for Updates…": compares the latest GitHub release with this build and offers the download.
/// Check-only by design; the user installs the DMG (or runs `brew upgrade`) themselves.
enum UpdateChecker {
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/ad-repo/nullplayer/releases/latest")!

    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
    }

    static func checkNow() {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, error in
            let release = data.flatMap { try? JSONDecoder().decode(Release.self, from: $0) }
            DispatchQueue.main.async { present(release, error: error) }
        }.resume()
    }

    /// True when `latest` is a higher version than `current` ("0.34.10" > "0.34.9"; a leading "v" is ignored).
    static func isNewer(_ latest: String, than current: String) -> Bool {
        let trimmed = latest.hasPrefix("v") ? String(latest.dropFirst()) : latest
        return trimmed.compare(current, options: .numeric) == .orderedDescending
    }

    private static func present(_ release: Release?, error: Error?) {
        let alert = NSAlert()
        // A bare SPM executable has no bundle icon, so NSAlert would fall back to a folder.
        alert.icon = NSApp.applicationIconImage
        let current = BundleHelper.appVersion
        guard let release else {
            alert.alertStyle = .warning
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = error?.localizedDescription ?? "GitHub did not return a release."
            alert.runModal()
            return
        }
        guard isNewer(release.tag_name, than: current) else {
            alert.messageText = "nullPlayer is up to date"
            alert.informativeText = "Version \(current) is the latest release."
            alert.runModal()
            return
        }
        alert.messageText = "nullPlayer \(release.tag_name) is available"
        alert.informativeText = "You have version \(current). Homebrew users can run `brew upgrade nullplayer`."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.html_url)
        }
    }
}
