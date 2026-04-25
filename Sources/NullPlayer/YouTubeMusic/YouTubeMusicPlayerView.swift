import AppKit
import WebKit

final class YouTubeMusicPlayerView: NSView, WKScriptMessageHandler {
    private let webView: WKWebView
    private let statusLabel = NSTextField(labelWithString: "YouTube Music")

    override init(frame frameRect: NSRect) {
        let contentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frameRect)

        contentController.add(self, name: "nullplayerYouTube")
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])

        YouTubeMusicController.shared.playerView = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func load(track: YouTubeMusicTrack, autoplay: Bool) {
        statusLabel.stringValue = track.displayTitle
        if track.kind == .search {
            webView.load(URLRequest(url: track.sourceURL))
            return
        }
        let html = makePlayerHTML(track: track, autoplay: autoplay)
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }

    func play() {
        evaluate("player && player.playVideo && player.playVideo();")
    }

    func pause() {
        evaluate("player && player.pauseVideo && player.pauseVideo();")
    }

    func stop() {
        evaluate("player && player.stopVideo && player.stopVideo();")
    }

    func seek(to seconds: TimeInterval) {
        evaluate("player && player.seekTo && player.seekTo(\(max(0, seconds)), true);")
    }

    func seek(by seconds: TimeInterval) {
        evaluate("""
        if (player && player.getCurrentTime && player.seekTo) {
          player.seekTo(Math.max(0, player.getCurrentTime() + (\(seconds))), true);
        }
        """)
    }

    func setVolume(_ volume: Int) {
        evaluate("player && player.setVolume && player.setVolume(\(max(0, min(100, volume))));")
    }

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        DispatchQueue.main.async {
            guard message.name == "nullplayerYouTube" else { return }
            if let body = message.body as? [String: Any],
               let type = body["type"] as? String,
               type == "state",
               let rawState = body["value"] as? Int {
                YouTubeMusicController.shared.handlePlayerState(rawState)
            }
        }
    }

    private func evaluate(_ js: String) {
        webView.evaluateJavaScript(js) { _, error in
            if let error {
                NSLog("YouTubeMusicPlayerView JS error: %@", error.localizedDescription)
            }
        }
    }

    private func makePlayerHTML(track: YouTubeMusicTrack, autoplay: Bool) -> String {
        let videoID = track.videoID ?? ""
        let playlistID = track.playlistID ?? ""
        let autoplayValue = autoplay ? 1 : 0
        let initialVideo = videoID.isEmpty ? "" : escapeJS(videoID)
        let escapedPlaylistID = escapeJS(playlistID)
        let autoplayJS = autoplay ? "player.playVideo();" : ""
        let playlistJS = playlistID.isEmpty ? "" : """
              player.loadPlaylist({
                listType: 'playlist',
                list: '\(escapedPlaylistID)',
                index: 0,
                suggestedQuality: 'default'
              });
              \(autoplayJS)
        """

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body, #player { margin: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
          </style>
        </head>
        <body>
          <div id="player"></div>
          <script src="https://www.youtube.com/iframe_api"></script>
          <script>
            var player;
            function post(type, value) {
              window.webkit.messageHandlers.nullplayerYouTube.postMessage({ type: type, value: value });
            }
            function onYouTubeIframeAPIReady() {
              player = new YT.Player('player', {
                width: '100%',
                height: '100%',
                videoId: '\(initialVideo)',
                playerVars: {
                  autoplay: \(autoplayValue),
                  controls: 1,
                  rel: 0,
                  playsinline: 1
                },
                events: {
                  onReady: function() {
                    \(playlistJS)
                  },
                  onStateChange: function(event) { post('state', event.data); },
                  onError: function(event) { post('error', event.data); }
                }
              });
            }
          </script>
        </body>
        </html>
        """
    }

    private func escapeJS(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}
