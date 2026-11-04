import Foundation

/// Which of a skin's `.lng` files its `@Lng:N;` captions read, as AIMP picks them: the user's
/// language, then English for any caption that translation leaves out. A `.lng` names no locale;
/// AIMP matches it by file name to its own language pack (`Russian.lng`, `Espanol-AR.lng`), so the
/// Mac's preferred languages are mapped to those names here.
enum AIMPSkinLanguage {
    /// AIMP's language file names (lowercased, without `.lng`) for one preferred-language
    /// identifier (`ru`, `pt-BR`, `zh-Hant-HK`), most specific first.
    static func fileNames(for identifier: String) -> [String] {
        let language = Locale.Language(identifier: identifier)
        let region = language.region?.identifier
        let script = language.script?.identifier
        switch language.languageCode?.identifier {
        case "en": return ["english"]
        case "ru": return ["russian"]
        case "uk": return ["ukrainian", "ukranian"]
        case "pl": return ["polish"]
        case "tr": return ["turkish"]
        case "it": return ["italian"]
        case "ja": return ["japanese"]
        case "ko": return ["korean"]
        case "zh":
            if script == "Hans" || (script == nil && ["CN", "SG"].contains(region ?? "CN")) { return ["simplified_chinese"] }
            return ["HK", "MO"].contains(region) ? ["hongkongese", "traditional_chinese"] : ["traditional_chinese", "hongkongese"]
        case "es":
            let byRegion = ["AR": "espanol-ar", "CO": "espanol-col", "ES": "espanol-es"]
            let first = region.flatMap { byRegion[$0] }
            return [first ?? "espanol-es"] + ["espanol-es", "espanol-ar", "espanol-col"].filter { $0 != first ?? "espanol-es" }
        case "pt": return region == "BR" ? ["brazilian", "portuguese"] : ["portuguese", "brazilian"]
        case "sr": return script == "Latn" ? ["serbian_latin", "serbian"] : ["serbian_cyrillic", "serbian"]
        case "et": return ["eesti", "estonian"]
        case "nl": return ["nederlands", "dutch"]
        case "de": return ["german"]
        case "fr": return ["french"]
        case "cs": return ["czech"]
        case "sk": return ["slovak"]
        case "sl": return ["slovenian"]
        case "hu": return ["hungarian"]
        case "fi": return ["finnish"]
        case "ca": return ["catalan"]
        case "bg": return ["bulgarian"]
        case "hr": return ["croatian"]
        case "ro": return ["romanian"]
        case "el": return ["greek"]
        case "he": return ["hebrew"]
        case "id": return ["indonesian"]
        case "uz": return ["uzbek"]
        case "tk": return ["turkmen"]
        case "tt": return ["tatar"]
        case "az": return ["azeri"]
        case "hy": return ["armenian"]
        default: return []
        }
    }

    /// The file `available` (lowercased names without `.lng`) holds for the first preferred
    /// language that has one; nil when none does (English alone is read).
    static func choose(available: Set<String>, preferred: [String]) -> String? {
        for identifier in preferred {
            if let name = fileNames(for: identifier).first(where: available.contains) { return name }
        }
        return nil
    }

    /// A `.lng`'s strings (UTF-16, an INI as AIMP writes them), by key, whatever section holds
    /// them, each as written; a key set twice keeps its last value.
    static func strings(_ data: Data, name: String = "") throws -> [String: String] {
        let ini = try AIMPSkinINI(utf16: data, name: name)
        var strings: [String: String] = [:]
        for section in ini.sections {
            for line in section.writtenLines { strings[line.key] = line.value }
        }
        return strings
    }

    /// The captions the skin reads in `preferred`'s language: English, with the chosen
    /// translation laid over it caption by caption (many translate only some). A file that does
    /// not read is a finding (`documents`), and reads as no strings.
    static func strings(in documents: AIMPSkinDocuments, preferred: [String]) -> [String: String] {
        let archive = documents.archive
        var files: [String: AIMPSkinArchive.Entry] = [:]
        for entry in archive.entries.values {
            let name = (entry.name as NSString).lastPathComponent.lowercased()
            guard name.hasSuffix(".lng") else { continue }
            files[String(name.dropLast(4))] = entry
        }
        func read(_ name: String) -> [String: String] {
            files[name].flatMap { entry in documents.reading(entry.name) { try strings(archive.payload(entry), name: entry.name) } } ?? [:]
        }
        var result = read("english")
        if let chosen = choose(available: Set(files.keys), preferred: preferred), chosen != "english" {
            result.merge(read(chosen)) { _, translated in translated }
        }
        return result
    }

    /// Every `@Lng:key;` in `text` (`@Lng:53; - @Lng:36;`) through the skin's strings, else AIMP's
    /// own (`playerString`); a key neither has reads as nothing, as a Delphi `ReadString` with no
    /// default does (Kantaris-Teyp 1.9's colour captions are in its Turkish file alone).
    static func expanded(_ text: String, strings: [String: String]) -> String {
        var out = "", rest = text[...]
        while let start = rest.range(of: "@Lng:"), let end = rest.range(of: ";", range: start.upperBound..<rest.endIndex) {
            let key = String(rest[start.upperBound..<end.lowerBound])
            out += rest[..<start.lowerBound]
            out += strings[key] ?? playerString(key) ?? ""
            rest = rest[end.upperBound...]
        }
        out += rest
        // Leading spaces are the designer's: they clear a glyph before the words (Unsquareable's radios).
        out = out.trimmingCharacters(in: .newlines)
        while out.last?.isWhitespace == true { out.removeLast() }
        return out
    }

    /// A string of AIMP's own language files, which skins name by section and key
    /// (`@Lng:Actions\QuickSearch;`, `@Lng:AIMP\acPlayerRepeat;`: Soot's search box and hints).
    /// Those files are AIMP's, not the skin's: the key's last part reads as words ("Quick search",
    /// "Player repeat"). Nil for the skin's own numbered strings.
    static func playerString(_ key: String) -> String? {
        guard let name = key.split(separator: "\\").last, key.contains("\\") else { return nil }
        // An action's or control's prefix (`acPlayerRepeat`, `btnReset`, `miMLBookmarks`) is not a word.
        let bare = name.drop { $0.isLowercase }.isEmpty ? Substring(name) : name.drop { $0.isLowercase }
        var words: [String] = []
        for character in bare {
            if character.isUppercase, let last = words.last?.last, !last.isUppercase { words.append("") }
            if words.isEmpty { words.append("") }
            words[words.count - 1].append(character)
        }
        let sentence = words.enumerated().map { i, word in
            i == 0 || word.count > 1 && word.allSatisfy(\.isUppercase) ? word : word.lowercased()
        }.joined(separator: " ")
        return sentence.isEmpty ? nil : sentence
    }
}
