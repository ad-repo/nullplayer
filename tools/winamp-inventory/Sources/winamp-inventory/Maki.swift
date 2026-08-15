import Foundation

/// Minimal MAKI (`.maki`) header + symbol inventory. This is NOT a full opcode
/// disassembler: every ClassicPro script ships with readable `.m` source, so the
/// bytecode is the fallback authority. What we extract here is the structured header
/// (magic/version/class-GUID table) plus the length-prefixed symbol pool (imported
/// method names and string constants), which is what the compatibility matrix needs.
struct MakiInfo {
    let file: String
    let valid: Bool
    let version: String
    let classGuidCount: Int
    let distinctGuids: [String]
    var methodNames: [String] = []      // camelCase identifiers (API calls)
    var stringConstants: [String] = []  // ids, actions, guids, tooltips, params
    let byteSize: Int
}

enum Maki {
    static func parse(_ url: URL, relRoot: String) -> MakiInfo {
        let rel = String(url.path.dropFirst(relRoot.count))
        guard let data = try? Data(contentsOf: url), data.count >= 12,
              data[0] == 0x46, data[1] == 0x47 else {       // "FG"
            return MakiInfo(file: rel, valid: false, version: "-", classGuidCount: 0,
                            distinctGuids: [], byteSize: 0)
        }
        func u16(_ o: Int) -> Int { Int(data[o]) | (Int(data[o+1]) << 8) }
        func u32(_ o: Int) -> Int { Int(data[o]) | (Int(data[o+1]) << 8) | (Int(data[o+2]) << 16) | (Int(data[o+3]) << 24) }

        let ver = u16(2)
        let nTypes = u32(8)
        let versionStr = String(format: "0x%04x", ver)

        // Class-GUID table: nTypes * 16 bytes starting at offset 12.
        var guids: [String] = []
        let guidStart = 12
        let guidEnd = guidStart + nTypes * 16
        if nTypes >= 0, nTypes < 100_000, guidEnd <= data.count {
            for k in 0..<nTypes {
                let base = guidStart + k * 16
                guids.append(guidString(data, base))
            }
        }

        var info = MakiInfo(file: rel, valid: true, version: versionStr,
                            classGuidCount: nTypes, distinctGuids: Array(Set(guids)).sorted(),
                            byteSize: data.count)

        // Resilient symbol scan over the region after the GUID table: MAKI stores both
        // imported method names and string constants as u16-length-prefixed ASCII.
        var seenMethods = Set<String>()
        var seenConsts = Set<String>()
        var i = max(guidEnd, 12)
        let n = data.count
        while i + 2 < n {
            let len = u16(i)
            if len >= 3 && len <= 96 && i + 2 + len <= n {
                let slice = data.subdata(in: (i + 2)..<(i + 2 + len))
                if let s = asciiString(slice) {
                    if isMethodName(s) { seenMethods.insert(s) }
                    else if isConstant(s) { seenConsts.insert(s) }
                    i += 2 + len
                    continue
                }
            }
            i += 1
        }
        info.methodNames = seenMethods.sorted()
        info.stringConstants = seenConsts.sorted()
        return info
    }

    private static func guidString(_ d: Data, _ o: Int) -> String {
        func h(_ r: Range<Int>) -> String { r.map { String(format: "%02X", d[$0]) }.joined() }
        // Winamp GUIDs are stored little-endian in the first three groups.
        let d1 = [o+3, o+2, o+1, o].map { String(format: "%02X", d[$0]) }.joined()
        let d2 = [o+5, o+4].map { String(format: "%02X", d[$0]) }.joined()
        let d3 = [o+7, o+6].map { String(format: "%02X", d[$0]) }.joined()
        let d4 = h((o+8)..<(o+10))
        let d5 = h((o+10)..<(o+16))
        return "\(d1)-\(d2)-\(d3)-\(d4)-\(d5)"
    }

    private static func asciiString(_ d: Data) -> String? {
        for b in d where b < 0x20 || b > 0x7E { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    private static func isMethodName(_ s: String) -> Bool {
        guard let first = s.first, first.isLowercase || first == "_" else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } && s.count >= 3
    }

    private static func isConstant(_ s: String) -> Bool {
        // Anything that isn't a bare identifier: paths, guids, actions, tooltips, params.
        s.contains(where: { $0 == " " || $0 == ":" || $0 == "{" || $0 == "." || $0 == "/" || $0 == "@" })
            || (s.first?.isUppercase ?? false)
    }
}
