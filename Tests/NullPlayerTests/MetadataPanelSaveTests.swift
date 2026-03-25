import XCTest
import AppKit
@testable import NullPlayer

@MainActor
final class MetadataPanelSaveTests: XCTestCase {

    func testAlbumCandidatePanelReturnsSelectedCandidateOnContinue() {
        let localTrack = LibraryTrack(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/panel-track.mp3"),
            title: "Intro",
            artist: nil,
            album: "Hate Your God",
            albumArtist: nil,
            trackNumber: 1,
            discNumber: 1
        )

        let first = AutoTagAlbumCandidate(
            id: "first",
            displayTitle: "Nunslaughter - Hate Your God",
            subtitle: "",
            confidence: 1.0,
            providers: [.musicBrainz],
            mergeKey: "nunslaughter|hateyourgod",
            albumPatch: AutoTagTrackPatch(artist: "Nunslaughter", album: "Hate Your God", albumArtist: "Nunslaughter"),
            perTrackPatches: [localTrack.id: AutoTagTrackPatch(title: "Intro", trackNumber: 1, discNumber: 1)],
            releaseTracks: [AutoTagReleaseTrackHint(title: "Intro", trackNumber: 1, discNumber: 1, recordingID: "rec-1", isrc: nil)]
        )
        let second = AutoTagAlbumCandidate(
            id: "second",
            displayTitle: "Other - Other Album",
            subtitle: "",
            confidence: 0.5,
            providers: [.discogs],
            mergeKey: "other|otheralbum",
            albumPatch: AutoTagTrackPatch(artist: "Other", album: "Other Album", albumArtist: "Other"),
            perTrackPatches: [:],
            releaseTracks: []
        )

        let panel = AutoTagAlbumCandidatePanel(candidates: [first, second], localTracks: [localTrack])
        let selected = panel.simulateAcceptedCandidateForTesting(row: 0)

        XCTAssertEqual(selected?.id, "first")
        XCTAssertEqual(selected?.perTrackPatches.count, 1)
    }

    func testAlbumEditorPersistsAutoTagSharedAndPerTrackChanges() {
        let firstTrack = LibraryTrack(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/album-track-1.mp3"),
            title: "01 - AC/DC - Jailbreak (2003 Remaster)",
            artist: "Unknown Artist",
            album: "Unknown Album",
            albumArtist: "Unknown Artist",
            trackNumber: 7,
            discNumber: 1
        )
        let secondTrack = LibraryTrack(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/album-track-2.mp3"),
            title: "Show Business - 2003 Remaster",
            artist: "Unknown Artist",
            album: "Unknown Album",
            albumArtist: "Unknown Artist",
            trackNumber: 8,
            discNumber: 1
        )

        let album = Album(
            id: "Unknown Artist|Unknown Album",
            name: "Unknown Album",
            artist: "Unknown Artist",
            year: nil,
            tracks: [firstTrack, secondTrack]
        )
        let panel = EditAlbumTagsPanel(album: album)

        var updatedTracksByURL: [URL: LibraryTrack] = [:]
        panel.trackFinder = { _ in nil }
        panel.trackUpdater = { track in
            updatedTracksByURL[track.url] = track
        }

        let candidate = AutoTagAlbumCandidate(
            id: "candidate",
            displayTitle: "AC/DC - '74 Jailbreak EP",
            subtitle: "Discogs",
            confidence: 0.95,
            providers: [.discogs],
            mergeKey: "acdc|jailbreak",
            albumPatch: AutoTagTrackPatch(
                artist: "AC/DC",
                album: "'74 Jailbreak EP",
                albumArtist: "AC/DC",
                genre: "Hard Rock",
                year: 2003
            ),
            perTrackPatches: [
                firstTrack.id: AutoTagTrackPatch(title: "Jailbreak", trackNumber: 1, discNumber: 1),
                secondTrack.id: AutoTagTrackPatch(title: "Show Business", trackNumber: 2, discNumber: 1)
            ],
            releaseTracks: [
                AutoTagReleaseTrackHint(title: "Jailbreak", trackNumber: 1, discNumber: 1, recordingID: nil, isrc: nil),
                AutoTagReleaseTrackHint(title: "Show Business", trackNumber: 2, discNumber: 1, recordingID: nil, isrc: nil)
            ]
        )

        panel.applyCandidateForTesting(candidate)
        let savedTracks = panel.persistEdits()

        XCTAssertEqual(savedTracks.count, 2)
        XCTAssertEqual(updatedTracksByURL[firstTrack.url]?.artist, "AC/DC")
        XCTAssertEqual(updatedTracksByURL[firstTrack.url]?.albumArtist, "AC/DC")
        XCTAssertEqual(updatedTracksByURL[firstTrack.url]?.album, "'74 Jailbreak EP")
        XCTAssertEqual(updatedTracksByURL[firstTrack.url]?.genre, "Hard Rock")
        XCTAssertEqual(updatedTracksByURL[firstTrack.url]?.year, 2003)
        XCTAssertEqual(updatedTracksByURL[firstTrack.url]?.title, "Jailbreak")
        XCTAssertEqual(updatedTracksByURL[firstTrack.url]?.trackNumber, 1)

        XCTAssertEqual(updatedTracksByURL[secondTrack.url]?.artist, "AC/DC")
        XCTAssertEqual(updatedTracksByURL[secondTrack.url]?.albumArtist, "AC/DC")
        XCTAssertEqual(updatedTracksByURL[secondTrack.url]?.album, "'74 Jailbreak EP")
        XCTAssertEqual(updatedTracksByURL[secondTrack.url]?.title, "Show Business")
        XCTAssertEqual(updatedTracksByURL[secondTrack.url]?.trackNumber, 2)
    }
}
