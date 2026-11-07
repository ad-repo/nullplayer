import CoreMedia
import Foundation

/// A minimal MPEG-2 transport stream writer for one H.264 video and one AAC audio stream: what the
/// visualization cast serves (`VisualizationCastEncoder`). A Samsung TV plays only live MPEG-TS over
/// DLNA and a Chromecast plays TS HLS, and AVFoundation cannot write TS, so the stream is built here.
///
/// The output is one continuous stream. `beginSegment()` writes PAT/PMT so the next keyframe starts a
/// valid entry point; the caller cuts its HLS segments there, and a DLNA client that joins at a cut
/// sees a stream that starts cleanly.
struct MPEGTSMuxer {
    static let pmtPID: UInt16 = 0x1000
    static let videoPID: UInt16 = 0x100
    static let audioPID: UInt16 = 0x101
    /// Where timestamps start, so the first frame is not at zero.
    static let ptsOffset: UInt64 = 63_000   // 0.7 s at 90 kHz

    private var continuity: [UInt16: UInt8] = [:]
    private(set) var bytes: [UInt8] = []

    /// Hands back everything written since the last call.
    mutating func take() -> [UInt8] {
        defer { bytes.removeAll(keepingCapacity: true) }
        return bytes
    }

    mutating func beginSegment() {
        writeSection(pid: 0, table: [
            0x00,                               // table_id: PAT
            0xB0, 0x0D,                         // section length 13
            0x00, 0x01,                         // transport_stream_id
            0xC1, 0x00, 0x00,                   // version 0, current; section 0 of 0
            0x00, 0x01,                         // program 1
            0xE0 | UInt8(Self.pmtPID >> 8), UInt8(Self.pmtPID & 0xFF),
        ])
        writeSection(pid: Self.pmtPID, table: [
            0x02,                               // table_id: PMT
            0xB0, 0x17,                         // section length 23
            0x00, 0x01,                         // program 1
            0xC1, 0x00, 0x00,
            0xE0 | UInt8(Self.videoPID >> 8), UInt8(Self.videoPID & 0xFF),   // PCR PID
            0xF0, 0x00,                         // no program info
            0x1B, 0xE0 | UInt8(Self.videoPID >> 8), UInt8(Self.videoPID & 0xFF), 0xF0, 0x00,  // H.264
            0x0F, 0xE0 | UInt8(Self.audioPID >> 8), UInt8(Self.audioPID & 0xFF), 0xF0, 0x00,  // AAC ADTS
        ])
    }

    /// One access unit in Annex B form, at `pts` on the 90 kHz clock (no B-frames, so DTS = PTS).
    mutating func writeVideo(annexB: [UInt8], pts: UInt64, isKeyframe: Bool) {
        let pes = Self.pesHeader(streamID: 0xE0, payloadLength: nil, pts: pts + Self.ptsOffset) + annexB
        // PCR level with the PTS, as ffmpeg's `-muxdelay 0`.
        writePackets(pid: Self.videoPID, payload: pes, pcr: pts + Self.ptsOffset, randomAccess: isKeyframe)
    }

    /// One or more ADTS frames, the first starting at `pts`.
    mutating func writeAudio(adts: [UInt8], pts: UInt64) {
        let pes = Self.pesHeader(streamID: 0xC0, payloadLength: adts.count, pts: pts + Self.ptsOffset) + adts
        writePackets(pid: Self.audioPID, payload: pes, pcr: nil, randomAccess: false)
    }

    // MARK: - Packets

    private mutating func nextContinuity(_ pid: UInt16) -> UInt8 {
        let value = continuity[pid, default: 0]
        continuity[pid] = (value + 1) & 0x0F
        return value
    }

    private mutating func writeSection(pid: UInt16, table: [UInt8]) {
        var section = table
        let crc = Self.crc32(section)
        section += [UInt8(crc >> 24), UInt8((crc >> 16) & 0xFF), UInt8((crc >> 8) & 0xFF), UInt8(crc & 0xFF)]
        var packet: [UInt8] = [0x47, 0x40 | UInt8(pid >> 8), UInt8(pid & 0xFF), 0x10 | nextContinuity(pid), 0x00]
        packet += section
        packet += [UInt8](repeating: 0xFF, count: 188 - packet.count)
        bytes += packet
    }

    /// Splits a PES into 188-byte packets. The first may carry a PCR and the random-access flag; the
    /// last is padded with adaptation-field stuffing.
    private mutating func writePackets(pid: UInt16, payload: [UInt8], pcr: UInt64?, randomAccess: Bool) {
        var offset = 0
        var first = true
        while offset < payload.count {
            let flagged = first && (pcr != nil || randomAccess)
            let flags = flagged ? Self.adaptationFlags(pcr: pcr, randomAccess: randomAccess) : []
            let take = min(payload.count - offset, 184 - (flagged ? 1 + flags.count : 0))
            let adaptationSize = 184 - take   // whatever the payload leaves, the field fills
            bytes += [0x47, (first ? 0x40 : 0) | UInt8(pid >> 8), UInt8(pid & 0xFF),
                      (adaptationSize > 0 ? 0x30 : 0x10) | nextContinuity(pid)]
            if adaptationSize > 0 { bytes += Self.adaptationField(flags, size: adaptationSize) }
            bytes += payload[offset..<offset + take]
            offset += take
            first = false
        }
    }

    /// The adaptation field's flags byte and optional PCR (base, 6 reserved bits, extension 0).
    private static func adaptationFlags(pcr: UInt64?, randomAccess: Bool) -> [UInt8] {
        var flags: [UInt8] = [(randomAccess ? 0x40 : 0) | (pcr != nil ? 0x10 : 0)]
        if let pcr {
            let base = pcr & 0x1_FFFF_FFFF
            flags += [UInt8(base >> 25), UInt8((base >> 17) & 0xFF), UInt8((base >> 9) & 0xFF),
                      UInt8((base >> 1) & 0xFF), UInt8((base & 1) << 7) | 0x7E, 0x00]
        }
        return flags
    }

    /// An adaptation field of exactly `size` bytes, length byte first: `flags` (or a zero flags
    /// byte), then 0xFF stuffing. One byte is just a zero length.
    private static func adaptationField(_ flags: [UInt8], size: Int) -> [UInt8] {
        guard size > 1 else { return [0] }
        let body = flags.isEmpty ? [0x00] : flags
        return [UInt8(size - 1)] + body + [UInt8](repeating: 0xFF, count: size - 1 - body.count)
    }

    // MARK: - Helpers

    /// A PES header with a PTS only. Video may leave the length unset (0), which TS allows.
    static func pesHeader(streamID: UInt8, payloadLength: Int?, pts: UInt64) -> [UInt8] {
        let pesLength = payloadLength.map { $0 + 8 <= 0xFFFF ? $0 + 8 : 0 } ?? 0
        let p = pts & 0x1_FFFF_FFFF
        return [0x00, 0x00, 0x01, streamID, UInt8(pesLength >> 8), UInt8(pesLength & 0xFF),
                0x80, 0x80, 0x05,
                0x21 | UInt8((p >> 29) & 0x0E), UInt8((p >> 22) & 0xFF), UInt8((p >> 14) & 0xFE) | 1,
                UInt8((p >> 7) & 0xFF), UInt8((p << 1) & 0xFE) | 1]
    }

    /// The 7-byte ADTS header for one AAC-LC frame of `frameLength` raw bytes.
    static func adtsHeader(frameLength: Int, sampleRate: Double, channels: UInt8) -> [UInt8] {
        let rates: [Double] = [96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000, 22_050, 16_000, 12_000, 11_025, 8_000, 7_350]
        guard let index = rates.firstIndex(of: sampleRate) else { preconditionFailure("no ADTS rate for \(sampleRate) Hz") }
        let rateIndex = UInt8(index)
        let length = frameLength + 7
        return [0xFF, 0xF1,
                (1 << 6) | (rateIndex << 2) | (channels >> 2),   // profile LC (1) + rate + channel MSB
                ((channels & 3) << 6) | UInt8((length >> 11) & 0x03),
                UInt8((length >> 3) & 0xFF),
                UInt8((length & 7) << 5) | 0x1F,
                0xFC]
    }

    /// AVCC (length-prefixed) to Annex B, with an access unit delimiter, and SPS/PPS before a keyframe.
    static func annexB(_ sample: CMSampleBuffer, withParameterSets: Bool) -> [UInt8]? {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        let startCode: [UInt8] = [0, 0, 0, 1]
        var out = startCode + [0x09, 0xF0]
        if withParameterSets, let format = CMSampleBufferGetFormatDescription(sample) {
            var count = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 0, parameterSetPointerOut: nil,
                                                               parameterSetSizeOut: nil, parameterSetCountOut: &count,
                                                               nalUnitHeaderLengthOut: nil)
            for index in 0..<count {
                var pointer: UnsafePointer<UInt8>?
                var size = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index, parameterSetPointerOut: &pointer,
                                                                   parameterSetSizeOut: &size, parameterSetCountOut: nil,
                                                                   nalUnitHeaderLengthOut: nil)
                if let pointer { out += startCode + UnsafeBufferPointer(start: pointer, count: size) }
            }
        }
        let length = CMBlockBufferGetDataLength(block)
        var avcc = [UInt8](repeating: 0, count: length)
        guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &avcc) == noErr else { return nil }
        var offset = 0
        while offset + 4 <= length {
            let nalLength = Int(avcc[offset]) << 24 | Int(avcc[offset + 1]) << 16 | Int(avcc[offset + 2]) << 8 | Int(avcc[offset + 3])
            offset += 4
            guard offset + nalLength <= length else { return nil }
            out += startCode + avcc[offset..<offset + nalLength]
            offset += nalLength
        }
        return out
    }

    /// MPEG-2 CRC-32 (polynomial 0x04C11DB7, not reflected), as PSI sections use.
    static func crc32(_ data: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte) << 24
            for _ in 0..<8 { crc = crc & 0x8000_0000 != 0 ? (crc << 1) ^ 0x04C1_1DB7 : crc << 1 }
        }
        return crc
    }
}
