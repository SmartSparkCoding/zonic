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

        // Put the stored login back before the first load, then keep it up to date.
        SessionVault.shared.attach(to: configuration.websiteDataStore)
        if let bootstrap = SessionVault.shared.storageBootstrapScript() {
            controller.addUserScript(
                WKUserScript(source: bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }

        loadHome()
    }

    func loadHome() {
        webView.load(URLRequest(url: Self.homeURL))
    }

    func command(_ action: String) {
        webView.evaluateJavaScript("window.__zonic && window.__zonic.command('\(action)');") { [weak self] _, _ in
            self?.refreshState()
        }
    }

    /// Asks the page for a fresh snapshot, so the chrome catches up without waiting for
    /// the next poll.
    func refreshState() {
        webView.evaluateJavaScript("window.__zonic && window.__zonic.tick();", completionHandler: nil)
    }

    /// Jumps inside the current track. The page reports how it managed it, which is what
    /// the scrubber and the menu items use to decide whether to explain themselves.
    func seek(to seconds: Double, completion: ((String) -> Void)? = nil) {
        webView.evaluateJavaScript("window.__zonic ? window.__zonic.seekTo(\(seconds)) : 'missing';") { result, _ in
            completion?(result as? String ?? "missing")
            self.refreshState()
        }
    }

    func seek(by delta: Double) {
        webView.evaluateJavaScript("window.__zonic ? window.__zonic.seekBy(\(delta)) : 'missing';") { _, _ in
            self.refreshState()
        }
    }

    func seek(fraction: Double) {
        let clamped = min(1, max(0, fraction))
        webView.evaluateJavaScript("window.__zonic ? window.__zonic.seekFraction(\(clamped)) : 'missing';") { _, _ in
            self.refreshState()
        }
    }

    /// Pushes the user's player preferences into the page, which needs them for the
    /// finish-the-track fallback.
    func syncOptions() {
        let finish = ThemeManager.shared.finishTrackSkips ? "true" : "false"
        webView.evaluateJavaScript(
            "window.__zonic && window.__zonic.options({ finishTrack: \(finish) });",
            completionHandler: nil
        )
    }

    /// Diagnostics for the "copy player diagnostics" menu item.
    func diagnostics(_ completion: @escaping (String) -> Void) {
        webView.evaluateJavaScript(
            "JSON.stringify(window.__zonic ? window.__zonic.debug() : null);"
        ) { [weak self] result, _ in
            let page = result as? String ?? "no bridge"
            guard let self else {
                completion(page)
                return
            }
            self.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let amazonCookies = cookies.filter { $0.domain.lowercased().contains("amazon") }
                let sessionScoped = amazonCookies.filter { $0.expiresDate == nil }.count
                let lines = [
                    "login cookies in store: \(amazonCookies.count) (\(sessionScoped) session-scoped)",
                    "login cookies in vault: \(SessionVault.shared.storedCookieCount)",
                    "page storage keys in vault: \(SessionVault.shared.storedStorageKeyCount)",
                    "vault file: \(SessionVault.shared.vaultPath)",
                    "last.fm calls:",
                    Scrobbler.shared.logText,
                    "page: \(page)"
                ]
                completion(lines.joined(separator: "\n"))
            }
        }
    }

    func zoom(by delta: Double) {
        webView.pageZoom = min(2.2, max(0.65, webView.pageZoom + delta))
    }

    func resetZoom() {
        webView.pageZoom = 1.0
    }

    // MARK: - Theme

    /// Installs (or removes) the page skin. Runs after every load and on theme changes.
    func applyTheme() {
        let css = ThemeManager.shared.pageCSS()
        guard !css.isEmpty else {
            webView.evaluateJavaScript(
                "var el = document.getElementById('zonic-theme'); if (el) { el.remove(); }",
                completionHandler: nil
            )
            return
        }

        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        let js = """
        (function () {
          var el = document.getElementById('zonic-theme');
          if (!el) {
            el = document.createElement('style');
            el.id = 'zonic-theme';
            (document.head || document.documentElement).appendChild(el);
          }
          el.textContent = '\(escaped)';
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
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
            isEditing: body["editing"] as? Bool ?? false,
            position: (body["position"] as? NSNumber)?.doubleValue ?? 0,
            duration: (body["duration"] as? NSNumber)?.doubleValue ?? 0,
            canSeek: body["canSeek"] as? Bool ?? false
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
        applyTheme()
        syncOptions()
        refreshState()
        // A page finishing is when the login is most likely to have just changed.
        SessionVault.shared.capture()
        SessionVault.shared.captureStorage(from: webView)
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
