import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let web = WebController()
    private let chrome = ChromeBar()
    private var lyricsView: LyricsView?

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
        window.minSize = NSSize(width: 720, height: 460)
        window.center()
        window.setFrameAutosaveName("ZonicMainWindow")

        super.init(window: window)

        window.delegate = self
        buildContent()
        wireActions()

        PlayerBridge.shared.web = web
        PlayerBridge.shared.window = self

        web.onStateChange = { [weak self] state in self?.applyState(state) }
        web.onLoading = { [weak self] loading in self?.chrome.setLoading(loading) }
        web.onNavigate = { [weak self] in self?.syncNavigation() }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerSettingsDidChange),
            name: .playerSettingsDidChange,
            object: nil
        )

        applyTheme()
        chrome.setSeekControlsEnabled(ThemeManager.shared.seekControlsEnabled)
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
            chrome.heightAnchor.constraint(equalToConstant: ChromeBar.height),

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
        chrome.appearanceButton.action = #selector(PlayerBridge.cycleTheme(_:))
        chrome.overflowButton.target = self
        chrome.overflowButton.action = #selector(showOverflowMenu(_:))
        chrome.onSeek = { [weak self] seconds in self?.web.seek(to: seconds) }
    }

    private func applyState(_ state: PlayerState) {
        chrome.update(state: state)
        lyricsView?.update(state: state)
        Scrobbler.shared.observe(state)
        let title = state.hasTrack ? state.displayText : "Zonic"
        if window?.title != title { window?.title = title }
    }

    /// The lyrics screen sits above the page, so it can be richer than anything the
    /// web view itself could render.
    func toggleLyrics() {
        if let view = lyricsView {
            hideLyrics(view)
        } else {
            showLyrics()
        }
    }

    private func showLyrics() {
        guard let content = window?.contentView else { return }
        let view = LyricsView(frame: content.bounds)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.onClose = { [weak self] in self?.toggleLyrics() }
        view.onSeek = { [weak self] time in self?.web.seek(to: time) }
        view.onTransport = { action in PlayerBridge.shared.handleRemote(action) }
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.topAnchor.constraint(equalTo: content.topAnchor),
            view.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        lyricsView = view
        view.update(state: web.state)
        window?.makeFirstResponder(view)
    }

    private func hideLyrics(_ view: LyricsView) {
        view.removeFromSuperview()
        lyricsView = nil
        window?.makeFirstResponder(web.webView)
    }

    private func syncNavigation() {
        chrome.setNavigation(canGoBack: web.webView.canGoBack, canGoForward: web.webView.canGoForward)
    }

    @objc private func themeDidChange() {
        applyTheme()
        web.applyTheme()
    }

    @objc private func playerSettingsDidChange() {
        chrome.setSeekControlsEnabled(ThemeManager.shared.seekControlsEnabled)
        web.syncOptions()
        web.refreshState()
    }

    private func applyTheme() {
        chrome.applyTheme(ThemeManager.shared.palette)
    }

    @objc private func showOverflowMenu(_ sender: NSButton) {
        let menu = NSMenu()

        menu.addItem(withTitle: "Reload", action: #selector(PlayerBridge.reloadPage(_:)), keyEquivalent: "").target = PlayerBridge.shared
        menu.addItem(withTitle: "Amazon Music Home", action: #selector(PlayerBridge.openHome(_:)), keyEquivalent: "").target = PlayerBridge.shared
        menu.addItem(.separator())

        let theme = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.delegate = ThemeManager.shared
        for palette in Palette.all {
            let item = NSMenuItem(title: palette.name, action: #selector(ThemeManager.select(_:)), keyEquivalent: "")
            item.target = ThemeManager.shared
            item.representedObject = palette.id
            item.state = palette.id == ThemeManager.shared.palette.id ? .on : .off
            submenu.addItem(item)
        }
        theme.submenu = submenu
        menu.addItem(theme)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Zoom In", action: #selector(PlayerBridge.zoomIn(_:)), keyEquivalent: "").target = PlayerBridge.shared
        menu.addItem(withTitle: "Zoom Out", action: #selector(PlayerBridge.zoomOut(_:)), keyEquivalent: "").target = PlayerBridge.shared
        menu.addItem(withTitle: "Actual Size", action: #selector(PlayerBridge.zoomReset(_:)), keyEquivalent: "").target = PlayerBridge.shared
        menu.addItem(.separator())
        menu.addItem(withTitle: "Copy Player Diagnostics", action: #selector(copyDiagnostics), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Copy Page Markup", action: #selector(copyPageReport), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Love on Last.fm", action: #selector(PlayerBridge.loveTrack(_:)), keyEquivalent: "").target = PlayerBridge.shared
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(Updater.checkNow(_:)), keyEquivalent: "").target = Updater.shared
        menu.addItem(withTitle: "Settings…", action: #selector(PlayerBridge.openSettings(_:)), keyEquivalent: "").target = PlayerBridge.shared

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 4), in: sender)
    }

    /// Dumps what the page can actually see, which is the fastest way to tell whether a
    /// seek problem is DRM, a missing slider or a dead bridge.
    @objc private func copyDiagnostics() {
        web.diagnostics { [weak self] text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            let alert = NSAlert()
            alert.messageText = "Player diagnostics copied"
            alert.informativeText = text
            alert.addButton(withTitle: "OK")
            if let window = self?.window {
                alert.beginSheetModal(for: window, completionHandler: nil)
            } else {
                alert.runModal()
            }
        }
    }
    /// Copies what the page is actually painted with, for fixing the skin selectors.
    @objc private func copyPageReport() {
        web.pageReport { [weak self] text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            let alert = NSAlert()
            alert.messageText = "Page markup copied"
            alert.informativeText = "Paste it into the chat and the skin can target Amazon's real class names."
            alert.addButton(withTitle: "OK")
            if let window = self?.window {
                alert.beginSheetModal(for: window, completionHandler: nil)
            } else {
                alert.runModal()
            }
        }
    }
}
