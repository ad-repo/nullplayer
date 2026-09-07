import AppKit
import XCTest
@testable import NullPlayer

/// A NullPlayer window mounted in a `.wal` skin's frame must still move when its body is dragged.
///
/// B55 gave every hosted surface a `guard hostedContext == nil else { return }` on the reasoning that
/// the skin's frame owns the drag. It owns the *chrome*: the frame's title strip measures 15–45 skin
/// pixels across the installed corpus, so a window that is a handle everywhere in Classic and
/// Original kept a ribbon — 27px of a 580px-tall projectM window on Nullsoft 2000 SP4 Lite (B57).
final class WinampModernHostedWindowDragTests: XCTestCase {

    /// Travel used by the dragging tests. Larger than `WinampModernHostedWindowDrag`'s threshold, so
    /// these presses are unambiguously drags.
    private static let travel = NSPoint(x: 40, y: 30)

    @MainActor
    func testEveryHostedSurfaceBodyDragsItsWindow() throws {
        for definition in WinampModernHostedWindowRegistry.all {
            // The waveform is the exception, and it has its own test: hosted, its seek surface *is*
            // its body.
            guard definition.id != .waveform else { continue }
            let mounted = try mount(definition)
            let origin = mounted.window.frame.origin
            drag(mounted.surface.view, from: center(of: mounted.surface.view), by: Self.travel,
                 in: mounted.window)
            XCTAssertEqual(mounted.window.frame.origin,
                           NSPoint(x: origin.x + Self.travel.x, y: origin.y + Self.travel.y),
                           "\(definition.id.rawValue) must move with a drag on its body")
        }
    }

    /// The press has to travel before it becomes a drag, or every click in a hosted window would
    /// nudge it — and the double-clicks these surfaces carry (quality mode, direction, performance
    /// mode) would move the window while they fired.
    @MainActor
    func testAPressThatBarelyMovesStaysAClick() throws {
        let mounted = try mount(XCTUnwrap(WinampModernHostedWindowRegistry.entry(id: .peppyMeter)))
        let origin = mounted.window.frame.origin
        drag(mounted.surface.view, from: center(of: mounted.surface.view),
             by: NSPoint(x: 2, y: -1), in: mounted.window)
        XCTAssertEqual(mounted.window.frame.origin, origin)
    }

    /// The surface gets first refusal on every press, so a control it owns never becomes a drag.
    /// The equalizer is the case that matters: its bands and buttons cover most of its body.
    @MainActor
    func testAControlOnAHostedSurfaceKeepsItsPress() throws {
        let mounted = try mount(XCTUnwrap(WinampModernHostedWindowRegistry.entry(id: .equalizer)))
        let origin = mounted.window.frame.origin
        // Inside the band sliders. Hosted, the layout spreads to the width the frame gives it, so
        // the bands own roughly x 145…255 of this 300×200 mount, against a background that starts
        // again at the edges — which is what the body drag has to leave alone.
        drag(mounted.surface.view, from: NSPoint(x: 200, y: 100), by: Self.travel, in: mounted.window)
        XCTAssertEqual(mounted.window.frame.origin, origin,
                       "a press on an equalizer control must not drag the window")
    }

    /// Hosted, `WaveformView.waveformRect` is the whole view — the body is one seek surface, and its
    /// handle is the frame's strip exactly as it is that view's own title bar when standalone. This
    /// pins that as deliberate rather than an oversight.
    @MainActor
    func testTheHostedWaveformBodySeeksRatherThanDragging() throws {
        let mounted = try mount(XCTUnwrap(WinampModernHostedWindowRegistry.entry(id: .waveform)))
        let origin = mounted.window.frame.origin
        drag(mounted.surface.view, from: center(of: mounted.surface.view), by: Self.travel,
             in: mounted.window)
        XCTAssertEqual(mounted.window.frame.origin, origin)
    }

    /// The Classic and Original windows are the same view classes, and none of this may reach them:
    /// standalone, the PeppyMeter has always moved from anywhere that is not its close button.
    @MainActor
    func testAStandaloneSurfaceStillDragsWithoutAHostedContext() throws {
        let window = makeWindow()
        let view = PeppyMeterView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        window.contentView = view
        addTeardownBlock { @MainActor in view.removeFromSuperview() }
        let origin = window.frame.origin
        drag(view, from: center(of: view), by: Self.travel, in: window)
        XCTAssertEqual(window.frame.origin,
                       NSPoint(x: origin.x + Self.travel.x, y: origin.y + Self.travel.y))
    }

    // MARK: - Harness

    private struct Mounted {
        let window: NSWindow
        let surface: WinampModernHostedSurface
    }

    @MainActor
    private func mount(_ definition: WinampModernHostedWindowDefinition) throws -> Mounted {
        let window = makeWindow()
        let context = WinampModernHostedSurfaceContext(
            audioEngine: WindowManager.shared.audioEngine,
            nativeWindow: { window },
            requestClose: {},
            requestFullscreen: {})
        let surface = try XCTUnwrap(definition.makeSurface?(context),
                                    "\(definition.id.rawValue) has no surface factory")
        surface.view.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        window.contentView = surface.view
        addTeardownBlock { @MainActor in surface.prepareForUITeardown() }
        return Mounted(window: window, surface: surface)
    }

    @MainActor
    private func makeWindow() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 200),
                 styleMask: [.borderless], backing: .buffered, defer: false)
    }

    @MainActor
    private func center(of view: NSView) -> NSPoint {
        NSPoint(x: view.bounds.midX, y: view.bounds.midY)
    }

    /// Press, move and release, as AppKit delivers them to the view.
    @MainActor
    private func drag(_ view: NSView, from start: NSPoint, by delta: NSPoint, in window: NSWindow) {
        let end = NSPoint(x: start.x + delta.x, y: start.y + delta.y)
        send(.leftMouseDown, at: start, to: view, in: window)
        send(.leftMouseDragged, at: end, to: view, in: window)
        send(.leftMouseUp, at: end, to: view, in: window)
    }

    @MainActor
    private func send(_ type: NSEvent.EventType, at point: NSPoint, to view: NSView,
                      in window: NSWindow) {
        guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil,
                                             eventNumber: 0, clickCount: 1, pressure: 1) else {
            return XCTFail("could not synthesize \(type)")
        }
        switch type {
        case .leftMouseDown: view.mouseDown(with: event)
        case .leftMouseDragged: view.mouseDragged(with: event)
        default: view.mouseUp(with: event)
        }
    }
}
