import FlyingFox
import FlyingSocks
import Foundation

/// What `LocalMediaServer` answers under `/viscast/` (any thread): `live.m3u8` and `seg-N.ts` for a
/// Chromecast, `live.ts` (endless) for DLNA; 404 when no visualization cast is serving.
extension VisualizationCast {
    nonisolated static func httpResponse(for request: HTTPRequest, includeBody: Bool) -> HTTPResponse {
        guard let encoder = serving.withLockUnchecked({ $0 }) else { return HTTPResponse(statusCode: .notFound) }
        var headers: [HTTPHeader: String] = [
            HTTPHeader("Access-Control-Allow-Origin"): "*",
            HTTPHeader("Cache-Control"): "no-cache",
        ]
        if request.headers[HTTPHeader("getcontentFeatures.dlna.org")] == "1" {
            headers[HTTPHeader("contentFeatures.dlna.org")] = LocalMediaServer.dlnaLiveContentFeatures
            headers[HTTPHeader("transferMode.dlna.org")] = "Streaming"
        }
        let name = (request.path as NSString).lastPathComponent
        let body: () -> HTTPBodySequence
        if name == "live.m3u8", let playlist = encoder.playlist() {
            headers[.contentType] = "application/vnd.apple.mpegurl"
            body = { HTTPBodySequence(data: Data(playlist.utf8)) }
        } else if name == "live.ts" {
            NSLog("VisualizationCast: %@ live.ts from %@ (%@)", request.method.rawValue,
                  request.remoteIPAddress ?? "?", request.headers[HTTPHeader("User-Agent")] ?? "-")
            headers[.contentType] = "video/mp2t"
            body = { HTTPBodySequence(from: LiveBytes(stream: encoder.liveBody())) }
        } else if name.hasPrefix("seg-"), name.hasSuffix(".ts"),
                  let sequence = Int(name.dropFirst(4).dropLast(3)), let data = encoder.segment(sequence) {
            headers[.contentType] = "video/mp2t"
            body = { HTTPBodySequence(data: data) }
        } else {
            return HTTPResponse(statusCode: .notFound)
        }
        // A Samsung HEADs before every GET, and `Content-Length: 0` (FlyingFox's answer to an empty
        // body) tells it the stream is empty. FlyingFox only says "chunked" for a body of unknown
        // length, so a HEAD gets an empty one (its 5-byte terminator) on a closing connection.
        guard includeBody else {
            headers[HTTPHeader("Connection")] = "close"
            return HTTPResponse(statusCode: .ok, headers: headers,
                                body: HTTPBodySequence(from: LiveBytes(stream: AsyncStream { $0.finish() })))
        }
        return HTTPResponse(statusCode: .ok, headers: headers, body: body())
    }

    /// The encoder's segments as the byte sequence FlyingFox sends (chunked, no length).
    private struct LiveBytes: AsyncBufferedSequence, @unchecked Sendable {
        typealias Element = UInt8
        let stream: AsyncStream<Data>

        func makeAsyncIterator() -> Iterator { Iterator(base: stream.makeAsyncIterator()) }

        struct Iterator: AsyncBufferedIteratorProtocol {
            var base: AsyncStream<Data>.Iterator
            private var pending: [UInt8] = []
            private var index = 0

            init(base: AsyncStream<Data>.Iterator) { self.base = base }

            mutating func nextBuffer(suggested count: Int) async throws -> [UInt8]? {
                if index < pending.count {
                    defer { index = pending.count }
                    return Array(pending[index...])
                }
                guard let data = await base.next() else { return nil }
                pending = []
                index = 0
                return [UInt8](data)
            }

            mutating func next() async throws -> UInt8? {
                if index >= pending.count {
                    guard let data = await base.next(), !data.isEmpty else { return nil }
                    pending = [UInt8](data)
                    index = 0
                }
                defer { index += 1 }
                return pending[index]
            }
        }
    }
}
