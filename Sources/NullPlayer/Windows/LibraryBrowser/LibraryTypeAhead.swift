import Foundation

/// Typing over the list jumps to the first row whose title starts with what was typed. The typed
/// text clears after a second without a key.
@MainActor
final class LibraryTypeAhead {
    private var query = ""
    private var timer: Timer?

    /// Apply a key: Escape clears, Delete drops the last character, and letters, digits and spaces
    /// are added. Returns the row to select, or nil when the selection stays.
    func handle(keyCode: UInt16, characters: String, in items: [LibraryBrowserItem]) -> Int? {
        switch keyCode {
        case 53: // Escape
            cancel()
            return nil
        case 51: // Delete
            guard !query.isEmpty else { return nil }
            query.removeLast()
        default:
            guard characters.rangeOfCharacter(from: .alphanumerics) != nil ||
                  characters.rangeOfCharacter(from: .whitespaces) != nil else { return nil }
            query += characters
        }

        let lowered = query.lowercased()
        guard !lowered.isEmpty else { return nil }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.query = "" }
        }
        return items.firstIndex { $0.matchesTypeAhead(lowered) }
    }

    func cancel() {
        query = ""
        timer?.invalidate()
        timer = nil
    }
}

/// The letters a row files under, for the alphabet index and type-ahead.
extension LibraryBrowserItem {
    /// The alphabet-index letter this row files under; a Subsonic artist uses the server's index letter.
    var sortLetter: String {
        if case .subsonicArtist(let artist) = type, let letter = Self.normalizedIndexLetter(artist.indexLetter) {
            return letter
        }
        return Self.sortLetter(forTitle: title)
    }

    /// The alphabet-index letter a title files under, ignoring a leading article as the sort does.
    static func sortLetter(forTitle title: String) -> String {
        let sortTitle = LibraryTextSorter.normalized(title, ignoreLeadingArticles: true).uppercased()
        guard let firstChar = sortTitle.first else { return "#" }
        return firstChar.isLetter ? String(firstChar) : "#"
    }

    /// A raw Subsonic `indexLetter` as a single uppercase letter, or nil if blank.
    static func normalizedIndexLetter(_ raw: String?) -> String? {
        guard let first = raw?.trimmingCharacters(in: .whitespaces).first else { return nil }
        return String(first).uppercased()
    }

    /// Whether type-ahead `query` (lowercased) picks this row: the start of its title, its start
    /// without a leading article ("beat" → "The Beatles"), or its canonical form ("the at" →
    /// "Atlas Moth, The").
    func matchesTypeAhead(_ query: String) -> Bool {
        let lower = title.lowercased()
        if lower.hasPrefix(query) { return true }
        if LibraryTextSorter.normalized(title, ignoreLeadingArticles: true).lowercased().hasPrefix(query) { return true }
        for suffix in [", the", ", an", ", a"] where lower.hasSuffix(suffix) {
            let article = String(suffix.dropFirst(2))
            return (article + " " + lower.dropLast(suffix.count)).hasPrefix(query)
        }
        return false
    }
}
