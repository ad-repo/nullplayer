import CoreAudio
import CoreVideo
import XCTest
@testable import NullPlayer

/// The visualization cast's stream (`skills/visualization-cast`): the transport stream both receivers
/// read, the playlist shape a Chromecast plays steadily, and the 4K frame-rate rule.
final class VisualizationCastTests: XCTestCase {

    // MARK: - MPEG-TS

    func testCRC32IsTheMPEG2Variant() {
        XCTAssertEqual(MPEGTSMuxer.crc32(Array("123456789".utf8)), 0x0376_E6E7)
    }

    func testSegmentIsWholePacketsWithValidTables() throws {
        var muxer = MPEGTSMuxer()
        muxer.beginSegment()
        muxer.writeVideo(annexB: [UInt8](repeating: 0xAB, count: 1000), pts: 3000, isKeyframe: true)
        muxer.writeAudio(adts: [UInt8](repeating: 0xCD, count: 200), pts: 3000)
        let bytes = muxer.take()
        XCTAssertEqual(bytes.count % 188, 0)
        let packets = stride(from: 0, to: bytes.count, by: 188).map { Array(bytes[$0..<$0 + 188]) }
        XCTAssertTrue(packets.allSatisfy { $0[0] == 0x47 })

        // PAT and PMT: each section's CRC over itself (CRC included) is zero.
        for pid in [0, Int(MPEGTSMuxer.pmtPID)] {
            let packet = try XCTUnwrap(packets.first { Self.pid($0) == pid })
            let start = 5 + Int(packet[4])                       // pointer field
            let length = (Int(packet[start + 1] & 0x0F) << 8) | Int(packet[start + 2])
            XCTAssertEqual(MPEGTSMuxer.crc32(Array(packet[start..<start + 3 + length])), 0, "PID \(pid)")
        }

        // Continuity counts per PID from zero.
        var counters: [Int: [Int]] = [:]
        for packet in packets { counters[Self.pid(packet), default: []].append(Int(packet[3] & 0x0F)) }
        for (pid, seen) in counters { XCTAssertEqual(seen, Array(0..<seen.count), "PID \(pid)") }
    }

    func testVideoCarriesPCRLevelWithItsPTSAndTheKeyframeFlag() throws {
        var muxer = MPEGTSMuxer()
        muxer.beginSegment()
        muxer.writeVideo(annexB: [0, 0, 0, 1, 0x65], pts: 90_000, isKeyframe: true)
        let bytes = muxer.take()
        let packet = try XCTUnwrap(stride(from: 0, to: bytes.count, by: 188).map { Array(bytes[$0..<$0 + 188]) }
            .first { Self.pid($0) == Int(MPEGTSMuxer.videoPID) })
        XCTAssertNotEqual(packet[3] & 0x20, 0, "adaptation field")
        XCTAssertNotEqual(packet[5] & 0x40, 0, "random access")
        XCTAssertNotEqual(packet[5] & 0x10, 0, "PCR")
        let b = packet[6..<12].map(UInt64.init)
        let pcr = (b[0] << 25) | (b[1] << 17) | (b[2] << 9) | (b[3] << 1) | (b[4] >> 7)
        let pes = 5 + Int(packet[4])
        XCTAssertEqual(Array(packet[pes..<pes + 3]), [0, 0, 1])
        let p = packet[pes + 9..<pes + 14].map(UInt64.init)
        let pts = (((p[0] >> 1) & 7) << 30) | (p[1] << 22) | ((p[2] >> 1) << 15) | (p[3] << 7) | (p[4] >> 1)
        XCTAssertEqual(pts, 90_000 + MPEGTSMuxer.ptsOffset)
        XCTAssertEqual(pcr, pts)
    }

    func testADTSHeaderCarriesTheFrameLengthWithItself() {
        let header = MPEGTSMuxer.adtsHeader(frameLength: 300, sampleRate: 48_000, channels: 2)
        XCTAssertEqual(header.count, 7)
        XCTAssertEqual(header[0], 0xFF)
        let length = (Int(header[3] & 0x03) << 11) | (Int(header[4]) << 3) | Int(header[5] >> 5)
        XCTAssertEqual(length, 307)
        XCTAssertEqual((header[2] >> 2) & 0x0F, 3, "48 kHz")
    }

    /// A payload that fills its packets exactly needs no adaptation field; one that falls short is
    /// stuffed to 188, including the one-byte (length 0) and two-byte cases.
    func testPacketsStuffOnlyWhatThePayloadLeaves() {
        for (shortfall, expected) in [(0, nil), (1, [0x00]), (2, [0x01, 0x00]), (5, [0x04, 0x00, 0xFF, 0xFF, 0xFF])] as [(Int, [UInt8]?)] {
            var muxer = MPEGTSMuxer()
            // An audio PES (14-byte header) of exactly two packets, less `shortfall`.
            muxer.writeAudio(adts: [UInt8](repeating: 0xCD, count: 2 * 184 - 14 - shortfall), pts: 0)
            let bytes = muxer.take()
            XCTAssertEqual(bytes.count, 2 * 188, "shortfall \(shortfall)")
            XCTAssertEqual(bytes[3] & 0x30, 0x10, "first packet is all payload")
            let last = Array(bytes[188...])
            if let expected {
                XCTAssertEqual(last[3] & 0x30, 0x30, "shortfall \(shortfall)")
                XCTAssertEqual(Array(last[4..<4 + expected.count]), expected, "shortfall \(shortfall)")
                XCTAssertEqual(last[4 + expected.count], 0xCD)
            } else {
                XCTAssertEqual(last[3] & 0x30, 0x10)
            }
            XCTAssertEqual(last.last, 0xCD)
        }
    }

    // MARK: - Audio ring

    /// The tap's ring duplicates mono, drops what a full ring cannot take, reads only the newest it
    /// keeps, and pads a short read with silence.
    func testAudioRingKeepsTheNewestAndPadsWithSilence() {
        let ring = AudioTapRing(frames: 4)
        var samples: [Float] = (1...10).map(Float.init)   // mono; the ring holds 8 frames, keeps 4
        samples.withUnsafeMutableBytes { raw in
            let list = AudioBufferList.allocate(maximumBuffers: 1)
            defer { free(list.unsafeMutablePointer) }
            list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress)
            ring.write(list, frames: 10)
        }
        XCTAssertEqual(ring.droppedFrames, 2)
        XCTAssertEqual(ring.read(frames: 6), [5, 5, 6, 6, 7, 7, 8, 8, 0, 0, 0, 0])
        XCTAssertEqual(ring.read(frames: 1), [0, 0])
    }

    // MARK: - Playlist

    /// A Chromecast plays a live cast steadily only from an EVENT playlist that starts it 6 s back.
    func testPlaylistIsAnEventPlaylistOfEverySegment() throws {
        let quality = VisualizationCastQuality(resolution: .hd, frameRate: 30)
        let encoder = try VisualizationCastEncoder(quality: quality, inputSampleRate: 48_000)
        encoder.start()
        defer { encoder.stop() }
        let frame = try XCTUnwrap(encoder.makePixelBuffer())
        encoder.submit(frame)   // the encoder repeats it every tick
        let deadline = Date().addingTimeInterval(6)
        while encoder.segmentCount < 3, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        XCTAssertGreaterThanOrEqual(encoder.segmentCount, 3)

        let playlist = try XCTUnwrap(encoder.playlist())
        let lines = playlist.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.contains("#EXT-X-PLAYLIST-TYPE:EVENT"))
        XCTAssertTrue(lines.contains("#EXT-X-START:TIME-OFFSET=-6.0"))
        XCTAssertTrue(lines.contains("#EXT-X-MEDIA-SEQUENCE:0"))
        XCTAssertTrue(lines.contains("#EXT-X-TARGETDURATION:2"))
        let segments = lines.filter { $0.hasPrefix("seg-") }
        XCTAssertEqual(segments.first, "seg-0.ts")
        XCTAssertTrue(lines.filter { $0.hasPrefix("#EXTINF:") }.allSatisfy { $0 == "#EXTINF:1.000," })
        let newest = try XCTUnwrap(Int(segments.last?.dropFirst(4).dropLast(3) ?? ""))
        XCTAssertNotNil(encoder.segment(newest))
    }

    // MARK: - Quality

    func testFourKCastsAtThirtyOnly() {
        XCTAssertTrue(VisualizationCastQuality.frameRateAllowed(60, at: .fullHD))
        XCTAssertTrue(VisualizationCastQuality.frameRateAllowed(30, at: .uhd))
        XCTAssertFalse(VisualizationCastQuality.frameRateAllowed(60, at: .uhd))

        let keys = ["visualizationCast.resolution", "visualizationCast.frameRate"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) } }
        VisualizationCastQuality(resolution: .uhd, frameRate: 60).save()
        XCTAssertEqual(VisualizationCastQuality.saved, VisualizationCastQuality(resolution: .uhd, frameRate: 30))
        VisualizationCastQuality(resolution: .fullHD, frameRate: 60).save()
        XCTAssertEqual(VisualizationCastQuality.saved.frameRate, 60)
    }

    private static func pid(_ packet: [UInt8]) -> Int { (Int(packet[1] & 0x1F) << 8) | Int(packet[2]) }
}
