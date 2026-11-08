import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let web = WebController()
    private let chrome = ChromeBar()

    private static let chromeHeight: CGFloat = 44

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Zonic"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 760, height: 480)
        window.center()
        window.setFrameAutosaveName("ZonicMainWindow")

        super.init(window: window)

        window.delegate = self
        buildContent()
        wireActions()

        PlayerBridge.shared.web = web
        chrome.setAppearanceSymbol(ThemeManager.shared.mode.symbolName)

        web.onStateChange = { [weak self] state in self?.applyState(state) }
        web.onLoading = { [weak self] loading in self?.chrome.setLoading(loading) }
        web.onNavigate = { [weak self] in self?.syncNavigation() }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeDidChange,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func buildContent() {
        guard let window, let content = window.contentView else { return }

        chrome.translatesAutoresizingMaskIntoConstraints = false
        web.webView.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(chrome)
        content.addSubview(web.webView)

        NSLayoutConstraint.activate([
            chrome.topAnchor.constraint(equalTo: content.topAnchor),
            chrome.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            chrome.heightAnchor.constraint(equalToConstant: Self.chromeHeight),

            web.webView.topAnchor.constraint(equalTo: chrome.bottomAnchor),
            web.webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            web.webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            web.webView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    private func wireActions() {
        let bridge = PlayerBridge.shared

        chrome.backButton.target = bridge
        chrome.backButton.action = #selector(PlayerBridge.goBack(_:))
        chrome.forwardButton.target = bridge
        chrome.forwardButton.action = #selector(PlayerBridge.goForward(_:))
        chrome.reloadButton.target = bridge
        chrome.reloadButton.action = #selector(PlayerBridge.reloadPage(_:))
        chrome.appearanceButton.target = bridge
        chrome.appearanceButton.action = #selector(PlayerBridge.cycleAppearance(_:))
        chrome.overflowButton.target = self
        chrome.overflowButton.action = #selector(showOverflowMenu(_:))
    }

    private func applyState(_ state: PlayerState) {
        chrome.update(state: state)
        window?.title = state.hasTrack ? state.displayText : "Zonic"
    }

    private func syncNavigation() {
        chrome.setNavigation(canGoBack: web.webView.canGoBack, canGoForward: web.webView.canGoForward)
    }

    @objc private func themeDidChange() {
        chrome.setAppearanceSymbol(ThemeManager.shared.mode.symbolName)
    }

    @objc private func showOverflowMenu(_ sender: NSButton) {
        let menu = NSMenu()

        menu.addItem(withTitle: "Reload", action: #selector(PlayerBridge.reloadPage(_:)), keyEquivalent: "").target = PlayerBridge.shared
        menu.addItem(withTitle: "Amazon Music Home", action: #selector(PlayerBridge.openHome(_:)), keyEquivalent: "").target = PlayerBridge.shared
        menu.addItem(.separator())

        let appearance = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.delegate = ThemeManager.shared
        for mode in AppearanceMode.allCases {
            let item = NSMenuItem(title: mode.label, action: #selector(ThemeManager.select(_:)), keyEquivalent: "")
            item.target = ThemeManager.shared
            item.representedObject = mode.rawValue
            item.state = mode == ThemeManager.shared.mode ? .on : .off
            submenu.addItem(item)
        }
        appearance.submenu = submenu
        menu.addItem(appearance)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Zoom In", action: #selector(PlayerBridge.zoomIn(_:)), keyEquivalent: "").target = PlayerBridge.shared
        menu.addItem(withTitle: "Zoom Out", action: #selector(PlayerBridge.zoomOut(_:)), keyEquivalent: "").target = PlayerBridge.shared
        menu.addItem(withTitle: "Actual Size", action: #selector(PlayerBridge.zoomReset(_:)), keyEquivalent: "").target = PlayerBridge.shared

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 4), in: sender)
    }
}
