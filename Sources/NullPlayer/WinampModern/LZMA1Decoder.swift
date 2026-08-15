import Foundation

/// Incremental raw LZMA1 range decoder for NSIS solid streams.
///
/// NSIS stores its solid payload as a headerless LZMA1 stream: 5 property bytes (`lclppb` + a 32-bit
/// little-endian dictionary size) followed immediately by the range-coded data, with no
/// uncompressed-size field and (in practice) no end marker. The installer decodes exactly as many
/// bytes as it needs, so this decoder is *incremental*: `decode(untilOutputCount:)` produces at least
/// N output bytes, retaining full history (the LZMA dictionary) across calls. Output is bounded to
/// guard against decompression bombs.
///
/// This is a from-scratch reimplementation of the LZMA SDK reference decoder
/// (`LzmaSpec.cpp`); no third-party code is used. It is validated against the local ClassicPro
/// installer with `7zz` as a reference oracle (see the opt-in Phase 6 tests); no engine fixture is
/// committed.
final class LZMA1Decoder {
    struct Limits {
        var maximumOutputBytes: UInt64 = 128 * 1_024 * 1_024
        static let production = Limits()
    }

    private let input: [UInt8]
    private var inputPos: Int
    private let limits: Limits

    // Model parameters decoded from the property byte.
    private let lc: Int
    private let lp: Int
    private let pb: Int
    private let literalPosMask: Int
    private let posStateMask: Int

    // Range decoder state.
    private var range: UInt32 = 0xFFFF_FFFF
    private var code: UInt32 = 0

    // Decoder state machine.
    private var state = 0
    private var rep0 = 0
    private var rep1 = 0
    private var rep2 = 0
    private var rep3 = 0

    /// The decoded bytes so far — also serves as the LZMA dictionary window.
    private(set) var output: [UInt8] = []
    private(set) var reachedEndMarker = false

    // Probability models (all initialised to kBitModelTotal / 2 = 1024).
    private static let kNumStates = 12
    private static let kNumPosBitsMax = 4
    private static let kNumLenToPosStates = 4
    private static let kNumAlignBits = 4
    private static let kEndPosModelIndex = 14
    private static let kNumFullDistances = 1 << (14 >> 1) // 128
    private static let kMatchMinLen = 2

    private var isMatch = [UInt16](repeating: 1024, count: kNumStates << kNumPosBitsMax)
    private var isRep = [UInt16](repeating: 1024, count: kNumStates)
    private var isRepG0 = [UInt16](repeating: 1024, count: kNumStates)
    private var isRepG1 = [UInt16](repeating: 1024, count: kNumStates)
    private var isRepG2 = [UInt16](repeating: 1024, count: kNumStates)
    private var isRep0Long = [UInt16](repeating: 1024, count: kNumStates << kNumPosBitsMax)
    private var posSlot = [UInt16](repeating: 1024, count: kNumLenToPosStates * (1 << 6))
    private var specPos = [UInt16](repeating: 1024, count: 1 + kNumFullDistances - kEndPosModelIndex)
    private var align = [UInt16](repeating: 1024, count: 1 << kNumAlignBits)
    // Length coders: [choice, choice2] + low[16*8] + mid[16*8] + high[256].
    private var lenChoice = [UInt16](repeating: 1024, count: 2)
    private var lenLow = [UInt16](repeating: 1024, count: (1 << kNumPosBitsMax) * 8)
    private var lenMid = [UInt16](repeating: 1024, count: (1 << kNumPosBitsMax) * 8)
    private var lenHigh = [UInt16](repeating: 1024, count: 256)
    private var repLenChoice = [UInt16](repeating: 1024, count: 2)
    private var repLenLow = [UInt16](repeating: 1024, count: (1 << kNumPosBitsMax) * 8)
    private var repLenMid = [UInt16](repeating: 1024, count: (1 << kNumPosBitsMax) * 8)
    private var repLenHigh = [UInt16](repeating: 1024, count: 256)
    private var literal: [UInt16]

    /// - Parameter stream: the raw LZMA1 stream beginning with the 5 property bytes.
    init(stream: Data, limits: Limits = .production) throws {
        let bytes = [UInt8](stream)
        guard bytes.count >= 10 else {
            throw WalFailure(WalDiagnostic(.invalidArchive, "LZMA stream is too short to contain a header."))
        }
        let props = Int(bytes[0])
        guard props < 9 * 5 * 5 else {
            throw WalFailure(WalDiagnostic(.invalidArchive, "Invalid LZMA property byte \(props)."))
        }
        self.lc = props % 9
        let remainder = props / 9
        self.lp = remainder % 5
        self.pb = remainder / 5
        self.literalPosMask = (1 << lp) - 1
        self.posStateMask = (1 << pb) - 1
        self.literal = [UInt16](repeating: 1024, count: 0x300 << (lc + lp))
        self.input = bytes
        self.limits = limits

        // Skip the 5 property bytes, then initialise the range decoder from the next 5 bytes:
        // the first must be 0, the following four form the initial code (big-endian).
        self.inputPos = 5
        guard nextByte() == 0 else {
            throw WalFailure(WalDiagnostic(.invalidArchive, "LZMA range-coder header did not begin with a zero byte."))
        }
        for _ in 0..<4 { code = (code << 8) | UInt32(nextByte()) }
    }

    /// Decode until `output.count` reaches at least `count` (a match may overshoot; extra bytes are
    /// retained for later calls). Returns `false` if the end marker was hit before reaching `count`.
    @discardableResult
    func decode(untilOutputCount count: Int) throws -> Bool {
        while output.count < count {
            if reachedEndMarker { return false }
            guard UInt64(output.count) < limits.maximumOutputBytes else {
                throw WalFailure(WalDiagnostic(.totalSizeExceeded, "LZMA output exceeded the \(limits.maximumOutputBytes)-byte limit."))
            }
            try step()
        }
        return true
    }

    // MARK: - Main decode step

    private func step() throws {
        let posState = output.count & posStateMask
        if decodeBit(&isMatch, (state << Self.kNumPosBitsMax) + posState) == 0 {
            decodeLiteral()
            return
        }
        var len: Int
        if decodeBit(&isRep, state) == 1 {
            if decodeBit(&isRepG0, state) == 0 {
                if decodeBit(&isRep0Long, (state << Self.kNumPosBitsMax) + posState) == 0 {
                    // Short rep: repeat a single byte from the most recent distance.
                    state = state < 7 ? 9 : 11
                    appendMatchByte(distance: rep0)
                    return
                }
            } else {
                let dist: Int
                if decodeBit(&isRepG1, state) == 0 {
                    dist = rep1
                } else if decodeBit(&isRepG2, state) == 0 {
                    dist = rep2
                    rep2 = rep1
                } else {
                    dist = rep3
                    rep3 = rep2
                    rep2 = rep1
                }
                rep1 = rep0
                rep0 = dist
            }
            len = decodeLength(&repLenChoice, &repLenLow, &repLenMid, &repLenHigh, posState)
            state = state < 7 ? 8 : 11
        } else {
            rep3 = rep2; rep2 = rep1; rep1 = rep0
            len = decodeLength(&lenChoice, &lenLow, &lenMid, &lenHigh, posState)
            state = state < 7 ? 7 : 10
            let newDist = decodeDistance(lenSlot: len)
            if newDist == 0xFFFF_FFFF {
                reachedEndMarker = true
                return
            }
            rep0 = Int(newDist)
        }
        try copyMatch(distance: rep0, length: len + Self.kMatchMinLen)
    }

    private func decodeLiteral() {
        let prevByte = output.isEmpty ? 0 : Int(output[output.count - 1])
        let litState = ((output.count & literalPosMask) << lc) + (prevByte >> (8 - lc))
        let base = 0x300 * litState
        var symbol = 1
        if state >= 7 {
            var matchByte = Int(output[output.count - rep0 - 1])
            repeat {
                let matchBit = (matchByte >> 7) & 1
                matchByte <<= 1
                let bit = decodeBit(&literal, base + ((1 + matchBit) << 8) + symbol)
                symbol = (symbol << 1) + bit
                if matchBit != bit { break }
            } while symbol < 0x100
        }
        while symbol < 0x100 {
            symbol = (symbol << 1) + decodeBit(&literal, base + symbol)
        }
        output.append(UInt8(symbol & 0xFF))
        state = state < 4 ? 0 : (state < 10 ? state - 3 : state - 6)
    }

    private func appendMatchByte(distance: Int) {
        output.append(output[output.count - distance - 1])
    }

    private func copyMatch(distance: Int, length: Int) throws {
        guard distance < output.count else {
            throw WalFailure(WalDiagnostic(.invalidArchive, "LZMA match distance \(distance) exceeds the output history."))
        }
        var remaining = length
        while remaining > 0 {
            output.append(output[output.count - distance - 1])
            remaining -= 1
        }
    }

    // MARK: - Length and distance

    private func decodeLength(_ choice: inout [UInt16], _ low: inout [UInt16],
                              _ mid: inout [UInt16], _ high: inout [UInt16], _ posState: Int) -> Int {
        if decodeBit(&choice, 0) == 0 {
            return bitTreeDecode(&low, (posState << 3), 3)
        }
        if decodeBit(&choice, 1) == 0 {
            return 8 + bitTreeDecode(&mid, (posState << 3), 3)
        }
        return 16 + bitTreeDecode(&high, 0, 8)
    }

    private func decodeDistance(lenSlot: Int) -> UInt32 {
        let lenState = min(lenSlot, Self.kNumLenToPosStates - 1)
        let slot = bitTreeDecode(&posSlot, lenState << 6, 6)
        if slot < 4 { return UInt32(slot) }
        let numDirectBits = (slot >> 1) - 1
        var dist = (2 | (slot & 1)) << numDirectBits
        if slot < Self.kEndPosModelIndex {
            dist += bitTreeReverseDecode(&specPos, dist - slot, numDirectBits)
        } else {
            dist += Int(decodeDirectBits(numDirectBits - Self.kNumAlignBits)) << Self.kNumAlignBits
            dist += bitTreeReverseDecode(&align, 0, Self.kNumAlignBits)
        }
        return UInt32(dist)
    }

    // MARK: - Range decoder primitives

    private func nextByte() -> UInt8 {
        guard inputPos < input.count else { return 0 }
        defer { inputPos += 1 }
        return input[inputPos]
    }

    private func normalize() {
        if range < 0x0100_0000 {
            range <<= 8
            code = (code << 8) | UInt32(nextByte())
        }
    }

    private func decodeBit(_ probs: inout [UInt16], _ index: Int) -> Int {
        let prob = UInt32(probs[index])
        let bound = (range >> 11) * prob
        let bit: Int
        if code < bound {
            range = bound
            probs[index] = UInt16(prob + ((2048 - prob) >> 5))
            bit = 0
        } else {
            code &-= bound
            range &-= bound
            probs[index] = UInt16(prob - (prob >> 5))
            bit = 1
        }
        normalize()
        return bit
    }

    private func bitTreeDecode(_ probs: inout [UInt16], _ base: Int, _ numBits: Int) -> Int {
        var m = 1
        for _ in 0..<numBits { m = (m << 1) + decodeBit(&probs, base + m) }
        return m - (1 << numBits)
    }

    private func bitTreeReverseDecode(_ probs: inout [UInt16], _ base: Int, _ numBits: Int) -> Int {
        var m = 1
        var symbol = 0
        for i in 0..<numBits {
            let bit = decodeBit(&probs, base + m)
            m = (m << 1) + bit
            symbol |= bit << i
        }
        return symbol
    }

    private func decodeDirectBits(_ numBits: Int) -> UInt32 {
        var result: UInt32 = 0
        for _ in 0..<numBits {
            range >>= 1
            code &-= range
            let t = 0 &- (code >> 31)
            code &+= range & t
            normalize()
            result = (result << 1) &+ (t &+ 1)
        }
        return result
    }
}
