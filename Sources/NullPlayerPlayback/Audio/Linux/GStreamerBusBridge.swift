#if os(Linux)
import Foundation
import CGStreamer
import NullPlayerCore

enum GStreamerBusSignal: Sendable {
    case endOfStream
    case loadError(code: String, message: String)
    case stateChanged(PlaybackState)
    case streamStarted
    case durationChanged
}

final class GStreamerBusBridge {
    private let playbin: UnsafeMutablePointer<GstElement>
    private let bus: UnsafeMutablePointer<GstBus>
    private let backendQueue: DispatchQueue
    private let signalHandler: @Sendable (GStreamerBusSignal) -> Void

    private var running = false
    private var loopThread: Thread?

    init?(
        playbin: UnsafeMutablePointer<GstElement>,
        backendQueue: DispatchQueue,
        signalHandler: @escaping @Sendable (GStreamerBusSignal) -> Void
    ) {
        guard let bus = gst_element_get_bus(playbin) else {
            return nil
        }

        self.playbin = playbin
        self.bus = bus
        self.backendQueue = backendQueue
        self.signalHandler = signalHandler
    }

    deinit {
        stop()
        gst_object_unref(UnsafeMutableRawPointer(bus))
    }

    func start() {
        guard !running else { return }
        running = true

        let thread = Thread { [weak self] in
            self?.runLoop()
        }
        thread.name = "NullPlayer.GStreamerBus"
        thread.start()
        loopThread = thread
    }

    func stop() {
        guard running else { return }
        running = false
        loopThread?.cancel()
        loopThread = nil
    }

    private func runLoop() {
        let waitNanos: GstClockTime = 200_000_000
        let maskRaw = GST_MESSAGE_EOS.rawValue
            | GST_MESSAGE_ERROR.rawValue
            | GST_MESSAGE_STATE_CHANGED.rawValue
            | GST_MESSAGE_STREAM_START.rawValue
            | GST_MESSAGE_DURATION_CHANGED.rawValue
        let mask = GstMessageType(maskRaw)

        while running {
            if let message = gst_bus_timed_pop_filtered(bus, waitNanos, mask) {
                handle(message)
                gst_message_unref(message)
            }
        }
    }

    private func handle(_ message: UnsafeMutablePointer<GstMessage>) {
        switch message.pointee.type {
        case GST_MESSAGE_EOS:
            backendQueue.async { [signalHandler] in
                signalHandler(.endOfStream)
            }

        case GST_MESSAGE_ERROR:
            var errorPointer: UnsafeMutablePointer<GError>?
            var debugInfoPointer: UnsafeMutablePointer<gchar>?
            gst_message_parse_error(message, &errorPointer, &debugInfoPointer)

            let messageText: String
            if let errorPointer {
                messageText = String(cString: errorPointer.pointee.message)
                g_error_free(errorPointer)
            } else {
                messageText = "Unknown GStreamer error"
            }

            if let debugInfoPointer {
                g_free(UnsafeMutableRawPointer(debugInfoPointer))
            }

            backendQueue.async { [signalHandler] in
                signalHandler(.loadError(code: "gstreamer_error", message: messageText))
            }

        case GST_MESSAGE_STATE_CHANGED:
            // Keep state transitions scoped to the playbin itself.
            let playbinObject = UnsafeMutableRawPointer(playbin).assumingMemoryBound(to: GstObject.self)
            guard message.pointee.src == playbinObject else { return }

            var oldState: GstState = GST_STATE_NULL
            var newState: GstState = GST_STATE_NULL
            var pendingState: GstState = GST_STATE_VOID_PENDING
            gst_message_parse_state_changed(message, &oldState, &newState, &pendingState)
            _ = oldState
            _ = pendingState

            let playbackState: PlaybackState
            switch newState {
            case GST_STATE_PLAYING:
                playbackState = .playing
            case GST_STATE_PAUSED:
                playbackState = .paused
            default:
                playbackState = .stopped
            }

            backendQueue.async { [signalHandler] in
                signalHandler(.stateChanged(playbackState))
            }

        case GST_MESSAGE_STREAM_START:
            backendQueue.async { [signalHandler] in
                signalHandler(.streamStarted)
            }

        case GST_MESSAGE_DURATION_CHANGED:
            backendQueue.async { [signalHandler] in
                signalHandler(.durationChanged)
            }

        default:
            break
        }
    }
}
#endif
