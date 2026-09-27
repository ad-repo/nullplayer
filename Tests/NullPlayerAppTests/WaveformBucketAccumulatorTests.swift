import XCTest
@testable import NullPlayer

/// `addSamples` is the vectorised form of the per-frame `add(frameAmplitude:at:)` loop the waveform
/// generator used to run once per sample; it must produce the same buckets.
final class WaveformBucketAccumulatorTests: XCTestCase {

    private func perFrame(_ channels: [[Float]], totalFrames: Int64, bucketCount: Int) -> [Float] {
        var accumulator = WaveformBucketAccumulator(totalFrames: totalFrames, bucketCount: bucketCount)
        for frame in 0..<channels[0].count {
            let amplitude = channels.map { abs($0[frame]) }.max() ?? 0
            accumulator.add(frameAmplitude: amplitude, at: Int64(frame))
        }
        return accumulator.maxima
    }

    func testVectorisedChunksMatchThePerFrameLoop() {
        var generator = SystemRandomNumberGenerator()
        for (frames, buckets, chunk) in [(10_000, 4096, 16_384), (48_000, 4096, 1_000), (997, 64, 37), (5, 4096, 2)] {
            let channels = (0..<2).map { _ in
                (0..<frames).map { _ in Float.random(in: -1.3...1.3, using: &generator) }
            }
            var vectorised = WaveformBucketAccumulator(totalFrames: Int64(frames), bucketCount: buckets)
            var start = 0
            while start < frames {
                let count = min(chunk, frames - start)
                for channel in channels {
                    channel.withUnsafeBufferPointer {
                        vectorised.addSamples($0.baseAddress! + start, count: count, startingAt: Int64(start))
                    }
                }
                start += count
            }
            XCTAssertEqual(vectorised.maxima, perFrame(channels, totalFrames: Int64(frames), bucketCount: buckets),
                           "frames=\(frames) buckets=\(buckets) chunk=\(chunk)")
        }
    }

    /// An interleaved buffer is fed one channel at a time with a stride.
    func testInterleavedStrideMatchesPlanar() {
        let left: [Float] = [0.1, -0.9, 0.3, 0.2, -0.05, 0.6]
        let right: [Float] = [-0.4, 0.2, 0.8, -0.1, 0.0, 0.1]
        let interleaved = zip(left, right).flatMap { [$0, $1] }
        var strided = WaveformBucketAccumulator(totalFrames: 6, bucketCount: 3)
        interleaved.withUnsafeBufferPointer { buffer in
            strided.addSamples(buffer.baseAddress!, count: 6, stride: 2, startingAt: 0)
            strided.addSamples(buffer.baseAddress! + 1, count: 6, stride: 2, startingAt: 0)
        }
        XCTAssertEqual(strided.maxima, perFrame([left, right], totalFrames: 6, bucketCount: 3))
    }

    /// A duration hint shorter than the decoded audio pushes the overrun into the last bucket.
    func testFramesPastTheEstimateLandInTheLastBucket() {
        let samples: [Float] = [0.1, 0.2, 0.3, 0.9]
        var accumulator = WaveformBucketAccumulator(totalFrames: 2, bucketCount: 2)
        samples.withUnsafeBufferPointer { accumulator.addSamples($0.baseAddress!, count: 4, startingAt: 0) }
        XCTAssertEqual(accumulator.maxima, perFrame([samples], totalFrames: 2, bucketCount: 2))
        XCTAssertEqual(accumulator.maxima.last, 0.9)
    }
}
