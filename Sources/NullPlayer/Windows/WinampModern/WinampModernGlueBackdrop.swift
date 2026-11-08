import CoreGraphics

/// Whether a script-glued window is a **backdrop** seen through its leader's holes, rather than a
/// frame drawn over it.
///
/// A glued pair is learned from the script with no word on which of the two is in front. A frame
/// (Ebonite, Itemskin, Pure Inspired, K-jr, MoonLight) is chrome-only, above a client. Würlitzer's `avs`
/// window is a host surface (the visualization) behind two opaque images that the player's own art cuts
/// holes in, so the player is the frame and goes on top. Two pieces of evidence, never a name: the
/// follower is a host-surface container and the leader is not, and the leader's picture is transparent
/// over a real share of the follower's opaque pixels (where a leader that covered them would hide it).
enum WinampModernGlueBackdrop {
    /// The share of the follower's opaque pixels the leader must leave transparent. Measured on
    /// Würlitzer's `avs`: 0.766; see `skills/winamp-modern-skin-guide/reference/harness.md`.
    static let threshold = 0.25

    /// An alpha plane, top row first, with the window frame (points, bottom-left origin) it covers.
    struct Plane {
        let width: Int
        let height: Int
        let alpha: [UInt8]
        let frame: CGRect

        init(width: Int, height: Int, alpha: [UInt8], frame: CGRect) {
            self.width = width
            self.height = height
            self.alpha = alpha
            self.frame = frame
        }

        /// Read an outline (`WinampModernCanvas.Frame.outline`, alpha only) as bytes.
        init?(_ image: CGImage, frame: CGRect) {
            let width = image.width, height = image.height
            guard width > 0, height > 0, frame.width > 0, frame.height > 0 else { return nil }
            var bytes = [UInt8](repeating: 0, count: width * height)
            let drawn: Bool = bytes.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress,
                      let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                              bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
                else { return false }
                context.setBlendMode(.copy)
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            self.init(width: width, height: height, alpha: bytes, frame: frame)
        }

        /// The alpha under a desktop point, 0 outside the plane.
        func alpha(atX x: CGFloat, y: CGFloat) -> UInt8 {
            let column = Int(((x - frame.minX) * CGFloat(width) / frame.width).rounded(.down))
            let row = Int(((frame.maxY - y) * CGFloat(height) / frame.height).rounded(.down))
            guard column >= 0, row >= 0, column < width, row < height else { return 0 }
            return alpha[row * width + column]
        }
    }

    /// The share of `follower`'s opaque pixels lying inside `leader`'s window where `leader` is
    /// transparent; nil when none of them do (nothing to judge).
    static func transparentShare(leader: Plane, follower: Plane) -> Double? {
        var opaque = 0, open = 0
        for row in 0..<follower.height {
            let y = follower.frame.maxY - (CGFloat(row) + 0.5) * follower.frame.height / CGFloat(follower.height)
            guard y >= leader.frame.minY, y < leader.frame.maxY else { continue }
            for column in 0..<follower.width where follower.alpha[row * follower.width + column] != 0 {
                let x = follower.frame.minX + (CGFloat(column) + 0.5) * follower.frame.width / CGFloat(follower.width)
                guard x >= leader.frame.minX, x < leader.frame.maxX else { continue }
                opaque += 1
                if leader.alpha(atX: x, y: y) == 0 { open += 1 }
            }
        }
        return opaque == 0 ? nil : Double(open) / Double(opaque)
    }

    static func isBackdrop(transparentShare share: Double?) -> Bool {
        (share ?? 0) > threshold
    }
}
