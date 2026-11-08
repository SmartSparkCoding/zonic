import AppKit
import WebKit

final class WebController: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let webView: WKWebView

    var onStateChange: ((PlayerState) -> Void)?
    var onLoading: ((Bool) -> Void)?
    var onNavigate: (() -> Void)?

    private(set) var state = PlayerState.empty

    static let homeURL = URL(string: "https://music.amazon.com")!
    private static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let controller = WKUserContentController()
        configuration.userContentController = controller

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        controller.add(self, name: "zonicState")
        controller.addUserScript(
            WKUserScript(source: Bridge.injectedScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = Self.browserUserAgent
        webView.allowsBackForwardNavigationGestures = true
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        loadHome()
    }

    func loadHome() {
        webView.load(URLRequest(url: Self.homeURL))
    }

    func command(_ action: String) {
        let js = "window.__zonic && window.__zonic.command('\(action)');"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func zoom(by delta: Double) {
        webView.pageZoom = min(2.2, max(0.65, webView.pageZoom + delta))
    }

    func resetZoom() {
        webView.pageZoom = 1.0
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "zonicState", let body = message.body as? [String: Any] else { return }

        let artworkString = body["artwork"] as? String
        let next = PlayerState(
            title: (body["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            artist: (body["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            album: (body["album"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            artworkURL: artworkString.flatMap(URL.init(string:)),
            isPlaying: body["playing"] as? Bool ?? false,
            isEditing: body["editing"] as? Bool ?? false
        )

        guard next != state else { return }
        state = next
        // Now Playing metadata is deliberately not pushed from here. WebKit registers its own
        // Now Playing session for a WKWebView with playing media, and claiming the seat as well
        // made macOS show Zonic twice in Control Center. The page's Media Session is the single
        // owner: it supplies the title, artist and artwork, and it receives the hardware keys.
        onStateChange?(next)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        onLoading?(true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoading?(false)
        onNavigate?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onLoading?(false)
        onNavigate?()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onLoading?(false)
        onNavigate?()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        if !["http", "https", "about", "data", "blob"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        let host = url.host?.lowercased() ?? ""
        let amazonHost = host.contains("amazon.") || host.hasSuffix(".amazon.com") || host.hasSuffix(".amazon.co.uk")
        let assetHost = host.contains("media-amazon.com") || host.contains("ssl-images-amazon.com") || host.contains("amazonaws.com")

        if !amazonHost && !assetHost,
           navigationAction.targetFrame?.isMainFrame == true,
           navigationAction.navigationType == .linkActivated {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Amazon sign-in can open a new window; keep it inside the app instead.
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = webView.title ?? "Amazon Music"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }
}
