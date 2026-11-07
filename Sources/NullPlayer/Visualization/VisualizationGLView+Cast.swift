import AppKit
import Accelerate
import OpenGL.GL3

/// The visualization cast's side of the GL view (`VisualizationCast`). While a cast encoder is set,
/// the GL surface's backing is pinned to the cast's size, so every engine draws its normal frame at
/// that size; it is read back for the encoder at most once per cast frame. An offscreen framebuffer
/// cannot do this: projectM 4.1 always composites into framebuffer 0
/// (`projectm_opengl_render_frame_fbo` arrives in 4.2). The window itself goes black under a note
/// (`CastOverlayLabel`): the picture there would run seconds ahead of the TV's.
extension VisualizationGLView {

    /// Render thread, context locked. Pins the surface to the cast size (or releases it once the cast
    /// is gone) and returns the size to draw at, or nil when not casting.
    func applyCastSurfaceSize(_ encoder: VisualizationCastEncoder?, to cgl: CGLContextObj) -> (Int, Int)? {
        var enabled: GLint = 0
        CGLIsEnabled(cgl, kCGLCESurfaceBackingSize, &enabled)
        guard let encoder else {
            if enabled != 0 { CGLDisable(cgl, kCGLCESurfaceBackingSize) }
            return nil
        }
        var size: [GLint] = [0, 0]
        CGLGetParameter(cgl, kCGLCPSurfaceBackingSize, &size)
        if enabled == 0 || size != [GLint(encoder.quality.width), GLint(encoder.quality.height)] {
            size = [GLint(encoder.quality.width), GLint(encoder.quality.height)]
            CGLSetParameter(cgl, kCGLCPSurfaceBackingSize, &size)
            CGLEnable(cgl, kCGLCESurfaceBackingSize)
        }
        return (encoder.quality.width, encoder.quality.height)
    }

    /// Render thread, after the engine drew into the back buffer at the cast size.
    func readBackForCast(_ encoder: VisualizationCastEncoder) {
        // The window shows the overlay, not the picture.
        defer {
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        }
        // ponytail: the readback is synchronous; if 4K60 drops frames, move to two-PBO async readback.
        guard encoder.wantsFrame(), let buffer = encoder.makePixelBuffer() else { return }
        let width = encoder.quality.width
        let height = encoder.quality.height
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), 0)
        glReadBuffer(GLenum(GL_BACK))
        glPixelStorei(GLenum(GL_PACK_ALIGNMENT), 4)
        glPixelStorei(GLenum(GL_PACK_ROW_LENGTH), GLint(rowBytes / 4))
        glReadPixels(0, 0, GLsizei(width), GLsizei(height), GLenum(GL_BGRA), GLenum(GL_UNSIGNED_INT_8_8_8_8_REV),
                     CVPixelBufferGetBaseAddress(buffer))
        glPixelStorei(GLenum(GL_PACK_ROW_LENGTH), 0)
        // GL rows are bottom-first; the encoder's are top-first.
        var image = vImage_Buffer(data: CVPixelBufferGetBaseAddress(buffer), height: vImagePixelCount(height),
                                  width: vImagePixelCount(width), rowBytes: rowBytes)
        vImageVerticalReflect_ARGB8888(&image, &image, vImage_Flags(kvImageNoFlags))
        encoder.submit(buffer)
    }

    // MARK: - Overlay

    /// Shows the note while a cast encoder is set and removes it after; runs on the main thread.
    func updateCastOverlay() {
        let existing = subviews.first { $0 is CastOverlayLabel }
        guard castEncoder != nil else { existing?.removeFromSuperview(); return }
        guard existing == nil else { return }
        let label = CastOverlayLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        label.stringValue = castOverlayText
        // The engine and preset change from the menu; the label follows until it is removed.
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak label] timer in
            MainActor.assumeIsolated {
                guard let self, let label, label.superview != nil else { return timer.invalidate() }
                label.stringValue = self.castOverlayText
            }
        }
    }

    private var castOverlayText: String {
        let device = VisualizationCast.shared.activeDevice?.name ?? "the TV"
        let preset = currentEnginePresetIndex.map { enginePresetName(at: $0) } ?? ""
        let showing = preset.isEmpty ? currentEngineType.displayName : "\(currentEngineType.displayName) — \(preset)"
        return "Casting to \(device)\n\n\(showing)\n\n"
            + "The TV's picture and sound run behind: changes can take 15–30 seconds to show there.\n"
            + "Right-click here to change the engine, preset or cast.\n"
            + "Keep this window open: closing it stops the cast."
    }

    // MARK: - Menu (`VisualizationContextMenu.Options.showsCast`)

    /// Cast Visualization ▸: the video-capable devices, Stop, and the stream's Resolution and Frame Rate.
    func castMenuItem() -> NSMenuItem {
        let castItem = NSMenuItem(title: "Cast Visualization", action: nil, keyEquivalent: "")
        guard VisualizationCast.isSupported else {
            castItem.toolTip = "Casting the visualization needs macOS 14.2 or later."
            return castItem   // no action and no submenu: the menu shows it disabled
        }
        let submenu = NSMenu()
        let activeID = VisualizationCast.shared.activeDevice?.id
        let devices = CastManager.shared.videoCapableDevices
        if devices.isEmpty {
            submenu.addItem(NSMenuItem(title: "No devices found", action: nil, keyEquivalent: ""))
        }
        for (header, type) in [("Chromecast", CastDeviceType.chromecast), ("TVs", .dlnaTV)] {
            let group = devices.filter { $0.type == type }
            guard !group.isEmpty else { continue }
            submenu.addItem(NSMenuItem(title: header, action: nil, keyEquivalent: ""))
            for device in group {
                let item = NSMenuItem(title: device.name, action: #selector(castVisualizationMenuAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = device
                item.indentationLevel = 1
                item.state = device.id == activeID ? .on : .off
                submenu.addItem(item)
            }
        }
        if activeID != nil {
            submenu.addItem(.separator())
            let stop = NSMenuItem(title: "Stop Casting Visualization", action: #selector(stopVisualizationCastMenuAction(_:)), keyEquivalent: "")
            stop.target = self
            submenu.addItem(stop)
        }
        submenu.addItem(.separator())

        let quality = VisualizationCastQuality.saved
        let resolutions = NSMenu()
        for resolution in VisualizationCastQuality.Resolution.allCases {
            let item = NSMenuItem(title: resolution.rawValue, action: #selector(setVisualizationCastResolutionMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = resolution
            item.state = quality.resolution == resolution ? .on : .off
            resolutions.addItem(item)
        }
        let resolutionItem = NSMenuItem(title: "Resolution", action: nil, keyEquivalent: "")
        resolutionItem.submenu = resolutions
        submenu.addItem(resolutionItem)

        let rates = NSMenu()
        rates.autoenablesItems = false
        for rate in VisualizationCastQuality.frameRates {
            let item = NSMenuItem(title: "\(rate) fps", action: #selector(setVisualizationCastFrameRateMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = rate
            item.state = quality.frameRate == rate ? .on : .off
            if !VisualizationCastQuality.frameRateAllowed(rate, at: quality.resolution) {
                item.isEnabled = false
                item.toolTip = "4K casts at 30 fps: TVs play 4K H.264 at up to 30."
            }
            rates.addItem(item)
        }
        let rateItem = NSMenuItem(title: "Frame Rate", action: nil, keyEquivalent: "")
        rateItem.submenu = rates
        submenu.addItem(rateItem)

        castItem.submenu = submenu
        return castItem
    }

    @objc func castVisualizationMenuAction(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? CastDevice else { return }
        VisualizationCast.shared.start(device: device, view: self)
    }

    @objc func stopVisualizationCastMenuAction(_ sender: NSMenuItem?) {
        Task { await VisualizationCast.shared.stop() }
    }

    @objc func setVisualizationCastResolutionMenuAction(_ sender: NSMenuItem) {
        guard let resolution = sender.representedObject as? VisualizationCastQuality.Resolution else { return }
        var quality = VisualizationCastQuality.saved
        quality.resolution = resolution
        quality.save()
        VisualizationCast.shared.qualityDidChange()
    }

    @objc func setVisualizationCastFrameRateMenuAction(_ sender: NSMenuItem) {
        guard let rate = sender.representedObject as? Int else { return }
        var quality = VisualizationCastQuality.saved
        quality.frameRate = rate
        quality.save()
        VisualizationCast.shared.qualityDidChange()
    }
}

/// The note over a casting visualization window. Clicks pass through, so the window's right-click
/// menu (engines, presets, the cast) works as before.
private final class CastOverlayLabel: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        alignment = .center
        textColor = NSColor(white: 0.75, alpha: 1)
        font = .systemFont(ofSize: 13)
        lineBreakMode = .byWordWrapping
        maximumNumberOfLines = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
