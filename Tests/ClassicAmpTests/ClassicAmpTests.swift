import XCTest
@testable import ClassicAmp

final class ClassicAmpTests: XCTestCase {
    
    // MARK: - BMP Parser Tests
    
    func testBMPParserSignatureValidation() {
        // Empty data should return nil
        let emptyData = Data()
        XCTAssertNil(BMPParser.parse(data: emptyData))
        
        // Invalid signature should return nil
        let invalidData = Data([0x00, 0x00])
        XCTAssertNil(BMPParser.parse(data: invalidData))
        
        // Valid BM signature but too short
        let shortData = Data([0x42, 0x4D, 0x00, 0x00])
        XCTAssertNil(BMPParser.parse(data: shortData))
    }
    
    // MARK: - Track Model Tests
    
    func testTrackCreation() {
        let url = URL(fileURLWithPath: "/path/to/song.mp3")
        let track = Track(url: url)
        
        XCTAssertEqual(track.title, "song")
        XCTAssertEqual(track.url, url)
        XCTAssertNil(track.artist)
    }
    
    func testTrackDisplayTitle() {
        let url = URL(fileURLWithPath: "/path/to/song.mp3")
        
        // Without artist
        let track1 = Track(url: url, title: "Test Song")
        XCTAssertEqual(track1.displayTitle, "Test Song")
        
        // With artist
        let track2 = Track(url: url, title: "Test Song", artist: "Test Artist")
        XCTAssertEqual(track2.displayTitle, "Test Artist - Test Song")
    }
    
    func testTrackFormattedDuration() {
        let url = URL(fileURLWithPath: "/path/to/song.mp3")
        
        // No duration
        let track1 = Track(url: url, title: "Test")
        XCTAssertEqual(track1.formattedDuration, "--:--")
        
        // With duration
        let track2 = Track(url: url, title: "Test", duration: 185)
        XCTAssertEqual(track2.formattedDuration, "3:05")
    }
    
    // MARK: - EQ Preset Tests
    
    func testEQPresetDefaults() {
        let flat = EQPreset.flat
        
        XCTAssertEqual(flat.name, "Flat")
        XCTAssertEqual(flat.preamp, 0)
        XCTAssertEqual(flat.bands.count, 10)
        XCTAssertTrue(flat.bands.allSatisfy { $0 == 0 })
    }
    
    func testEQPresetRock() {
        let rock = EQPreset.rock
        
        XCTAssertEqual(rock.name, "Rock")
        XCTAssertEqual(rock.bands.count, 10)
        // Rock preset should have boosted lows and highs
        XCTAssertGreaterThan(rock.bands[0], 0) // 60Hz boosted
        XCTAssertGreaterThan(rock.bands[9], 0) // 16kHz boosted
    }
    
    // MARK: - Playlist Model Tests
    
    func testPlaylistCreation() {
        let playlist = Playlist(name: "Test Playlist")
        
        XCTAssertEqual(playlist.name, "Test Playlist")
        XCTAssertTrue(playlist.trackURLs.isEmpty)
    }
    
    func testPlaylistAddTrack() {
        var playlist = Playlist(name: "Test")
        let url = URL(fileURLWithPath: "/path/to/song.mp3")
        
        playlist.addTrack(url: url)
        
        XCTAssertEqual(playlist.trackURLs.count, 1)
        XCTAssertEqual(playlist.trackURLs.first, url)
    }
    
    func testPlaylistRemoveTrack() {
        var playlist = Playlist(name: "Test")
        let url1 = URL(fileURLWithPath: "/path/to/song1.mp3")
        let url2 = URL(fileURLWithPath: "/path/to/song2.mp3")
        
        playlist.addTrack(url: url1)
        playlist.addTrack(url: url2)
        playlist.removeTrack(at: 0)
        
        XCTAssertEqual(playlist.trackURLs.count, 1)
        XCTAssertEqual(playlist.trackURLs.first, url2)
    }
    
    func testPlaylistM3UExport() {
        var playlist = Playlist(name: "Test")
        playlist.addTrack(url: URL(fileURLWithPath: "/path/to/song1.mp3"))
        playlist.addTrack(url: URL(fileURLWithPath: "/path/to/song2.mp3"))
        
        let m3u = playlist.toM3U()
        
        XCTAssertTrue(m3u.hasPrefix("#EXTM3U"))
        XCTAssertTrue(m3u.contains("/path/to/song1.mp3"))
        XCTAssertTrue(m3u.contains("/path/to/song2.mp3"))
    }
    
    // MARK: - Color Extension Tests
    
    func testNSColorHexInit() {
        let red = NSColor(hex: "#FF0000")
        XCTAssertNotNil(red)
        
        let green = NSColor(hex: "00FF00")
        XCTAssertNotNil(green)
        
        let invalid = NSColor(hex: "not a color")
        XCTAssertNil(invalid)
    }
    
    func testNSColorHexString() {
        let color = NSColor(red: 1.0, green: 0, blue: 0, alpha: 1.0)
        let hex = color.hexString
        XCTAssertEqual(hex, "#FF0000")
    }
}
