import Foundation

/// A structured, queryable per-skin compatibility report.
///
/// Loading a `.wal` (and running its scripts) produces a stream of `WalDiagnostic`s plus a tally of
/// unsupported MAKI method calls. On their own those are a flat log; this report groups them into
/// stable, machine-readable categories with counts so the DEBUG UI, tests, and Phase 7.3 demand
/// analysis can all consume the same shape. It records *what a skin needs that we don't fully provide*
/// without changing load or execution behavior — a skin that loads with warnings is `.degraded`, one
/// whose load threw is `.unsupported`, and a clean load with no gaps is `.full`.
struct WinampModernCompatibilityReport: Codable, Equatable {
    /// The coarse compatibility verdict, worst-case across all findings.
    enum Level: String, Codable, Comparable {
        /// Loaded and ran with no compatibility gaps recorded.
        case full
        /// Loaded and is usable, but some resources/groups/methods degraded (warnings only).
        case degraded
        /// Did not load — a hard failure diagnostic was recorded.
        case unsupported

        private var rank: Int {
            switch self {
            case .full: return 0
            case .degraded: return 1
            case .unsupported: return 2
            }
        }
        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rank < rhs.rank }
    }

    /// Stable buckets a finding maps into. Kept coarse so the set is durable across runtime growth.
    enum Category: String, Codable, CaseIterable {
        case archive            // archive/container structure and security limits
        case resources          // missing/oversized bitmaps, fonts, cursors, colors
        case groups             // missing / unresolved groupdefs and inheritance
        case scripts            // MAKI parse/binding/budget problems
        case unsupportedMethods // MAKI methods with no host implementation
        case other
    }

    struct Finding: Codable, Equatable {
        let category: Category
        let code: String
        let severity: WalDiagnosticSeverity
        let message: String
        let location: String?
        /// How many times this exact finding was recorded (diagnostics are de-duplicated by identity).
        var count: Int
    }

    let level: Level
    let findings: [Finding]

    /// Number of findings in a category (summed over their counts).
    func occurrences(in category: Category) -> Int {
        findings.filter { $0.category == category }.reduce(0) { $0 + $1.count }
    }

    var hasBlockingFailure: Bool { findings.contains { $0.severity == .error } }

    /// Build a report from load-time diagnostics, an optional runtime unsupported-method tally, and
    /// whether the load ultimately succeeded (a thrown load records the failure diagnostics but ends
    /// `.unsupported`).
    init(diagnostics: [WalDiagnostic],
         unsupportedMethodCalls: [String: Int] = [:],
         loadSucceeded: Bool = true) {
        var findings: [Finding] = []

        // Diagnostics de-duplicate to a (code, message, location) identity with a running count.
        var index: [String: Int] = [:]
        for diagnostic in diagnostics {
            let category = Self.category(for: diagnostic.code)
            let key = "\(diagnostic.code.rawValue)\u{1}\(diagnostic.message)\u{1}\(diagnostic.location?.description ?? "")"
            if let existing = index[key] {
                findings[existing].count += 1
            } else {
                index[key] = findings.count
                findings.append(Finding(category: category,
                                        code: diagnostic.code.rawValue,
                                        severity: diagnostic.severity,
                                        message: diagnostic.message,
                                        location: diagnostic.location?.description,
                                        count: 1))
            }
        }

        for (method, count) in unsupportedMethodCalls.sorted(by: { $0.key < $1.key }) {
            findings.append(Finding(category: .unsupportedMethods,
                                    code: WalDiagnosticCode.unsupportedScriptCapability.rawValue,
                                    severity: .warning,
                                    message: "MAKI method '\(method)' is not implemented; calls are no-ops.",
                                    location: nil,
                                    count: count))
        }

        self.findings = findings
        if !loadSucceeded || findings.contains(where: { $0.severity == .error }) {
            self.level = .unsupported
        } else if findings.isEmpty {
            self.level = .full
        } else {
            self.level = .degraded
        }
    }

    private static func category(for code: WalDiagnosticCode) -> Category {
        switch code {
        case .invalidArchive, .unsupportedContainer, .entryLimitExceeded, .entryTooLarge,
             .totalSizeExceeded, .compressionRatioExceeded, .unsafePath, .symbolicLink,
             .caseCollision, .invalidRoot:
            return .archive
        case .resourceMissing, .resourceEscapesVFS, .invalidImageResource,
             .imageDimensionsExceeded, .fontSizeExceeded, .missingRequiredMount:
            return .resources
        case .missingGroupDefinition, .groupInheritanceCycle, .groupInheritanceDepthExceeded,
             .duplicateIdentifier:
            return .groups
        case .invalidScript, .unsupportedScriptCapability, .scriptBudgetExceeded:
            return .scripts
        case .unresolvedPathVariable, .includeCycle, .includeDepthExceeded, .xmlDepthExceeded,
             .expandedNodeLimitExceeded, .malformedXML, .unknownComponent, .unsupportedElement:
            return .other
        }
    }

    /// A compact one-line-per-category summary for DEBUG logging.
    var summary: String {
        var lines = ["Winamp Modern compatibility: \(level.rawValue)"]
        for category in Category.allCases {
            let count = occurrences(in: category)
            if count > 0 { lines.append("  \(category.rawValue): \(count)") }
        }
        return lines.joined(separator: "\n")
    }
}
