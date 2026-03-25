import Foundation

enum AutoTagProvider: String, CaseIterable, Hashable {
    case discogs = "Discogs"
    case musicBrainz = "MusicBrainz"
}

struct AutoTagTrackPatch {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var genre: String?
    var year: Int?
    var trackNumber: Int?
    var discNumber: Int?
    var composer: String?
    var comment: String?
    var grouping: String?
    var bpm: Int?
    var musicalKey: String?
    var isrc: String?
    var copyright: String?
    var musicBrainzRecordingID: String?
    var musicBrainzReleaseID: String?
    var discogsReleaseID: Int?
    var discogsMasterID: Int?
    var discogsLabel: String?
    var discogsCatalogNumber: String?
    var artworkURL: String?

    var isEmpty: Bool {
        title == nil && artist == nil && album == nil && albumArtist == nil && genre == nil &&
        year == nil && trackNumber == nil && discNumber == nil && composer == nil &&
        comment == nil && grouping == nil && bpm == nil && musicalKey == nil && isrc == nil &&
        copyright == nil && musicBrainzRecordingID == nil && musicBrainzReleaseID == nil &&
        discogsReleaseID == nil && discogsMasterID == nil && discogsLabel == nil &&
        discogsCatalogNumber == nil && artworkURL == nil
    }

    func applying(to track: LibraryTrack) -> LibraryTrack {
        var updated = track
        if let title { updated.title = title }
        if let artist { updated.artist = artist }
        if let album { updated.album = album }
        if let albumArtist { updated.albumArtist = albumArtist }
        if let genre { updated.genre = genre }
        if let year { updated.year = year }
        if let trackNumber { updated.trackNumber = trackNumber }
        if let discNumber { updated.discNumber = discNumber }
        if let composer { updated.composer = composer }
        if let comment { updated.comment = comment }
        if let grouping { updated.grouping = grouping }
        if let bpm { updated.bpm = bpm }
        if let musicalKey { updated.musicalKey = musicalKey }
        if let isrc { updated.isrc = isrc }
        if let copyright { updated.copyright = copyright }
        if let musicBrainzRecordingID { updated.musicBrainzRecordingID = musicBrainzRecordingID }
        if let musicBrainzReleaseID { updated.musicBrainzReleaseID = musicBrainzReleaseID }
        if let discogsReleaseID { updated.discogsReleaseID = discogsReleaseID }
        if let discogsMasterID { updated.discogsMasterID = discogsMasterID }
        if let discogsLabel { updated.discogsLabel = discogsLabel }
        if let discogsCatalogNumber { updated.discogsCatalogNumber = discogsCatalogNumber }
        if let artworkURL { updated.artworkURL = artworkURL }
        return updated
    }

    mutating func mergeIn(_ other: AutoTagTrackPatch, preferredProvider: AutoTagProvider) {
        // Fields where Discogs should win when present.
        if preferredProvider == .discogs {
            if let v = other.genre { genre = v }
            if let v = other.discogsReleaseID { discogsReleaseID = v }
            if let v = other.discogsMasterID { discogsMasterID = v }
            if let v = other.discogsLabel { discogsLabel = v }
            if let v = other.discogsCatalogNumber { discogsCatalogNumber = v }
            if let v = other.artworkURL { artworkURL = v }
        }

        // Fields where MusicBrainz should win when present.
        if preferredProvider == .musicBrainz {
            if let v = other.musicBrainzRecordingID { musicBrainzRecordingID = v }
            if let v = other.musicBrainzReleaseID { musicBrainzReleaseID = v }
            if let v = other.trackNumber { trackNumber = v }
            if let v = other.discNumber { discNumber = v }
            if let v = other.title { title = v }
        }

        // Fill remaining gaps.
        title = title ?? other.title
        artist = artist ?? other.artist
        album = album ?? other.album
        albumArtist = albumArtist ?? other.albumArtist
        genre = genre ?? other.genre
        year = year ?? other.year
        trackNumber = trackNumber ?? other.trackNumber
        discNumber = discNumber ?? other.discNumber
        composer = composer ?? other.composer
        comment = comment ?? other.comment
        grouping = grouping ?? other.grouping
        bpm = bpm ?? other.bpm
        musicalKey = musicalKey ?? other.musicalKey
        isrc = isrc ?? other.isrc
        copyright = copyright ?? other.copyright
        musicBrainzRecordingID = musicBrainzRecordingID ?? other.musicBrainzRecordingID
        musicBrainzReleaseID = musicBrainzReleaseID ?? other.musicBrainzReleaseID
        discogsReleaseID = discogsReleaseID ?? other.discogsReleaseID
        discogsMasterID = discogsMasterID ?? other.discogsMasterID
        discogsLabel = discogsLabel ?? other.discogsLabel
        discogsCatalogNumber = discogsCatalogNumber ?? other.discogsCatalogNumber
        artworkURL = artworkURL ?? other.artworkURL
    }
}

struct AutoTagTrackCandidate {
    let id: String
    let displayTitle: String
    let subtitle: String
    let confidence: Double
    let providers: Set<AutoTagProvider>
    let mergeKey: String
    let patch: AutoTagTrackPatch
}

struct AutoTagAlbumCandidate {
    let id: String
    let displayTitle: String
    let subtitle: String
    let confidence: Double
    let providers: Set<AutoTagProvider>
    let mergeKey: String
    let albumPatch: AutoTagTrackPatch
    let perTrackPatches: [UUID: AutoTagTrackPatch]
    let releaseTracks: [AutoTagReleaseTrackHint]
}

struct AutoTagReleaseTrackHint {
    let title: String
    let trackNumber: Int?
    let discNumber: Int?
    let recordingID: String?
    let isrc: String?
}

enum AutoTagCandidateMerger {
    static func mergeTrackCandidates(_ input: [AutoTagTrackCandidate], limit: Int = 5) -> [AutoTagTrackCandidate] {
        var byKey: [String: AutoTagTrackCandidate] = [:]
        for candidate in input {
            if let existing = byKey[candidate.id], existing.confidence >= candidate.confidence {
                continue
            }
            byKey[candidate.id] = candidate
        }
        return byKey.values
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
                }
                return lhs.confidence > rhs.confidence
            }
            .prefix(limit)
            .map { $0 }
    }

    static func mergeAlbumCandidates(_ input: [AutoTagAlbumCandidate], limit: Int = 5) -> [AutoTagAlbumCandidate] {
        var byKey: [String: AutoTagAlbumCandidate] = [:]
        for candidate in input {
            if let existing = byKey[candidate.id], existing.confidence >= candidate.confidence {
                continue
            }
            byKey[candidate.id] = candidate
        }
        return byKey.values
            .sorted { lhs, rhs in
                let lhsMatchCount = lhs.perTrackPatches.count
                let rhsMatchCount = rhs.perTrackPatches.count
                if lhsMatchCount != rhsMatchCount {
                    return lhsMatchCount > rhsMatchCount
                }
                let lhsCoverage = lhs.releaseTracks.isEmpty ? 0.0 : Double(lhsMatchCount) / Double(lhs.releaseTracks.count)
                let rhsCoverage = rhs.releaseTracks.isEmpty ? 0.0 : Double(rhsMatchCount) / Double(rhs.releaseTracks.count)
                if lhsCoverage != rhsCoverage {
                    return lhsCoverage > rhsCoverage
                }
                if lhs.confidence == rhs.confidence {
                    return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
                }
                return lhs.confidence > rhs.confidence
            }
            .prefix(limit)
            .map { $0 }
    }
}

enum AutoTagTitleMatcher {
    private struct PreparedTitle {
        let exactVariants: Set<String>
        let baseVariants: Set<String>
        let compactExactVariants: Set<String>
        let compactBaseVariants: Set<String>
    }

    private static let separatorTokens = [" - ", " – ", " — ", " / ", " | ", " : ", " ~ "]
    private static let tokenExpansions: [String: String] = [
        "blvd": "boulevard",
        "rd": "road",
        "ave": "avenue",
        "hwy": "highway",
        "ctr": "center",
        "pt": "part",
        "vol": "volume"
    ]
    private static let noiseTokens: Set<String> = [
        "a", "an", "the",
        "bonus", "clean", "deluxe", "digital", "edition", "explicit",
        "mix", "mono", "radio", "remaster", "remastered", "reissue",
        "stereo", "track", "version"
    ]

    static func normalizedKeyComponent(_ input: String) -> String {
        let prepared = prepare(input)
        return prepared.baseVariants.max(by: { $0.count < $1.count }) ??
            prepared.exactVariants.max(by: { $0.count < $1.count }) ??
            ""
    }

    static func score(_ lhs: String, _ rhs: String) -> Double {
        let left = prepare(lhs)
        let right = prepare(rhs)

        if !left.exactVariants.isDisjoint(with: right.exactVariants) { return 1.0 }
        if !left.compactExactVariants.isDisjoint(with: right.compactExactVariants) { return 0.99 }
        if !left.baseVariants.isDisjoint(with: right.baseVariants) { return 0.97 }
        if !left.compactBaseVariants.isDisjoint(with: right.compactBaseVariants) { return 0.95 }

        let exactScore = bestFuzzyScore(left.exactVariants, right.exactVariants)
        let baseScore = bestFuzzyScore(left.baseVariants, right.baseVariants)
        return max(exactScore, baseScore)
    }

    private static func prepare(_ input: String) -> PreparedTitle {
        let canonical = input
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        var rawVariants: Set<String> = [canonical]
        rawVariants.insert(removeBracketedText(from: canonical))

        for separator in separatorTokens where canonical.contains(separator) {
            canonical
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .forEach { segment in
                    rawVariants.insert(segment)
                    rawVariants.insert(removeBracketedText(from: segment))
                }
        }

        let exactVariants = Set(rawVariants.map { normalize($0, aggressive: false) }.filter { !$0.isEmpty })
        let baseVariants = Set(rawVariants.map { normalize($0, aggressive: true) }.filter { !$0.isEmpty })

        return PreparedTitle(
            exactVariants: exactVariants,
            baseVariants: baseVariants.isEmpty ? exactVariants : baseVariants,
            compactExactVariants: Set(exactVariants.map(compact)),
            compactBaseVariants: Set((baseVariants.isEmpty ? exactVariants : baseVariants).map(compact))
        )
    }

    private static func bestFuzzyScore(_ lhsVariants: Set<String>, _ rhsVariants: Set<String>) -> Double {
        var best = 0.0
        for lhs in lhsVariants {
            for rhs in rhsVariants {
                best = max(best, fuzzyScore(lhs, rhs))
            }
        }
        return best
    }

    private static func fuzzyScore(_ lhs: String, _ rhs: String) -> Double {
        let lhsCompact = compact(lhs)
        let rhsCompact = compact(rhs)
        guard !lhsCompact.isEmpty, !rhsCompact.isEmpty else { return 0 }

        if lhsCompact.contains(rhsCompact) || rhsCompact.contains(lhsCompact) {
            let minLength = min(lhsCompact.count, rhsCompact.count)
            if minLength >= 5 {
                return 0.90
            }
        }

        let lhsTokens = Array(Set(lhs.split(separator: " ").map(String.init)))
        let rhsTokens = Array(Set(rhs.split(separator: " ").map(String.init)))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }

        let lhsSet = Set(lhsTokens)
        let rhsSet = Set(rhsTokens)
        let intersectionCount = Double(lhsSet.intersection(rhsSet).count)
        let unionCount = Double(lhsSet.union(rhsSet).count)
        let smallerCount = Double(min(lhsSet.count, rhsSet.count))
        let coverage = smallerCount > 0 ? intersectionCount / smallerCount : 0
        let jaccard = unionCount > 0 ? intersectionCount / unionCount : 0
        let bigram = diceCoefficient(lhsCompact, rhsCompact)

        var score = (coverage * 0.50) + (jaccard * 0.30) + (bigram * 0.20)
        if coverage == 1.0 && smallerCount >= 2 {
            score = max(score, 0.88)
        }
        if sharedPrefixTokenCount(lhs, rhs) >= 2 {
            score += 0.04
        }
        return min(score, 0.94)
    }

    private static func normalize(_ value: String, aggressive: Bool) -> String {
        var normalized = value
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "(?i)\\b(feat|ft|featuring)\\.?\\b", with: " featuring ", options: .regularExpression)
            .replacingOccurrences(of: #"^[\s._-]*((disc|cd)\s*)?\d+[\s._-]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[\[\](){}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)

        var tokens = normalized
            .split(separator: " ")
            .map(String.init)
            .map { tokenExpansions[$0] ?? $0 }

        if aggressive {
            tokens.removeAll { token in
                noiseTokens.contains(token) ||
                token.range(of: #"^(19|20)\d{2}$"#, options: .regularExpression) != nil ||
                token.range(of: #"^(disc|cd)\d+$"#, options: .regularExpression) != nil
            }
        }

        normalized = tokens.joined(separator: " ")
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeBracketedText(from value: String) -> String {
        value.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]|\{[^}]*\}"#, with: " ", options: .regularExpression)
    }

    private static func compact(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "")
    }

    private static func diceCoefficient(_ lhs: String, _ rhs: String) -> Double {
        let lhsBigrams = bigrams(lhs)
        let rhsBigrams = bigrams(rhs)
        guard !lhsBigrams.isEmpty, !rhsBigrams.isEmpty else {
            return lhs == rhs ? 1.0 : 0
        }

        var rhsCounts: [String: Int] = [:]
        for bigram in rhsBigrams {
            rhsCounts[bigram, default: 0] += 1
        }

        var matches = 0
        for bigram in lhsBigrams where (rhsCounts[bigram] ?? 0) > 0 {
            matches += 1
            rhsCounts[bigram, default: 0] -= 1
        }

        return (2.0 * Double(matches)) / Double(lhsBigrams.count + rhsBigrams.count)
    }

    private static func bigrams(_ value: String) -> [String] {
        let scalars = Array(value)
        guard scalars.count >= 2 else { return scalars.isEmpty ? [] : [value] }
        return (0..<(scalars.count - 1)).map { String(scalars[$0...($0 + 1)]) }
    }

    private static func sharedPrefixTokenCount(_ lhs: String, _ rhs: String) -> Int {
        let lhsTokens = lhs.split(separator: " ").map(String.init)
        let rhsTokens = rhs.split(separator: " ").map(String.init)
        var count = 0
        for (left, right) in zip(lhsTokens, rhsTokens) where left == right {
            count += 1
        }
        return count
    }
}

enum AutoTagTrackMapper {
    private static let acceptanceThreshold = 0.74

    static func map(releaseTracks: [AutoTagReleaseTrackHint], localTracks: [LibraryTrack]) -> [UUID: AutoTagReleaseTrackHint] {
        var mapped: [UUID: AutoTagReleaseTrackHint] = [:]
        var remainingReleaseIndices = Set(releaseTracks.indices)
        var remainingTrackIDs = Set(localTracks.map(\.id))
        let localByDiscTrack: [String: LibraryTrack] = Dictionary(uniqueKeysWithValues: localTracks.compactMap { track in
            guard let disc = track.discNumber, let trackNo = track.trackNumber else { return nil }
            return ("\(disc)-\(trackNo)", track)
        })

        let localByISRC: [String: LibraryTrack] = Dictionary(uniqueKeysWithValues: localTracks.compactMap { track in
            guard let isrc = normalizedCode(track.isrc) else { return nil }
            return (isrc, track)
        })

        for (releaseIndex, hint) in releaseTracks.enumerated() {
            if let isrc = normalizedCode(hint.isrc),
               let local = localByISRC[isrc],
               remainingTrackIDs.contains(local.id) {
                mapped[local.id] = hint
                remainingTrackIDs.remove(local.id)
                remainingReleaseIndices.remove(releaseIndex)
            }
        }

        for (releaseIndex, hint) in releaseTracks.enumerated() where remainingReleaseIndices.contains(releaseIndex) {
            if let disc = hint.discNumber, let trackNo = hint.trackNumber,
               let local = localByDiscTrack["\(disc)-\(trackNo)"], remainingTrackIDs.contains(local.id) {
                mapped[local.id] = hint
                remainingTrackIDs.remove(local.id)
                remainingReleaseIndices.remove(releaseIndex)
            }
        }

        struct MatchCandidate {
            let releaseIndex: Int
            let localTrackID: UUID
            let score: Double
        }

        var candidates: [MatchCandidate] = []
        for releaseIndex in remainingReleaseIndices {
            let releaseTrack = releaseTracks[releaseIndex]
            for (localIndex, localTrack) in localTracks.enumerated() where remainingTrackIDs.contains(localTrack.id) {
                let score = matchConfidence(
                    releaseTrack: releaseTrack,
                    localTrack: localTrack,
                    releaseIndex: releaseIndex,
                    localIndex: localIndex
                )
                if score >= acceptanceThreshold {
                    candidates.append(MatchCandidate(releaseIndex: releaseIndex, localTrackID: localTrack.id, score: score))
                }
            }
        }

        candidates.sort { lhs, rhs in
            if lhs.score == rhs.score {
                if lhs.releaseIndex == rhs.releaseIndex {
                    return lhs.localTrackID.uuidString < rhs.localTrackID.uuidString
                }
                return lhs.releaseIndex < rhs.releaseIndex
            }
            return lhs.score > rhs.score
        }

        for candidate in candidates
            where remainingReleaseIndices.contains(candidate.releaseIndex) &&
                  remainingTrackIDs.contains(candidate.localTrackID) {
            mapped[candidate.localTrackID] = releaseTracks[candidate.releaseIndex]
            remainingReleaseIndices.remove(candidate.releaseIndex)
            remainingTrackIDs.remove(candidate.localTrackID)
        }

        return mapped
    }

    static func matchConfidence(
        releaseTrack: AutoTagReleaseTrackHint,
        localTrack: LibraryTrack,
        releaseIndex: Int? = nil,
        localIndex: Int? = nil
    ) -> Double {
        if let releaseISRC = normalizedCode(releaseTrack.isrc),
           let localISRC = normalizedCode(localTrack.isrc),
           releaseISRC == localISRC {
            return 1.2
        }

        var score = AutoTagTitleMatcher.score(releaseTrack.title, localTrack.title)

        if let releaseDisc = releaseTrack.discNumber,
           let releaseTrackNumber = releaseTrack.trackNumber,
           let localDisc = localTrack.discNumber,
           let localTrackNumber = localTrack.trackNumber,
           releaseDisc == localDisc,
           releaseTrackNumber == localTrackNumber {
            score = max(score, 0.95)
        } else {
            if let releaseTrackNumber = releaseTrack.trackNumber,
               let localTrackNumber = localTrack.trackNumber,
               releaseTrackNumber == localTrackNumber {
                score += 0.10
            }
            if let releaseDisc = releaseTrack.discNumber,
               let localDisc = localTrack.discNumber,
               releaseDisc == localDisc {
                score += 0.04
            }
        }

        if let releaseIndex, let localIndex {
            let distance = abs(releaseIndex - localIndex)
            score += max(0, 0.08 - (Double(distance) * 0.02))
        }

        if let releaseTrackNumber = releaseTrack.trackNumber,
           let localTrackNumber = localTrack.trackNumber,
           releaseTrackNumber != localTrackNumber {
            score -= min(0.10, Double(abs(releaseTrackNumber - localTrackNumber)) * 0.02)
        }

        return max(0, min(score, 1.25))
    }

    private static func normalizedCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return normalized.isEmpty ? nil : normalized
    }
}

actor AutoTaggingService {
    static let shared = AutoTaggingService()

    private let discogsClient = DiscogsTaggingClient()
    private let musicBrainzClient = MusicBrainzTaggingClient()

    func searchTrackCandidates(for track: LibraryTrack) async -> [AutoTagTrackCandidate] {
        let query = buildTrackQuery(for: track)
        async let discogs = discogsTrackCandidates(for: track, query: query)
        async let musicBrainz = musicBrainzTrackCandidates(query: query)
        let combined = await discogs + musicBrainz
        return AutoTagCandidateMerger.mergeTrackCandidates(combined, limit: 5)
    }

    func searchAlbumCandidates(albumName: String, albumArtist: String?, tracks: [LibraryTrack]) async -> [AutoTagAlbumCandidate] {
        let query = buildAlbumQuery(albumName: albumName, albumArtist: albumArtist)
        async let discogs = discogsAlbumCandidates(albumName: albumName, tracks: tracks, query: query)
        async let musicBrainz = musicBrainzAlbumCandidates(tracks: tracks, query: query)
        let combined = await discogs + musicBrainz
        return AutoTagCandidateMerger.mergeAlbumCandidates(combined, limit: 5)
    }

    private func buildTrackQuery(for track: LibraryTrack) -> String {
        let artist = (track.artist ?? track.albumArtist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let album = (track.album ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var terms: [String] = []
        if !artist.isEmpty { terms.append(artist) }
        if !title.isEmpty { terms.append(title) }
        if !album.isEmpty { terms.append(album) }
        if terms.isEmpty {
            terms.append(track.url.deletingPathExtension().lastPathComponent)
        }
        return terms.joined(separator: " ")
    }

    private func buildAlbumQuery(albumName: String, albumArtist: String?) -> String {
        var terms: [String] = []
        if let albumArtist, !albumArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            terms.append(albumArtist)
        }
        let cleanedAlbum = albumName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedAlbum.isEmpty {
            terms.append(cleanedAlbum)
        }
        return terms.joined(separator: " ")
    }

    private func discogsTrackCandidates(for track: LibraryTrack, query: String) async -> [AutoTagTrackCandidate] {
        do {
            let results = try await discogsClient.searchReleases(query: query, limit: 5)
            var candidates: [AutoTagTrackCandidate] = []
            for (idx, result) in results.enumerated() {
                let release: DiscogsTaggingClient.ReleaseDetails
                do {
                    guard let fetched = try await discogsClient.fetchRelease(id: result.id) else { continue }
                    release = fetched
                } catch {
                    NSLog("AutoTaggingService: Discogs track detail fetch failed for release %d: %@", result.id, error.localizedDescription)
                    continue
                }
                let trackHint = release.bestTrackMatch(for: track.title)
                let mergeKey = normalizeKey([trackHint?.title ?? track.title, result.artistName, result.albumName])
                let confidence = max(0.10, result.confidence - (Double(idx) * 0.03))
                let patch = AutoTagTrackPatch(
                    title: trackHint?.title,
                    artist: result.artistName,
                    album: result.albumName,
                    albumArtist: result.artistName,
                    genre: release.primaryGenre,
                    year: release.year,
                    trackNumber: trackHint?.trackNumber,
                    discNumber: trackHint?.discNumber,
                    isrc: trackHint?.isrc,
                    discogsReleaseID: release.id,
                    discogsMasterID: release.masterID,
                    discogsLabel: release.primaryLabel,
                    discogsCatalogNumber: release.catalogNumber,
                    artworkURL: release.primaryArtworkURL
                )
                candidates.append(AutoTagTrackCandidate(
                    id: "discogs-track-\(release.id)",
                    displayTitle: "\(result.artistName ?? "Unknown Artist") - \(trackHint?.title ?? track.title)",
                    subtitle: [release.primaryGenre, release.year.map(String.init), "Discogs"].compactMap { $0 }.joined(separator: " • "),
                    confidence: confidence,
                    providers: [.discogs],
                    mergeKey: mergeKey,
                    patch: patch
                ))
            }
            return candidates
        } catch {
            NSLog("AutoTaggingService: Discogs track lookup failed: %@", error.localizedDescription)
            return []
        }
    }

    private func musicBrainzTrackCandidates(query: String) async -> [AutoTagTrackCandidate] {
        do {
            let results = try await musicBrainzClient.searchRecordings(query: query, limit: 5)
            return results.map { result in
                let mergeKey = normalizeKey([result.title, result.artistName, result.releaseTitle])
                let patch = AutoTagTrackPatch(
                    title: result.title,
                    artist: result.artistName,
                    album: result.releaseTitle,
                    albumArtist: result.artistName,
                    genre: result.genre,
                    year: result.year,
                    trackNumber: result.trackNumber,
                    discNumber: result.discNumber,
                    isrc: result.isrc,
                    musicBrainzRecordingID: result.recordingID,
                    musicBrainzReleaseID: result.releaseID,
                    artworkURL: result.releaseID.map { "https://coverartarchive.org/release/\($0)/front-500" }
                )
                return AutoTagTrackCandidate(
                    id: "mb-track-\(result.recordingID)",
                    displayTitle: "\(result.artistName ?? "Unknown Artist") - \(result.title)",
                    subtitle: [result.genre, result.year.map(String.init), "MusicBrainz"].compactMap { $0 }.joined(separator: " • "),
                    confidence: result.confidence,
                    providers: [.musicBrainz],
                    mergeKey: mergeKey,
                    patch: patch
                )
            }
        } catch {
            NSLog("AutoTaggingService: MusicBrainz track lookup failed: %@", error.localizedDescription)
            return []
        }
    }

    private func discogsAlbumCandidates(albumName: String, tracks: [LibraryTrack], query: String) async -> [AutoTagAlbumCandidate] {
        do {
            let results = try await discogsClient.searchReleases(query: query, limit: 5)
            var candidates: [AutoTagAlbumCandidate] = []
            for (idx, result) in results.enumerated() {
                let release: DiscogsTaggingClient.ReleaseDetails
                do {
                    guard let fetched = try await discogsClient.fetchRelease(id: result.id) else { continue }
                    release = fetched
                } catch {
                    NSLog("AutoTaggingService: Discogs album detail fetch failed for release %d: %@", result.id, error.localizedDescription)
                    continue
                }
                let mapped = AutoTagTrackMapper.map(releaseTracks: release.trackHints.map {
                    AutoTagReleaseTrackHint(title: $0.title, trackNumber: $0.trackNumber, discNumber: $0.discNumber, recordingID: nil, isrc: $0.isrc)
                }, localTracks: tracks)

                var perTrackPatches: [UUID: AutoTagTrackPatch] = [:]
                for (trackID, hint) in mapped {
                    perTrackPatches[trackID] = AutoTagTrackPatch(
                        title: hint.title,
                        trackNumber: hint.trackNumber,
                        discNumber: hint.discNumber,
                        isrc: hint.isrc
                    )
                }

                let mergeKey = normalizeKey([result.artistName, result.albumName])
                let confidence = max(0.10, result.confidence - (Double(idx) * 0.03))
                let albumPatch = AutoTagTrackPatch(
                    artist: result.artistName,
                    album: result.albumName,
                    albumArtist: result.artistName,
                    genre: release.primaryGenre,
                    year: release.year,
                    discogsReleaseID: release.id,
                    discogsMasterID: release.masterID,
                    discogsLabel: release.primaryLabel,
                    discogsCatalogNumber: release.catalogNumber,
                    artworkURL: release.primaryArtworkURL
                )
                candidates.append(AutoTagAlbumCandidate(
                    id: "discogs-album-\(release.id)",
                    displayTitle: "\(result.artistName ?? "Unknown Artist") - \(result.albumName ?? albumName)",
                    subtitle: [release.primaryGenre, release.year.map(String.init), "Discogs"].compactMap { $0 }.joined(separator: " • "),
                    confidence: confidence,
                    providers: [.discogs],
                    mergeKey: mergeKey,
                    albumPatch: albumPatch,
                    perTrackPatches: perTrackPatches,
                    releaseTracks: release.trackHints.map {
                        AutoTagReleaseTrackHint(title: $0.title, trackNumber: $0.trackNumber, discNumber: $0.discNumber, recordingID: nil, isrc: $0.isrc)
                    }
                ))
            }
            return candidates
        } catch {
            NSLog("AutoTaggingService: Discogs album lookup failed: %@", error.localizedDescription)
            return []
        }
    }

    private func musicBrainzAlbumCandidates(tracks: [LibraryTrack], query: String) async -> [AutoTagAlbumCandidate] {
        do {
            let results = try await musicBrainzClient.searchReleases(query: query, limit: 5)
            var candidates: [AutoTagAlbumCandidate] = []
            for result in results {
                let detail: MusicBrainzTaggingClient.ReleaseDetails
                do {
                    guard let fetched = try await musicBrainzClient.fetchReleaseDetails(id: result.releaseID) else { continue }
                    detail = fetched
                } catch {
                    NSLog("AutoTaggingService: MusicBrainz release detail fetch failed for %@: %@", result.releaseID, error.localizedDescription)
                    continue
                }
                let mapped = AutoTagTrackMapper.map(releaseTracks: detail.trackHints.map {
                    AutoTagReleaseTrackHint(title: $0.title, trackNumber: $0.trackNumber, discNumber: $0.discNumber, recordingID: $0.recordingID, isrc: $0.isrc)
                }, localTracks: tracks)

                var perTrackPatches: [UUID: AutoTagTrackPatch] = [:]
                for (trackID, hint) in mapped {
                    perTrackPatches[trackID] = AutoTagTrackPatch(
                        title: hint.title,
                        trackNumber: hint.trackNumber,
                        discNumber: hint.discNumber,
                        isrc: hint.isrc,
                        musicBrainzRecordingID: hint.recordingID,
                        musicBrainzReleaseID: result.releaseID
                    )
                }

                let mergeKey = normalizeKey([result.artistName, result.title])
                let albumPatch = AutoTagTrackPatch(
                    artist: result.artistName,
                    album: result.title,
                    albumArtist: result.artistName,
                    genre: detail.primaryGenre,
                    year: result.year,
                    musicBrainzReleaseID: result.releaseID,
                    artworkURL: "https://coverartarchive.org/release/\(result.releaseID)/front-500"
                )
                candidates.append(AutoTagAlbumCandidate(
                    id: "mb-album-\(result.releaseID)",
                    displayTitle: "\(result.artistName ?? "Unknown Artist") - \(result.title)",
                    subtitle: [detail.primaryGenre, result.year.map(String.init), "MusicBrainz"].compactMap { $0 }.joined(separator: " • "),
                    confidence: result.confidence,
                    providers: [.musicBrainz],
                    mergeKey: mergeKey,
                    albumPatch: albumPatch,
                    perTrackPatches: perTrackPatches,
                    releaseTracks: detail.trackHints.map {
                        AutoTagReleaseTrackHint(title: $0.title, trackNumber: $0.trackNumber, discNumber: $0.discNumber, recordingID: $0.recordingID, isrc: $0.isrc)
                    }
                ))
            }
            return candidates
        } catch {
            NSLog("AutoTaggingService: MusicBrainz album lookup failed: %@", error.localizedDescription)
            return []
        }
    }

    private func normalizeKey(_ components: [String?]) -> String {
        components
            .compactMap { $0 }
            .map(AutoTagTitleMatcher.normalizedKeyComponent)
            .filter { !$0.isEmpty }
            .joined(separator: "|")
    }
}

private actor HTTPResponseCache {
    static let shared = HTTPResponseCache()
    private var dataByURL: [String: (timestamp: Date, data: Data)] = [:]
    private let maxAge: TimeInterval = 300

    func get(url: URL) -> Data? {
        guard let entry = dataByURL[url.absoluteString] else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > maxAge {
            dataByURL.removeValue(forKey: url.absoluteString)
            return nil
        }
        return entry.data
    }

    func set(url: URL, data: Data) {
        dataByURL[url.absoluteString] = (Date(), data)
    }
}

private actor HTTPHostThrottle {
    static let shared = HTTPHostThrottle()
    private var lastRequestAt: [String: Date] = [:]

    func waitIfNeeded(for host: String, minInterval: TimeInterval) async {
        if let last = lastRequestAt[host] {
            let delta = Date().timeIntervalSince(last)
            if delta < minInterval {
                let sleepNanos = UInt64((minInterval - delta) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: sleepNanos)
            }
        }
        lastRequestAt[host] = Date()
    }
}

private struct DiscogsTaggingClient {
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: cfg)
    }

    struct SearchResult {
        let id: Int
        let artistName: String?
        let albumName: String?
        let confidence: Double
    }

    struct ReleaseDetails {
        struct TrackHint {
            let title: String
            let trackNumber: Int?
            let discNumber: Int?
            let isrc: String?
        }

        let id: Int
        let masterID: Int?
        let year: Int?
        let primaryGenre: String?
        let primaryLabel: String?
        let catalogNumber: String?
        let primaryArtworkURL: String?
        let trackHints: [TrackHint]

        func bestTrackMatch(for title: String) -> TrackHint? {
            let best = trackHints.max(by: { lhs, rhs in
                AutoTagTitleMatcher.score(lhs.title, title) < AutoTagTitleMatcher.score(rhs.title, title)
            })
            if let best {
                let score = AutoTagTitleMatcher.score(best.title, title)
                return score >= 0.74 ? best : nil
            }
            return nil
        }
    }

    func searchReleases(query: String, limit: Int) async throws -> [SearchResult] {
        var comps = URLComponents(string: "https://api.discogs.com/database/search")
        comps?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "per_page", value: String(limit)),
            URLQueryItem(name: "page", value: "1")
        ]
        guard let url = comps?.url else { return [] }
        let response: DiscogsSearchResponse = try await request(url: url)
        return response.results.enumerated().map { idx, dto in
            SearchResult(
                id: dto.id,
                artistName: dto.artistName,
                albumName: dto.albumName,
                confidence: max(0.20, 0.90 - Double(idx) * 0.10)
            )
        }
    }

    func fetchRelease(id: Int) async throws -> ReleaseDetails? {
        guard let url = URL(string: "https://api.discogs.com/releases/\(id)") else { return nil }
        let response: DiscogsReleaseResponse = try await request(url: url)

        let hints = response.tracklist
            .filter { $0.type == "track" || $0.type == nil }
            .map { item in
                ReleaseDetails.TrackHint(
                    title: item.title,
                    trackNumber: parseTrackNumber(item.position),
                    discNumber: parseDiscNumber(item.position),
                    isrc: item.isrc
                )
            }

        return ReleaseDetails(
            id: response.id,
            masterID: response.masterID,
            year: response.year,
            primaryGenre: response.styles.first ?? response.genres.first,
            primaryLabel: response.labels.first?.name,
            catalogNumber: response.labels.first?.catalogNumber,
            primaryArtworkURL: response.images.first?.uri,
            trackHints: hints
        )
    }

    private func parseTrackNumber(_ position: String?) -> Int? {
        guard let position else { return nil }
        let parts = position.split(separator: "-")
        if let last = parts.last, let number = Int(last.filter(\.isNumber)) {
            return number
        }
        if let number = Int(position.filter(\.isNumber)) {
            return number
        }
        return nil
    }

    private func parseDiscNumber(_ position: String?) -> Int? {
        guard let position else { return nil }
        let parts = position.split(separator: "-")
        if parts.count == 2, let disc = Int(parts[0].filter(\.isNumber)) {
            return disc
        }
        return 1
    }

    private func request<T: Decodable>(url: URL) async throws -> T {
        if let cached = await HTTPResponseCache.shared.get(url: url) {
            return try JSONDecoder().decode(T.self, from: cached)
        }
        if let host = url.host {
            await HTTPHostThrottle.shared.waitIfNeeded(for: host, minInterval: 0.45)
        }
        var request = URLRequest(url: url)
        request.setValue("NullPlayer/1.0 (metadata auto-tag)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(domain: "DiscogsTaggingClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Discogs HTTP \(http.statusCode)"])
        }
        await HTTPResponseCache.shared.set(url: url, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct MusicBrainzTaggingClient {
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: cfg)
    }

    struct RecordingResult {
        let recordingID: String
        let releaseID: String?
        let title: String
        let artistName: String?
        let releaseTitle: String?
        let confidence: Double
        let year: Int?
        let genre: String?
        let trackNumber: Int?
        let discNumber: Int?
        let isrc: String?
    }

    struct ReleaseResult {
        let releaseID: String
        let title: String
        let artistName: String?
        let confidence: Double
        let year: Int?
    }

    struct ReleaseDetails {
        struct TrackHint {
            let title: String
            let trackNumber: Int?
            let discNumber: Int?
            let recordingID: String?
            let isrc: String?
        }

        let primaryGenre: String?
        let trackHints: [TrackHint]
    }

    static func decodeReleaseSearchResults(from data: Data) throws -> [ReleaseResult] {
        let response = try JSONDecoder().decode(MusicBrainzReleaseSearchResponse.self, from: data)
        return response.releases.map { release in
            ReleaseResult(
                releaseID: release.id,
                title: release.title,
                artistName: release.artistCredit?.first?.name,
                confidence: (Double(release.score ?? "0") ?? 0) / 100.0,
                year: release.date.flatMap { Int($0.prefix(4)) }
            )
        }
    }

    static func decodeReleaseDetails(from data: Data) throws -> ReleaseDetails {
        let response = try JSONDecoder().decode(MusicBrainzReleaseDetailsResponse.self, from: data)
        let hints = response.media.flatMap { medium in
            medium.tracks.map { track in
                ReleaseDetails.TrackHint(
                    title: track.title,
                    trackNumber: Int(track.number),
                    discNumber: Int(medium.position),
                    recordingID: track.recording?.id,
                    isrc: track.recording?.isrcs?.first
                )
            }
        }
        return ReleaseDetails(
            primaryGenre: response.genres?.first?.name ?? response.tags?.first?.name,
            trackHints: hints
        )
    }

    func searchRecordings(query: String, limit: Int) async throws -> [RecordingResult] {
        var comps = URLComponents(string: "https://musicbrainz.org/ws/2/recording")
        comps?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = comps?.url else { return [] }
        let response: MusicBrainzRecordingSearchResponse = try await request(url: url)
        return response.recordings.map { recording in
            let release = recording.releases?.first
            return RecordingResult(
                recordingID: recording.id,
                releaseID: release?.id,
                title: recording.title,
                artistName: recording.artistCredit?.first?.name,
                releaseTitle: release?.title,
                confidence: (Double(recording.score ?? "0") ?? 0) / 100.0,
                year: release?.date.flatMap { Int($0.prefix(4)) },
                genre: recording.tags?.first?.name,
                trackNumber: nil,
                discNumber: nil,
                isrc: recording.isrcs?.first
            )
        }
    }

    func searchReleases(query: String, limit: Int) async throws -> [ReleaseResult] {
        var comps = URLComponents(string: "https://musicbrainz.org/ws/2/release")
        comps?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = comps?.url else { return [] }
        let data = try await requestData(url: url)
        return try Self.decodeReleaseSearchResults(from: data)
    }

    func fetchReleaseDetails(id: String) async throws -> ReleaseDetails? {
        var comps = URLComponents(string: "https://musicbrainz.org/ws/2/release/\(id)")
        comps?.queryItems = [
            URLQueryItem(name: "inc", value: "recordings+artist-credits+genres+isrcs"),
            URLQueryItem(name: "fmt", value: "json")
        ]
        guard let url = comps?.url else { return nil }
        let data = try await requestData(url: url)
        return try Self.decodeReleaseDetails(from: data)
    }

    private func request<T: Decodable>(url: URL) async throws -> T {
        let data = try await requestData(url: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func requestData(url: URL) async throws -> Data {
        if let cached = await HTTPResponseCache.shared.get(url: url) {
            return cached
        }
        if let host = url.host {
            await HTTPHostThrottle.shared.waitIfNeeded(for: host, minInterval: 0.8)
        }
        var request = URLRequest(url: url)
        request.setValue("NullPlayer/1.0 (metadata auto-tag)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(domain: "MusicBrainzTaggingClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "MusicBrainz HTTP \(http.statusCode)"])
        }
        await HTTPResponseCache.shared.set(url: url, data: data)
        return data
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        }
        return nil
    }
}

private struct DiscogsSearchResponse: Decodable {
    let results: [DiscogsSearchResultDTO]
}

private struct DiscogsSearchResultDTO: Decodable {
    let id: Int
    let title: String?

    var artistName: String? {
        guard let title else { return nil }
        let parts = title.components(separatedBy: " - ")
        return parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var albumName: String? {
        guard let title else { return nil }
        let parts = title.components(separatedBy: " - ")
        if parts.count > 1 {
            return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title
    }
}

private struct DiscogsReleaseResponse: Decodable {
    struct TrackItem: Decodable {
        let title: String
        let position: String?
        let type: String?
        let isrc: String?

        enum CodingKeys: String, CodingKey {
            case title, position, type, isrc
            case typeAlt = "type_"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            self.position = try c.decodeIfPresent(String.self, forKey: .position)
            self.isrc = try c.decodeIfPresent(String.self, forKey: .isrc)
            self.type = try c.decodeIfPresent(String.self, forKey: .type) ?? c.decodeIfPresent(String.self, forKey: .typeAlt)
        }
    }

    struct LabelItem: Decodable {
        let name: String?
        let catalogNumber: String?

        enum CodingKeys: String, CodingKey {
            case name
            case catalogNumber = "catno"
        }
    }

    struct ImageItem: Decodable {
        let uri: String?
    }

    let id: Int
    let masterID: Int?
    let year: Int?
    let genres: [String]
    let styles: [String]
    let labels: [LabelItem]
    let images: [ImageItem]
    let tracklist: [TrackItem]

    enum CodingKeys: String, CodingKey {
        case id, year, genres, styles, labels, images, tracklist
        case masterID = "master_id"
    }
}

private struct MusicBrainzRecordingSearchResponse: Decodable {
    let recordings: [MusicBrainzRecordingDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordings = try container.decodeIfPresent([MusicBrainzRecordingDTO].self, forKey: .recordings) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case recordings
    }
}

private struct MusicBrainzRecordingDTO: Decodable {
    struct Credit: Decodable { let name: String? }
    struct Release: Decodable {
        let id: String
        let title: String?
        let date: String?
    }
    struct Tag: Decodable { let name: String? }

    let id: String
    let title: String
    let score: String?
    let artistCredit: [Credit]?
    let releases: [Release]?
    let tags: [Tag]?
    let isrcs: [String]?

    enum CodingKeys: String, CodingKey {
        case id, title, score, releases, tags, isrcs
        case artistCredit = "artist-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        score = try container.decodeLossyStringIfPresent(forKey: .score)
        artistCredit = try container.decodeIfPresent([Credit].self, forKey: .artistCredit)
        releases = try container.decodeIfPresent([Release].self, forKey: .releases)
        tags = try container.decodeIfPresent([Tag].self, forKey: .tags)
        isrcs = try container.decodeIfPresent([String].self, forKey: .isrcs)
    }
}

private struct MusicBrainzReleaseSearchResponse: Decodable {
    let releases: [MusicBrainzReleaseDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        releases = try container.decodeIfPresent([MusicBrainzReleaseDTO].self, forKey: .releases) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case releases
    }
}

private struct MusicBrainzReleaseDTO: Decodable {
    struct Credit: Decodable { let name: String? }
    let id: String
    let title: String
    let score: String?
    let date: String?
    let artistCredit: [Credit]?

    enum CodingKeys: String, CodingKey {
        case id, title, score, date
        case artistCredit = "artist-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        score = try container.decodeLossyStringIfPresent(forKey: .score)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        artistCredit = try container.decodeIfPresent([Credit].self, forKey: .artistCredit)
    }
}

private struct MusicBrainzReleaseDetailsResponse: Decodable {
    struct Tag: Decodable { let name: String? }

    struct Medium: Decodable {
        struct Track: Decodable {
            struct Recording: Decodable {
                let id: String?
                let isrcs: [String]?
            }

            let title: String
            let number: String
            let recording: Recording?

            private enum CodingKeys: String, CodingKey {
                case title, number, recording
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
                number = try container.decodeLossyStringIfPresent(forKey: .number) ?? ""
                recording = try container.decodeIfPresent(Recording.self, forKey: .recording)
            }
        }

        let position: String
        let tracks: [Track]

        private enum CodingKeys: String, CodingKey {
            case position, tracks
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            position = try container.decodeLossyStringIfPresent(forKey: .position) ?? ""
            tracks = try container.decodeIfPresent([Track].self, forKey: .tracks) ?? []
        }
    }

    let genres: [Tag]?
    let tags: [Tag]?
    let media: [Medium]

    private enum CodingKeys: String, CodingKey {
        case genres, tags, media
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        genres = try container.decodeIfPresent([Tag].self, forKey: .genres)
        tags = try container.decodeIfPresent([Tag].self, forKey: .tags)
        media = try container.decodeIfPresent([Medium].self, forKey: .media) ?? []
    }
}
