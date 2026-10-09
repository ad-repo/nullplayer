/*
Copyright 2020-2021 Panic Inc.

This file is part of Audion.

Audion is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Audion is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Audion.  If not, see <https://www.gnu.org/licenses/>.
*/

// NullPlayer: adapted from FaceKit `FaceKit/AudionSliderWindow.swift` at commit `5b7c847`
// (https://gitlab.com/panicinc/facekit). The window is FaceKit's; the target/action pair became
// `onChange`, and closing on resign-key reports through `onClose`.

import AppKit

/// The volume and position sliders: a borderless popup holding one `NSSlider`, closed as soon as it
/// stops being key.
final class AudionFaceSliderWindow: NSWindow {
    private let borderWidth: CGFloat = 8.0
    private let slider: NSSlider
    /// The slider's value, and whether the mouse is up — a scrub's last report.
    var onChange: ((Double, _ finished: Bool) -> Void)?
    var onClose: (() -> Void)?

    init(size: NSSize, vertical: Bool, label: String) {
        slider = NSSlider(frame: NSRect(origin: .zero, size: size))
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hidesOnDeactivate = true
        level = .popUpMenu

        if let contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            contentView.layer?.borderWidth = 1.0
            contentView.layer?.borderColor = NSColor.gridColor.cgColor
            slider.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(slider)
            NSLayoutConstraint.activate([
                slider.topAnchor.constraint(equalTo: contentView.topAnchor, constant: borderWidth),
                slider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -borderWidth),
                slider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: borderWidth),
                slider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -borderWidth),
            ])
        }
        slider.isVertical = vertical
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.setAccessibilityLabel(label)
    }

    /// Opens with its top-left corner at `topLeft`, in screen coordinates.
    func show(topLeft: NSPoint, value: Double, range: ClosedRange<Double>) {
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        setFrameTopLeftPoint(topLeft)
        makeKeyAndOrderFront(nil)
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        close()
        onClose?()
        DispatchQueue.main.async { super.resignKey() }
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        onChange?(sender.doubleValue, NSApp.currentEvent?.type == .leftMouseUp)
    }
}
