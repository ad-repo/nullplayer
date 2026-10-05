import AppKit

extension NSImage {
    /// The largest centered square of this image, at its full pixel resolution. Used to
    /// show 16:9 YouTube thumbnails as album art. Returns `self` when already square or
    /// when there is no bitmap to crop.
    func squareCenterCropped() -> NSImage {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }
        let width = cgImage.width, height = cgImage.height
        guard width != height else { return self }
        let side = min(width, height)
        let rect = CGRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side)
        guard let cropped = cgImage.cropping(to: rect) else { return self }
        // Keep the point size proportional to the source so the art pane scales it the same way.
        let scale = size.width > 0 ? size.width / CGFloat(width) : 1
        return NSImage(cgImage: cropped, size: NSSize(width: CGFloat(side) * scale, height: CGFloat(side) * scale))
    }
}
