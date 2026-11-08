import AppKit

/// One window for the things worth changing: the palette, the page skin, the scrubber
/// and the update check.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let swatch = PaletteSwatchView()
    private let skinCheck = NSButton(checkboxWithTitle: "Recolour the Amazon Music page to match the theme", target: nil, action: nil)
    private let seekCheck = NSButton(checkboxWithTitle: "Show a scrubber and allow seeking inside a track", target: nil, action: nil)
    private let updateCheck = NSButton(checkboxWithTitle: "Check for updates automatically", target: nil, action: nil)
    private let versionLabel = NSTextField(labelWithString: "")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Zonic Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        window.delegate = self
        build()
        refresh()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
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

    func present() {
        refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Layout

    private func build() {
        guard let content = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

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
        stack.addArrangedSubview(note("Amazon controls its own layout, so this is a best-effort tint and can look patchy."))

        stack.addArrangedSubview(header("Playback"))
        seekCheck.target = self
        seekCheck.action = #selector(seekToggled)
        seekCheck.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(seekCheck)
        stack.addArrangedSubview(note("Amazon limits skipping per hour on its side, so this cannot lift that. Seeking may be refused on some tracks."))

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

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])
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
        NSLayoutConstraint.activate([label.widthAnchor.constraint(equalToConstant: 400)])
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
        seekCheck.state = ThemeManager.shared.seekControlsEnabled ? .on : .off
        updateCheck.state = ThemeManager.shared.autoCheckUpdates ? .on : .off
        versionLabel.stringValue = "Zonic \(Updater.shared.currentVersion)"
    }

    @objc private func themeChanged() {
        guard let id = themePopup.selectedItem?.representedObject as? String else { return }
        ThemeManager.shared.set(Palette.palette(withID: id))
    }

    @objc private func skinToggled() {
        ThemeManager.shared.skinsPage = skinCheck.state == .on
    }

    @objc private func seekToggled() {
        ThemeManager.shared.seekControlsEnabled = seekCheck.state == .on
    }

    @objc private func updateToggled() {
        ThemeManager.shared.autoCheckUpdates = updateCheck.state == .on
    }
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
