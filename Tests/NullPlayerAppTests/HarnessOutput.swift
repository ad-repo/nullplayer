import Foundation

/// One `write(2)` per line, straight to the descriptor, never through stdio. Shared by every
/// family's harness (`.wmz`, Audion faces); test plumbing, so family isolation does not apply.
///
/// W35, the reason this exists. In the 180-archive sweep a `CALL` line and the `SKIN` line that
/// opened the next archive landed inside one another —
///
///     CALL vSKIN Windows_XP_Media_Center_Edition.wmz
///
/// — and the 5,087 bytes that should have followed the `CALL` (the rest of that skin's trace, two
/// `PNG` lines and a `RENDER-DUMP`) never reached the file at all. That cost **two** rows: the
/// containing block is flagged `damaged` and the swallowed skin reads `not-run`, and both skins
/// measure fine when run alone.
///
/// It is byte-identical across two full sweeps and does not reproduce on a two-archive corpus, so
/// it is the buffered stream rather than anything in the content: what is lost is whatever `stdout`
/// happened to be holding. `print` writes into that buffer. A lost buffer is lost measurements, and
/// a silently missing row reads exactly like a skin that stopped drawing — the failure mode this
/// whole harness exists to escape. Writing each line unbuffered and whole removes the buffer that
/// can be lost, and `WMPRenderDumpTests.testEmitsEveryLineWholeUnderConcurrentWriters` proves the emitter itself.
///
/// The `fflush` keeps stdio's own output (XCTest's case lines) ordered against ours; without it the
/// two streams would reach the file in different orders and a block boundary could move.
enum HarnessOutput {
    private static let lock = NSLock()

    static func emit(_ line: String, to descriptor: Int32 = STDOUT_FILENO) {
        let bytes = Array((line + "\n").utf8)
        lock.lock()
        defer { lock.unlock() }
        fflush(stdout)
        bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(descriptor, buffer.baseAddress!.advanced(by: offset),
                                    buffer.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0 && (errno == EINTR || errno == EAGAIN) {
                    continue
                } else {
                    // Nothing useful is left to do with a descriptor that will not take bytes; the
                    // census's short-capture floor is what notices a truncated run.
                    return
                }
            }
        }
    }
}
