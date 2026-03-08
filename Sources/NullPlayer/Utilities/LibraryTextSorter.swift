import Foundation

enum LibraryTextSorter {
    static func normalized(_ text: String, ignoreLeadingArticles: Bool = true) -> String {
        guard ignoreLeadingArticles else { return text }
        let upper = text.uppercased()
        for prefix in ["THE ", "AN ", "A "] where upper.hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count))
        }
        return text
    }

    static func compare(
        _ lhs: String,
        _ rhs: String,
        ignoreLeadingArticles: Bool = true
    ) -> ComparisonResult {
        let left = normalized(lhs, ignoreLeadingArticles: ignoreLeadingArticles)
        let right = normalized(rhs, ignoreLeadingArticles: ignoreLeadingArticles)
        return left.compare(
            right,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive, .numeric],
            range: nil,
            locale: .current
        )
    }

    static func areInOrder(
        _ lhs: String,
        _ rhs: String,
        ascending: Bool,
        ignoreLeadingArticles: Bool = true
    ) -> Bool {
        let result = compare(lhs, rhs, ignoreLeadingArticles: ignoreLeadingArticles)
        return ascending ? result == .orderedAscending : result == .orderedDescending
    }
}
