import XCTest
@testable import NullPlayer

final class AutoTaggingServiceTests: XCTestCase {

    func testTrackCandidateMergerKeepsDistinctCandidatesWithSameMergeKey() {
        let discogsPatch = AutoTagTrackPatch(
            title: "Discogs Title",
            genre: "House",
            discogsReleaseID: 10,
            discogsMasterID: 20,
            discogsLabel: "Discogs Label",
            discogsCatalogNumber: "D-100",
            artworkURL: "https://discogs.example/art.jpg"
        )
        let mbPatch = AutoTagTrackPatch(
            title: "MusicBrainz Title",
            trackNumber: 2,
            discNumber: 1,
            musicBrainzRecordingID: "mb-recording",
            musicBrainzReleaseID: "mb-release"
        )

        let discogsCandidate = AutoTagTrackCandidate(
            id: "discogs",
            displayTitle: "A",
            subtitle: "",
            confidence: 0.60,
            providers: [.discogs],
            mergeKey: "artist|title|album",
            patch: discogsPatch
        )
        let mbCandidate = AutoTagTrackCandidate(
            id: "mb",
            displayTitle: "B",
            subtitle: "",
            confidence: 0.92,
            providers: [.musicBrainz],
            mergeKey: "artist|title|album",
            patch: mbPatch
        )

        let merged = AutoTagCandidateMerger.mergeTrackCandidates([discogsCandidate, mbCandidate], limit: 5)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.map(\.id), ["mb", "discogs"])
    }

    func testAlbumCandidateMergerKeepsDistinctCandidatesWithSameMergeKey() {
        let trackID = UUID()
        let discogs = AutoTagAlbumCandidate(
            id: "d1",
            displayTitle: "Discogs Album",
            subtitle: "",
            confidence: 0.70,
            providers: [.discogs],
            mergeKey: "artist|album",
            albumPatch: AutoTagTrackPatch(genre: "Techno", discogsReleaseID: 555),
            perTrackPatches: [trackID: AutoTagTrackPatch(title: "Discogs Track")],
            releaseTracks: [AutoTagReleaseTrackHint(title: "Discogs Track", trackNumber: 1, discNumber: 1, recordingID: nil, isrc: nil)]
        )
        let mb = AutoTagAlbumCandidate(
            id: "m1",
            displayTitle: "MB Album",
            subtitle: "",
            confidence: 0.85,
            providers: [.musicBrainz],
            mergeKey: "artist|album",
            albumPatch: AutoTagTrackPatch(musicBrainzReleaseID: "mb-rel"),
            perTrackPatches: [trackID: AutoTagTrackPatch(title: "MB Track", trackNumber: 1, discNumber: 1)],
            releaseTracks: [AutoTagReleaseTrackHint(title: "MB Track", trackNumber: 1, discNumber: 1, recordingID: "mb-rec", isrc: nil)]
        )

        let merged = AutoTagCandidateMerger.mergeAlbumCandidates([discogs, mb], limit: 5)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.map(\.id), ["m1", "d1"])
        XCTAssertEqual(merged.first(where: { $0.id == "d1" })?.perTrackPatches[trackID]?.title, "Discogs Track")
        XCTAssertEqual(merged.first(where: { $0.id == "m1" })?.perTrackPatches[trackID]?.trackNumber, 1)
    }

    func testAlbumCandidateMergerLimitsToTopFiveByConfidence() {
        let candidates = (0..<7).map { index in
            AutoTagAlbumCandidate(
                id: "c\(index)",
                displayTitle: "Candidate \(index)",
                subtitle: "",
                confidence: Double(index) / 10.0,
                providers: [.discogs],
                mergeKey: "artist|album",
                albumPatch: AutoTagTrackPatch(album: "Album \(index)"),
                perTrackPatches: [:],
                releaseTracks: []
            )
        }

        let merged = AutoTagCandidateMerger.mergeAlbumCandidates(candidates, limit: 5)
        XCTAssertEqual(merged.count, 5)
        XCTAssertEqual(merged.map(\.id), ["c6", "c5", "c4", "c3", "c2"])
    }

    func testAlbumCandidateMergerPrefersTrackMatchedResultsOverNoOpConfidence() {
        let matchedTrackID = UUID()
        let noOp = AutoTagAlbumCandidate(
            id: "noop",
            displayTitle: "High Voltage Generic",
            subtitle: "",
            confidence: 0.99,
            providers: [.discogs],
            mergeKey: "acdc|highvoltage",
            albumPatch: AutoTagTrackPatch(album: "High Voltage"),
            perTrackPatches: [:],
            releaseTracks: [
                AutoTagReleaseTrackHint(title: "Little Lover", trackNumber: 7, discNumber: 1, recordingID: nil, isrc: nil)
            ]
        )
        let matched = AutoTagAlbumCandidate(
            id: "matched",
            displayTitle: "High Voltage AU",
            subtitle: "",
            confidence: 0.90,
            providers: [.musicBrainz],
            mergeKey: "acdc|highvoltage",
            albumPatch: AutoTagTrackPatch(album: "High Voltage"),
            perTrackPatches: [matchedTrackID: AutoTagTrackPatch(title: "Little Lover", trackNumber: 7, discNumber: 1)],
            releaseTracks: [
                AutoTagReleaseTrackHint(title: "Little Lover", trackNumber: 7, discNumber: 1, recordingID: "rec-7", isrc: nil)
            ]
        )

        let merged = AutoTagCandidateMerger.mergeAlbumCandidates([noOp, matched], limit: 5)
        XCTAssertEqual(merged.map(\.id), ["matched", "noop"])
    }

    func testTrackMapperMatchesDiscTrackThenTitleFallback() {
        let localExact = LibraryTrack(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/exact.mp3"),
            title: "Exact Song",
            artist: "Artist",
            album: "Album",
            albumArtist: "Artist",
            trackNumber: 1,
            discNumber: 1
        )
        let localFuzzy = LibraryTrack(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/fuzzy.mp3"),
            title: "Sunset Boulevard",
            artist: "Artist",
            album: "Album",
            albumArtist: "Artist"
        )

        let releaseHints = [
            AutoTagReleaseTrackHint(title: "Exact Song", trackNumber: 1, discNumber: 1, recordingID: "mb1", isrc: nil),
            AutoTagReleaseTrackHint(title: "Sunset Blvd", trackNumber: nil, discNumber: nil, recordingID: "mb2", isrc: "ISRC-2")
        ]

        let mapped = AutoTagTrackMapper.map(releaseTracks: releaseHints, localTracks: [localExact, localFuzzy])
        XCTAssertEqual(mapped[localExact.id]?.recordingID, "mb1")
        XCTAssertEqual(mapped[localFuzzy.id]?.recordingID, "mb2")
        XCTAssertEqual(mapped[localFuzzy.id]?.isrc, "ISRC-2")
    }

    func testTrackMapperMatchesTitlesWithEmbeddedNoiseAndArtistPrefixes() {
        let localOne = LibraryTrack(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/jailbreak.mp3"),
            title: "01 - AC/DC - Jailbreak (2003 Remaster)",
            artist: "AC/DC",
            album: "'74 Jailbreak EP",
            albumArtist: "AC/DC"
        )
        let localTwo = LibraryTrack(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/soul-stripper.mp3"),
            title: "04 Soul Stripper [Remastered 2003]",
            artist: "AC/DC",
            album: "'74 Jailbreak EP",
            albumArtist: "AC/DC"
        )

        let releaseHints = [
            AutoTagReleaseTrackHint(title: "Jailbreak", trackNumber: nil, discNumber: nil, recordingID: "mb-jailbreak", isrc: nil),
            AutoTagReleaseTrackHint(title: "Soul Stripper", trackNumber: nil, discNumber: nil, recordingID: "mb-soul-stripper", isrc: nil)
        ]

        let mapped = AutoTagTrackMapper.map(releaseTracks: releaseHints, localTracks: [localOne, localTwo])
        XCTAssertEqual(mapped[localOne.id]?.recordingID, "mb-jailbreak")
        XCTAssertEqual(mapped[localTwo.id]?.recordingID, "mb-soul-stripper")
    }

    func testTrackMapperUsesTitleScoringWhenTrackNumbersAreShifted() {
        let localOne = LibraryTrack(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/track-one.mp3"),
            title: "AC/DC - Soul Stripper",
            artist: "AC/DC",
            album: "'74 Jailbreak EP",
            albumArtist: "AC/DC",
            trackNumber: 7,
            discNumber: 1
        )
        let localTwo = LibraryTrack(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/track-two.mp3"),
            title: "Show Business - 2003 Remaster",
            artist: "AC/DC",
            album: "'74 Jailbreak EP",
            albumArtist: "AC/DC",
            trackNumber: 8,
            discNumber: 1
        )

        let releaseHints = [
            AutoTagReleaseTrackHint(title: "Soul Stripper", trackNumber: 1, discNumber: 1, recordingID: "mb-soul", isrc: nil),
            AutoTagReleaseTrackHint(title: "Show Business", trackNumber: 2, discNumber: 1, recordingID: "mb-show", isrc: nil)
        ]

        let mapped = AutoTagTrackMapper.map(releaseTracks: releaseHints, localTracks: [localOne, localTwo])
        XCTAssertEqual(mapped[localOne.id]?.recordingID, "mb-soul")
        XCTAssertEqual(mapped[localTwo.id]?.recordingID, "mb-show")
    }

    func testMusicBrainzReleaseSearchDecodesNumericScores() throws {
        let data = Data("""
        {
          "releases": [
            {
              "id": "rel-1",
              "title": "High Voltage",
              "score": 100,
              "date": "1976-05-14",
              "artist-credit": [{ "name": "AC/DC" }]
            }
          ]
        }
        """.utf8)

        let results = try MusicBrainzTaggingClient.decodeReleaseSearchResults(from: data)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.releaseID, "rel-1")
        XCTAssertEqual(results.first?.artistName, "AC/DC")
        XCTAssertEqual(results.first?.confidence, 1.0)
        XCTAssertEqual(results.first?.year, 1976)
    }

    func testMusicBrainzReleaseDetailsDecodesNumericTrackFieldsAndMissingMedia() throws {
        let numericData = Data("""
        {
          "genres": [{ "name": "Hard Rock" }],
          "media": [
            {
              "position": 1,
              "tracks": [
                {
                  "title": "T.N.T.",
                  "number": 5,
                  "recording": {
                    "id": "rec-5",
                    "isrcs": ["ISRC-5"]
                  }
                }
              ]
            }
          ]
        }
        """.utf8)

        let numericDetails = try MusicBrainzTaggingClient.decodeReleaseDetails(from: numericData)
        XCTAssertEqual(numericDetails.primaryGenre, "Hard Rock")
        XCTAssertEqual(numericDetails.trackHints.count, 1)
        XCTAssertEqual(numericDetails.trackHints.first?.title, "T.N.T.")
        XCTAssertEqual(numericDetails.trackHints.first?.trackNumber, 5)
        XCTAssertEqual(numericDetails.trackHints.first?.discNumber, 1)
        XCTAssertEqual(numericDetails.trackHints.first?.recordingID, "rec-5")
        XCTAssertEqual(numericDetails.trackHints.first?.isrc, "ISRC-5")

        let missingMediaData = Data("""
        {
          "tags": [{ "name": "Rock" }]
        }
        """.utf8)

        let missingMediaDetails = try MusicBrainzTaggingClient.decodeReleaseDetails(from: missingMediaData)
        XCTAssertEqual(missingMediaDetails.primaryGenre, "Rock")
        XCTAssertTrue(missingMediaDetails.trackHints.isEmpty)
    }
}
