import Foundation

/// A skin's documents as one load reads them: each parsed when asked for, and what does not read
/// kept as a finding, so every reader of the load (`AIMPSkinLoader`, `AIMPSkinLegacy`) reports
/// failures one way. A document that is missing is nil without a finding; one that is there and
/// does not read is nil with one. Whether that is fatal is the caller's to say (`throwing`).
final class AIMPSkinDocuments {
    let archive: AIMPSkinArchive
    private(set) var findings: [AIMPSkinFinding] = []

    init(_ archive: AIMPSkinArchive) {
        self.archive = archive
    }

    /// `name`'s tree; nil when the skin has no such entry or it does not read (a finding).
    func node(_ name: String) -> AIMPNode? {
        guard let entry = archive.entry(name) else { return nil }
        return reading(entry.name) { try AIMPNode.parse(try archive.payload(entry), name: entry.name) }
    }

    /// The `<item>`s of a document with no root element (AIMP 2's `MainLayout.xml`: siblings),
    /// read inside one.
    func items(_ name: String) -> [AIMPNode]? {
        guard let entry = archive.entry(name) else { return nil }
        return reading(entry.name) {
            var text = String(decoding: try archive.payload(entry), as: UTF8.self)
            if let declaration = text.range(of: "?>") { text = String(text[declaration.upperBound...]) }
            return try AIMPNode.parse(Data("<layout>\(text)</layout>".utf8), name: entry.name).children("item")
        }
    }

    /// `name`'s tree, or the reason there is none, thrown: the finding its parse left, else
    /// `missing`'s. For a document the skin cannot do without (its main form).
    func throwing<T>(_ name: String, missing: String, _ read: (String) -> T?) throws -> T {
        let before = findings.count
        if let found = read(name) { return found }
        throw findings.count > before ? findings.removeLast() : AIMPSkinFinding(.noMainForm, missing)
    }

    /// A warning found reading something else (a picture that does not read).
    func record(_ finding: AIMPSkinFinding) { findings.append(finding) }

    /// `body`'s result, or nil with its failure kept as a finding.
    func reading<T>(_ name: String, _ body: () throws -> T) -> T? {
        do {
            return try body()
        } catch let finding as AIMPSkinFinding {
            record(finding)
        } catch {
            findings.append(AIMPSkinFinding(.entryUnreadable, "\(name): \(error)"))
        }
        return nil
    }
}
