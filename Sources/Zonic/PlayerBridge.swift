import AppKit

/// Shared command surface so the menu bar, the window chrome and the media keys all
/// drive the same web view.
final class PlayerBridge {
    static let shared = PlayerBridge()

    weak var web: WebController?

    func handleRemote(_ command: String) {
        guard let web else { return }
        switch command {
        case "play", "pause", "next", "previous":
            web.command(command)
        case "toggle":
            web.command(web.state.isPlaying ? "pause" : "play")
        default:
            break
        }
    }

    @objc func playPause(_ sender: Any?) {
        handleRemote("toggle")
    }

    @objc func nextTrack(_ sender: Any?) {
        handleRemote("next")
    }

    @objc func previousTrack(_ sender: Any?) {
        handleRemote("previous")
    }

    @objc func reloadPage(_ sender: Any?) {
        web?.webView.reload()
    }

    @objc func goBack(_ sender: Any?) {
        guard let web, web.webView.canGoBack else { return }
        web.webView.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        guard let web, web.webView.canGoForward else { return }
        web.webView.goForward()
    }

    @objc func openHome(_ sender: Any?) {
        web?.loadHome()
    }

    @objc func zoomIn(_ sender: Any?) {
        web?.zoom(by: 0.1)
    }

    @objc func zoomOut(_ sender: Any?) {
        web?.zoom(by: -0.1)
    }

    @objc func zoomReset(_ sender: Any?) {
        web?.resetZoom()
    }

    @objc func cycleAppearance(_ sender: Any?) {
        ThemeManager.shared.cycle()
    }
}
