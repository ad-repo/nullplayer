import XCTest
import AppKit
import CoreText
import ZIPFoundation
@testable import NullPlayer

/// The 2026-08-16 crash report — an abort inside `NSString.size(withAttributes:)` while running
/// cPro-Bento:
///
///     -[__NSPlaceholderDictionary initWithObjects:forKeys:count:]: attempt to insert nil object
///
/// `state-of-the-engine.md` recorded the fix as "plausible, not proven", because neither the dump
/// harness nor `WinampModernCrashRepro` could reproduce it. This file resolves that, by measuring
/// the two things the reasoning rested on rather than arguing them.
///
/// **1. The mechanism is a non-optional-typed nil, not a nameless font.** That exact abort string is
/// produced only by a real nil reaching the ObjC dictionary bridge — which in Swift means a value
/// whose *static type* is non-optional but whose runtime value is null, the shape an ObjC
/// constructor imported as non-optional can still return. A Swift `Optional.none` boxed in `Any`
/// bridges to `NSNull` and aborts differently (`-[NSNull pointSize]: unrecognized selector`), so the
/// reported string identifies the mechanism uniquely. The defence is therefore that
/// `WasabiTextMetrics.font(identifier:size:traits:)` is typed `NSFont?` and every constructor result
/// is assigned to an optional before use.
///
/// **2. The PostScript-name guard could never have fired — in either version.** It was written as
/// `CTFontCopyPostScriptName(created) == nil`, which the compiler reports as always false, and
/// repaired in 0.30.0 to test the name for `isEmpty`. `testCoreGraphicsSynthesizesANameForANamelessFont`
/// shows the repair is equally inert: CoreGraphics invents a name for a font that has none. The
/// guard was removed rather than repaired again, and that test is what will say so if a future macOS
/// changes its mind.
final class WinampModernNamelessFontTests: XCTestCase {

    // MARK: - What CoreGraphics does with a font that has no name

    /// Three ways to take a font's name away, and CoreGraphics answers all three with a synthesized
    /// `font<hex>` name. This is the measurement that retires the name-based guard: no font that
    /// survives `CGFont(provider)` can report an empty PostScript name, so a check for one is dead
    /// code no matter how it is spelled.
    func testCoreGraphicsSynthesizesANameForANamelessFont() throws {
        for (label, data) in [("an empty name table", try Self.fontWithEmptyNameTable()),
                              ("no name table at all", try Self.fontWithNoNameTable()),
                              ("a zero-length PostScript record", try Self.fontWithEmptyPostScriptRecord())] {
            let provider = try XCTUnwrap(CGDataProvider(data: data as CFData), label)
            let cgFont = try XCTUnwrap(CGFont(provider), "CoreGraphics still accepts \(label)")
            let name = CTFontCopyPostScriptName(CTFontCreateWithGraphicsFont(cgFont, 12, nil, nil)) as String
            XCTAssertFalse(name.isEmpty,
                           "CoreGraphics synthesizes a PostScript name for \(label) — a check for an "
                           + "empty name can never fire, which is why the guard was removed")
        }
    }

    /// The other end of the range: bytes that are not a font are refused outright, so they never
    /// reach `CTFontCreateWithGraphicsFont` either.
    func testCoreGraphicsRejectsBytesThatAreNotAFont() {
        let provider = CGDataProvider(data: Data(repeating: 0x41, count: 4096) as CFData)
        XCTAssertNil(provider.flatMap { CGFont($0) },
                     "garbage is refused before a font object exists")
    }

    // MARK: - The engine's own path

    /// End to end: a skin that declares a `truetypefont` whose name table has been stripped must
    /// load, resolve a usable face, and measure text through it without taking the process down.
    /// This is the case the crash report describes, constructed rather than waited for.
    func testASkinWhoseFontHasNoNameStillMeasuresText() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <elements>
            <truetypefont id="player.namelessfont" file="nameless.ttf"/>
          </elements>
          <container id="main">
            <layout id="normal" w="200" h="40">
              <text id="ticker" text="0:00 / 3:21" font="player.namelessfont" x="0" y="0" w="200" h="40"/>
            </layout>
          </container>
        </WasabiXML>
        """, resources: ["nameless.ttf": try Self.fontWithEmptyNameTable()])

        let metrics = WasabiTextMetrics(loadedSkin: loaded)
        addTeardownBlock { metrics.teardown() }

        let font = try XCTUnwrap(metrics.font(identifier: "player.namelessfont", size: 12),
                                 "a nameless font resolves to something usable rather than to nil")
        // The call from the crash report, on the object that would have made it. If the font were a
        // non-optional-typed nil this aborts the test process rather than failing the assertion.
        XCTAssertGreaterThan(metrics.measuredWidth(of: "0:00 / 3:21", font: font), 0,
                             "and text measures through it")
    }

    /// The invariant the defence actually rests on, asserted directly: whatever
    /// `font(identifier:size:traits:)` hands back is a genuine object, never a null wearing a
    /// non-optional type. `unsafeBitCast` to `Optional` is the only way to see the difference — a
    /// plain `!= nil` on the non-optional result is what the original guard did, and it is always
    /// true.
    func testResolvedFontsAreNeverANullWearingANonOptionalType() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <elements>
            <truetypefont id="player.namelessfont" file="nameless.ttf"/>
            <truetypefont id="player.missingfont" file="NOTSHIPPED.ttf"/>
          </elements>
          <container id="main"><layout id="normal" w="80" h="20"/></container>
        </WasabiXML>
        """, resources: ["nameless.ttf": try Self.fontWithEmptyNameTable()])

        let metrics = WasabiTextMetrics(loadedSkin: loaded)
        addTeardownBlock { metrics.teardown() }

        // A declared-but-nameless font, a declared-but-missing file, a bare family name the system
        // has, a family name nothing has, and no identifier at all: every way in.
        for identifier in ["player.namelessfont", "player.missingfont", "Monaco", "NoSuchFamilyXYZ", nil] {
            let font = try XCTUnwrap(metrics.font(identifier: identifier, size: 12),
                                     "font(identifier: \(identifier ?? "nil")) falls back rather than failing")
            let asPointer = unsafeBitCast(font, to: UnsafeRawPointer?.self)
            XCTAssertNotNil(asPointer,
                            "font(identifier: \(identifier ?? "nil")) returned a null typed as NSFont — "
                            + "that value in an attributes dictionary is the 2026-08-16 abort")
            XCTAssertGreaterThan((("0:00" as NSString).size(withAttributes: [.font: font])).width, 0,
                                 "and it survives the call the crash report names")
        }
    }

    // MARK: - Building a font with no name

    /// A real TrueType face with its `name` table rewritten to hold zero records. Built from a system
    /// font so the rest of the tables stay valid — the point is a font CoreGraphics *accepts* and
    /// that has no name of its own, which a synthetic stub could not be.
    private static func fontWithEmptyNameTable() throws -> Data {
        try patchingSourceFont { bytes, record, offset, _ in
            // format 0, count 0, stringOffset 6 — well-formed, and naming nothing.
            bytes.replaceSubrange(offset..<(offset + 6), with: [0, 0, 0, 0, 0, 6])
            Self.writeU32(6, into: &bytes, at: record + 12)   // and the table is 6 bytes long
        }
    }

    /// The same face with the `name` table dropped from the table directory entirely.
    private static func fontWithNoNameTable() throws -> Data {
        try patchingSourceFont { bytes, record, _, directory in
            let last = 12 + (directory.count - 1) * 16
            for byte in 0..<16 { bytes[record + byte] = bytes[last + byte] }
            let remaining = directory.count - 1
            bytes[4] = UInt8(remaining >> 8)
            bytes[5] = UInt8(remaining & 0xFF)
        }
    }

    /// The same face keeping its `name` table, but with every nameID 6 (PostScript name) record given
    /// a zero-length string — the closest thing to a font that literally declares an empty name.
    private static func fontWithEmptyPostScriptRecord() throws -> Data {
        try patchingSourceFont { bytes, _, offset, _ in
            let count = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            for index in 0..<count {
                let record = offset + 6 + index * 12
                let nameID = Int(bytes[record + 6]) << 8 | Int(bytes[record + 7])
                if nameID == 6 { bytes[record + 8] = 0; bytes[record + 9] = 0 }
            }
        }
    }

    private struct TableRecord { let tag: String; let record: Int; let offset: Int }

    /// Monaco, with its `name` table handed to `patch`. Skips rather than fails if the system font
    /// is not where it has always been, so this file cannot become the reason a test run goes red on
    /// a machine that simply ships a different set of fonts.
    private static func patchingSourceFont(
        _ patch: (inout [UInt8], Int, Int, [TableRecord]) -> Void
    ) throws -> Data {
        let url = URL(fileURLWithPath: "/System/Library/Fonts/Monaco.ttf")
        guard let source = try? Data(contentsOf: url) else {
            throw XCTSkip("no system TrueType font to strip a name table from")
        }
        var bytes = [UInt8](source)
        func u16(_ offset: Int) -> Int { Int(bytes[offset]) << 8 | Int(bytes[offset + 1]) }
        func u32(_ offset: Int) -> Int {
            (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16)
                | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
        }
        let directory = (0..<u16(4)).map { index -> TableRecord in
            let record = 12 + index * 16
            return TableRecord(tag: String(bytes: bytes[record..<(record + 4)], encoding: .ascii) ?? "",
                               record: record, offset: u32(record + 8))
        }
        guard let name = directory.first(where: { $0.tag == "name" }) else {
            throw XCTSkip("the system font has no name table to strip")
        }
        patch(&bytes, name.record, name.offset, directory)
        return Data(bytes)
    }

    private static func writeU32(_ value: Int, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8((value >> 24) & 0xFF)
        bytes[offset + 1] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 3] = UInt8(value & 0xFF)
    }

    // MARK: - Fixture

    private func makeSkin(xml: String, resources: [String: Data] = [:]) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernNamelessFontTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Nameless-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in [("skin.xml", Data(xml.utf8))] + resources.map({ ($0.key, $0.value) }) {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }
}
