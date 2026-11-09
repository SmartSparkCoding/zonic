import AppKit

/// One window for the things worth changing: the palette, the page skin, the player
/// controls, scrobbling and the update check.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let stack = NSStackView()

    private let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let swatch = PaletteSwatchView()
    private let skinCheck = NSButton(checkboxWithTitle: "Recolour the Amazon Music page to match the theme", target: nil, action: nil)
    private let crossfadePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let seekCheck = NSButton(checkboxWithTitle: "Show a scrubber and allow skipping inside a track", target: nil, action: nil)
    private let finishCheck = NSButton(checkboxWithTitle: "When Amazon refuses a skip, finish the track so the next one starts", target: nil, action: nil)
    private let updateCheck = NSButton(checkboxWithTitle: "Check for updates automatically", target: nil, action: nil)

    private let lastfmCheck = NSButton(checkboxWithTitle: "Scrobble to Last.fm", target: nil, action: nil)
    private let keyField = NSTextField()
    private let secretField = NSSecureTextField()
    private let connectButton = NSButton(title: "Connect Last.fm", target: nil, action: nil)
    private let lastfmStatus = NSTextField(labelWithString: "")
    private let versionLabel = NSTextField(labelWithString: "")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Zonic Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        window.delegate = self
        build()
        refresh()

        for name in [Notification.Name.themeDidChange, .lastfmStatusDidChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: name, object: nil)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func present() {
        refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Layout

    private func build() {
        guard let content = window?.contentView else { return }

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        content.addSubview(scroll)

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20)
        ])

        buildThemeSection()
        buildPlaybackSection()
        buildLastFMSection()
        buildUpdatesSection()
    }

    private func buildThemeSection() {
        stack.addArrangedSubview(header("Theme"))

        themePopup.target = self
        themePopup.action = #selector(themeChanged)
        for palette in Palette.all {
            let item = NSMenuItem(title: palette.name, action: nil, keyEquivalent: "")
            item.representedObject = palette.id
            themePopup.menu?.addItem(item)
        }
        stack.addArrangedSubview(themePopup)

        swatch.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(swatch)
        NSLayoutConstraint.activate([
            swatch.heightAnchor.constraint(equalToConstant: 22),
            swatch.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        skinCheck.target = self
        skinCheck.action = #selector(skinToggled)
        skinCheck.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(skinCheck)
        stack.addArrangedSubview(note("The page is repainted from the palette: colours, backgrounds, controls and scrollbars. Album art is left alone. Amazon ships hashed class names, so a redesign can leave patches."))
    }

    private func buildPlaybackSection() {
        stack.addArrangedSubview(header("Playback"))

        seekCheck.target = self
        seekCheck.action = #selector(seekToggled)
        seekCheck.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(seekCheck)

        finishCheck.target = self
        finishCheck.action = #selector(finishToggled)
        finishCheck.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(finishCheck)

        stack.addArrangedSubview(note("Crossfade between tracks"))
        for seconds in [0, 2, 4, 6, 8] {
            let item = NSMenuItem(title: seconds == 0 ? "Off" : "\(seconds) seconds", action: nil, keyEquivalent: "")
            item.representedObject = seconds
            crossfadePopup.menu?.addItem(item)
        }
        crossfadePopup.target = self
        crossfadePopup.action = #selector(crossfadeChanged)
        crossfadePopup.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(crossfadePopup)
        stack.addArrangedSubview(note("Fades the tail of the outgoing track and the head of the incoming one. A truly overlapping crossfade needs two decoders, and the DRM stream in the web view will not give up that, so this is a fade either side of the boundary rather than two songs playing over each other."))
        stack.addArrangedSubview(note("Amazon counts skip presses per hour on its side, so nothing here can lift that. Finishing a track is a different path to the next song: playback ends naturally and the queue rolls on. Skipping inside a track drives Amazon's own progress bar."))
    }

    private func buildLastFMSection() {
        stack.addArrangedSubview(header("Last.fm"))

        lastfmCheck.target = self
        lastfmCheck.action = #selector(lastfmToggled)
        lastfmCheck.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(lastfmCheck)

        lastfmStatus.font = .systemFont(ofSize: 11)
        lastfmStatus.textColor = .secondaryLabelColor
        lastfmStatus.lineBreakMode = .byWordWrapping
        lastfmStatus.maximumNumberOfLines = 4
        stack.addArrangedSubview(lastfmStatus)

        keyField.placeholderString = "API key"
        keyField.font = .systemFont(ofSize: 12)
        keyField.target = self
        keyField.action = #selector(keysChanged)
        keyField.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(keyField)
        NSLayoutConstraint.activate([keyField.widthAnchor.constraint(equalTo: stack.widthAnchor)])

        secretField.placeholderString = "Shared secret"
        secretField.font = .systemFont(ofSize: 12)
        secretField.target = self
        secretField.action = #selector(keysChanged)
        secretField.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(secretField)
        NSLayoutConstraint.activate([secretField.widthAnchor.constraint(equalTo: stack.widthAnchor)])

        connectButton.target = self
        connectButton.action = #selector(connectTapped)
        connectButton.bezelStyle = .rounded
        connectButton.controlSize = .small
        stack.addArrangedSubview(connectButton)

        let testButton = NSButton(title: "Send Test Scrobble", target: self, action: #selector(testScrobble))
        testButton.bezelStyle = .rounded
        testButton.controlSize = .small
        stack.addArrangedSubview(testButton)

        stack.addArrangedSubview(note("Create an API account at last.fm/api/account/create, paste the key and secret, then press Connect. Zonic opens your browser to approve itself; press Connect again afterwards. Keys live in this app's preferences, not the keychain."))
    }

    private func buildUpdatesSection() {
        stack.addArrangedSubview(header("Updates"))

        updateCheck.target = self
        updateCheck.action = #selector(updateToggled)
        updateCheck.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(updateCheck)

        let checkNow = NSButton(title: "Check for Updates Now", target: Updater.shared, action: #selector(Updater.checkNow(_:)))
        checkNow.bezelStyle = .rounded
        checkNow.controlSize = .small
        stack.addArrangedSubview(checkNow)

        versionLabel.font = .systemFont(ofSize: 10)
        versionLabel.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(versionLabel)
    }

    private func header(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 10)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([label.widthAnchor.constraint(equalToConstant: 420)])
        return label
    }

    // MARK: - State

    @objc func refresh() {
        let palette = ThemeManager.shared.palette
        if let index = Palette.all.firstIndex(where: { $0.id == palette.id }) {
            themePopup.selectItem(at: index)
        }
        swatch.palette = palette
        skinCheck.state = ThemeManager.shared.skinsPage ? .on : .off
        let seconds = ThemeManager.shared.crossfadeSeconds
        let options = [0, 2, 4, 6, 8]
        crossfadePopup.selectItem(at: options.firstIndex(where: { $0 == seconds }) ?? 2)
        seekCheck.state = ThemeManager.shared.seekControlsEnabled ? .on : .off
        finishCheck.state = ThemeManager.shared.finishTrackSkips ? .on : .off
        updateCheck.state = ThemeManager.shared.autoCheckUpdates ? .on : .off

        let scrobbler = Scrobbler.shared
        lastfmCheck.state = scrobbler.isEnabled ? .on : .off
        if keyField.currentEditor() == nil { keyField.stringValue = scrobbler.apiKey }
        if secretField.currentEditor() == nil { secretField.stringValue = scrobbler.apiSecret }

        if scrobbler.isConnected {
            connectButton.title = "Disconnect"
        } else if scrobbler.hasPendingToken {
            connectButton.title = "Finish Connecting"
        } else {
            connectButton.title = "Connect Last.fm"
        }
        let message = scrobbler.lastMessage
        lastfmStatus.stringValue = message.isEmpty ? scrobbler.statusLine : "\(scrobbler.statusLine)\n\(message)"
        versionLabel.stringValue = "Zonic \(Updater.shared.currentVersion)"
    }

    @objc private func themeChanged() {
        guard let id = themePopup.selectedItem?.representedObject as? String else { return }
        ThemeManager.shared.set(Palette.palette(withID: id))
    }

    @objc private func crossfadeChanged() {
        guard let seconds = crossfadePopup.selectedItem?.representedObject as? Int else { return }
        ThemeManager.shared.crossfadeSeconds = seconds
    }

    @objc private func skinToggled() {
        ThemeManager.shared.skinsPage = skinCheck.state == .on
    }

    @objc private func seekToggled() {
        ThemeManager.shared.seekControlsEnabled = seekCheck.state == .on
    }

    @objc private func finishToggled() {
        ThemeManager.shared.finishTrackSkips = finishCheck.state == .on
    }

    @objc private func updateToggled() {
        ThemeManager.shared.autoCheckUpdates = updateCheck.state == .on
    }

    @objc private func lastfmToggled() {
        Scrobbler.shared.isEnabled = lastfmCheck.state == .on
    }

    @objc private func keysChanged() {
        Scrobbler.shared.apiKey = keyField.stringValue
        Scrobbler.shared.apiSecret = secretField.stringValue
        refresh()
    }

    /// Ignores the listening rules on purpose: it either lands on Last.fm or shows the
    /// exact reason it did not, which is the whole point of the button.
    @objc private func testScrobble() {
        keysChanged()
        Scrobbler.shared.testScrobble()
        refresh()
    }

    @objc private func connectTapped() {
        keysChanged()
        let scrobbler = Scrobbler.shared
        if scrobbler.isConnected {
            scrobbler.signOut()
        } else {
            scrobbler.finishAuth()
        }
        refresh()
    }
}

/// Top-left origin, so a stack view inside a scroll view starts at the top.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Five chips showing the palette, so picking a theme is not a guess.
final class PaletteSwatchView: NSView {
    var palette: Palette = .system {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let colors = [
            palette.backgroundColor,
            palette.surfaceColor,
            palette.mutedColor,
            palette.accentColor,
            palette.foregroundColor
        ]

        let gap: CGFloat = 6
        let width = (bounds.width - gap * CGFloat(colors.count - 1)) / CGFloat(colors.count)
        let radius: CGFloat = 6

        for (index, color) in colors.enumerated() {
            let rect = NSRect(
                x: CGFloat(index) * (width + gap),
                y: 0,
                width: width,
                height: bounds.height
            )
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            color.setFill()
            path.fill()
        }

        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        outline.lineWidth = 1
        outline.stroke()
    }
}
