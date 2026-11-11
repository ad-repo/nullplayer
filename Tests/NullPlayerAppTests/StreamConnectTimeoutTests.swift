import XCTest
import AudioStreaming
@testable import NullPlayer

/// M87: an address that accepts the connection but never sends audio used to buffer forever,
/// because AudioStreaming retries it without reporting anything.
final class StreamConnectTimeoutTests: XCTestCase, StreamingAudioPlayerDelegate {
    private var failed: XCTestExpectation?

    func testStreamThatSendsNothingFailsAtTheDeadline() throws {
        try playSilentStream(pausingWhileConnecting: false)
    }

    /// A pause does not make an address answer, so it must not drop the deadline.
    func testPauseWhileConnectingStillFailsAtTheDeadline() throws {
        try playSilentStream(pausingWhileConnecting: true)
    }

    private func playSilentStream(pausingWhileConnecting: Bool) throws {
        // A listening socket nobody accepts on: the kernel completes the TCP handshake from the
        // backlog, and the HTTP request then waits for an answer that never comes.
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        try withUnsafeMutablePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                guard Darwin.bind(fd, raw, length) == 0, Darwin.listen(fd, 1) == 0,
                      getsockname(fd, raw, &length) == 0 else { throw XCTSkip("no loopback socket") }
            }
        }
        let port = UInt16(bigEndian: address.sin_port)

        let player = StreamingAudioPlayer()
        player.delegate = self
        player.connectTimeout = 1
        failed = expectation(description: "stream reported as failing to connect")
        player.play(url: URL(string: "http://127.0.0.1:\(port)/stream")!)
        if pausingWhileConnecting { player.pause() }
        wait(for: [failed!], timeout: 5)
        player.stop()
    }

    func streamingPlayerDidFailToConnect(after timeout: TimeInterval) { failed?.fulfill() }

    func streamingPlayerDidChangeState(_ state: AudioPlayerState) {}
    func streamingPlayerDidFinishPlaying() {}
    func streamingPlayerDidUpdateSpectrum(_ levels: [Float]) {}
    func streamingPlayerDidUpdatePCM(_ samples: [Float]) {}
    func streamingPlayerDidUpdateStereoPCM(left: [Float], right: [Float], sampleRate: Double) {}
    func streamingPlayerDidUpdateFullStereoPCM(left: [Float], right: [Float], sampleRate: Double) {}
    func streamingPlayerDidDetectFormat(sampleRate: Int, channels: Int) {}
    func streamingPlayerDidEncounterError(_ error: AudioPlayerError) {}
    func streamingPlayerDidReceiveMetadata(_ metadata: [String: String]) {}
}
