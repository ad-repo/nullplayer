#if os(Linux)
import XCTest
import Foundation
import NullPlayerCore
@testable import NullPlayerPlayback

final class LinuxSmokeTests: XCTestCase {
    func testLocalPlaybackPauseResumeSeek() throws {
        setenv("GST_AUDIO_SINK", "fakesink", 1)

        let backend = LinuxGStreamerAudioBackend()
        let facade = AudioEngineFacade(backend: backend)
        let delegate = DelegateProbe()
        facade.delegate = delegate

        let fixture = try makeFixtureWAV()
        defer { try? FileManager.default.removeItem(at: fixture) }

        facade.loadTracks([Track(url: fixture)])
        facade.play()

        waitShort()
        facade.pause()
        waitShort()
        facade.play()
        waitShort()
        facade.seek(to: 0.2)
        waitShort()

        XCTAssertTrue(delegate.sawStateChange)
    }

    func testNextPreviousEQAndOutputs() throws {
        setenv("GST_AUDIO_SINK", "fakesink", 1)

        let backend = LinuxGStreamerAudioBackend()
        let facade = AudioEngineFacade(backend: backend)

        let first = try makeFixtureWAV(filename: "first.wav", frequency: 440)
        let second = try makeFixtureWAV(filename: "second.wav", frequency: 880)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        facade.loadTracks([Track(url: first), Track(url: second)])
        facade.play()
        waitShort()

        facade.next()
        waitShort()
        facade.previous()
        waitShort()

        facade.setEQEnabled(true)
        for band in 0..<facade.eqConfiguration.bandCount {
            facade.setEQBand(band, gain: Float((band % 3) - 1))
        }

        let outputs = facade.outputDevices
        XCTAssertFalse(outputs.isEmpty)

        if outputs.count > 1 {
            XCTAssertTrue(facade.selectOutputDevice(persistentID: outputs[1].persistentID))
        } else {
            XCTAssertTrue(facade.selectOutputDevice(persistentID: outputs[0].persistentID))
        }
    }

    func testHTTPStreamPlayback() throws {
        setenv("GST_AUDIO_SINK", "fakesink", 1)

        let fixture = try makeFixtureWAV(filename: "stream.wav", frequency: 330)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let server = Process()
        server.currentDirectoryURL = fixture.deletingLastPathComponent()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        server.arguments = ["python3", "-m", "http.server", "38080", "--bind", "127.0.0.1"]

        try server.run()
        defer {
            server.terminate()
            server.waitUntilExit()
        }

        usleep(400_000)

        let backend = LinuxGStreamerAudioBackend()
        let facade = AudioEngineFacade(backend: backend)
        let streamURL = URL(string: "http://127.0.0.1:38080/\(fixture.lastPathComponent)")!

        facade.loadTracks([Track(url: streamURL)])
        facade.play()
        waitShort()

        XCTAssertGreaterThanOrEqual(facade.currentIndex, 0)
    }

    private func waitShort() {
        let expectation = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    private func makeFixtureWAV(
        filename: String = "fixture.wav",
        frequency: Double = 440,
        sampleRate: Int = 44_100,
        durationSeconds: Double = 1.0
    ) throws -> URL {
        let frameCount = Int(Double(sampleRate) * durationSeconds)
        var pcm = Data(capacity: frameCount * MemoryLayout<Int16>.size)

        for index in 0..<frameCount {
            let t = Double(index) / Double(sampleRate)
            let value = sin(2.0 * .pi * frequency * t)
            let sample = Int16(max(-32767, min(32767, Int(value * 32767))))
            var littleEndian = sample.littleEndian
            pcm.append(Data(bytes: &littleEndian, count: MemoryLayout<Int16>.size))
        }

        let byteRate = sampleRate * MemoryLayout<Int16>.size
        let blockAlign = UInt16(MemoryLayout<Int16>.size)
        let subchunk2Size = UInt32(pcm.count)
        let chunkSize = UInt32(36) + subchunk2Size

        var wav = Data()
        wav.append("RIFF".data(using: .ascii)!)
        appendLittleEndian(chunkSize, to: &wav)
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)

        let subchunk1Size: UInt32 = 16
        let audioFormat: UInt16 = 1
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16

        appendLittleEndian(subchunk1Size, to: &wav)
        appendLittleEndian(audioFormat, to: &wav)
        appendLittleEndian(numChannels, to: &wav)
        appendLittleEndian(UInt32(sampleRate), to: &wav)
        appendLittleEndian(UInt32(byteRate), to: &wav)
        appendLittleEndian(blockAlign, to: &wav)
        appendLittleEndian(bitsPerSample, to: &wav)

        wav.append("data".data(using: .ascii)!)
        appendLittleEndian(subchunk2Size, to: &wav)
        wav.append(pcm)

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nullplayer-tests")
            .appendingPathComponent(filename)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try wav.write(to: url)
        return url
    }

    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}

private final class DelegateProbe: AudioEngineDelegate {
    var sawStateChange = false

    func audioEngineDidChangeState(_ state: PlaybackState) {
        _ = state
        sawStateChange = true
    }

    func audioEngineDidUpdateTime(current: TimeInterval, duration: TimeInterval) {
        _ = current
        _ = duration
    }

    func audioEngineDidChangeTrack(_ track: Track?) {
        _ = track
    }

    func audioEngineDidUpdateSpectrum(_ levels: [Float]) {
        _ = levels
    }

    func audioEngineDidChangePlaylist() {}

    func audioEngineDidFailToLoadTrack(_ track: Track, error: Error) {
        _ = track
        _ = error
    }
}

#else
import XCTest

final class LinuxSmokeTests: XCTestCase {
    func testLinuxOnly() {
        XCTAssertTrue(true)
    }
}
#endif
