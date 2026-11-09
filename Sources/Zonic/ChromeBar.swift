import AppKit

/// A flat icon button that lights up on hover. Solid fills instead of vibrancy, so a
/// theme like Gruvbox keeps its own colours rather than picking up the desktop behind it.
final class ChromeButton: NSButton {
    var normalTint: NSColor = .secondaryLabelColor {
        didSet { contentTintColor = normalTint }
    }
    var hoverTint: NSColor = .labelColor
    var hoverFill: NSColor = NSColor.labelColor.withAlphaComponent(0.08)

    private var hoverArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.cornerRadius = 6
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        contentTintColor = hoverTint
        layer?.backgroundColor = hoverFill.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        contentTintColor = normalTint
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

/// Custom titlebar: transports on the left, what's playing in the middle, theme, lyrics
/// and overflow actions on the right. Kept thin so it reads as chrome, not a toolbar.
final class ChromeBar: NSView {
    static let height: CGFloat = 34

    let backButton = ChromeBar.makeButton("chevron.left", "Back")
    let forwardButton = ChromeBar.makeButton("chevron.right", "Forward")
    let reloadButton = ChromeBar.makeButton("arrow.clockwise", "Reload")
    let appearanceButton = ChromeBar.makeButton("paintbrush.pointed", "Theme")
    let lyricsButton = ChromeBar.makeButton("quote.bubble", "Lyrics")
    let overflowButton = ChromeBar.makeButton("ellipsis", "More")

    /// Called while the user drags the scrubber.
    var onSeek: ((Double) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Amazon Music")
    private let timeLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let scrubber = NSSlider()
    private let surface = NSView()
    private let hairline = NSView()

    private var lastScrubAt = Date.distantPast
    private var palette = Palette.system

    private lazy var centeredTitle = titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
    private lazy var leadingTitle = titleLabel.trailingAnchor.constraint(equalTo: scrubber.leadingAnchor, constant: -12)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    override var mouseDownCanMoveWindow: Bool { true }

    static func makeButton(_ symbol: String, _ tooltip: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        let button = ChromeButton(image: image ?? NSImage(), target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.setButtonType(.momentaryChange)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 24)
        ])
        return button
    }

    private func setUp() {
        wantsLayer = true

        surface.wantsLayer = true
        surface.translatesAutoresizingMaskIntoConstraints = false

        hairline.wantsLayer = true
        hairline.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.alignment = .right
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        scrubber.controlSize = .small
        scrubber.isContinuous = true
        scrubber.target = self
        scrubber.action = #selector(scrubberMoved(_:))
        scrubber.isHidden = true
        scrubber.translatesAutoresizingMaskIntoConstraints = false

        let transport = NSStackView(views: [backButton, forwardButton, reloadButton])
        transport.orientation = .horizontal
        transport.spacing = 2
        transport.translatesAutoresizingMaskIntoConstraints = false

        let trailing = NSStackView(views: [lyricsButton, appearanceButton, overflowButton])
        trailing.orientation = .horizontal
        trailing.spacing = 2
        trailing.translatesAutoresizingMaskIntoConstraints = false

        addSubview(surface)
        addSubview(hairline)
        addSubview(transport)
        addSubview(titleLabel)
        addSubview(timeLabel)
        addSubview(scrubber)
        addSubview(trailing)
        addSubview(spinner)

        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),

            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            transport.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 84),
            transport.centerYAnchor.constraint(equalTo: centerYAnchor),

            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: transport.trailingAnchor, constant: 16),
            centeredTitle,
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -16),

            scrubber.centerYAnchor.constraint(equalTo: centerYAnchor),
            scrubber.widthAnchor.constraint(equalToConstant: 150),
            scrubber.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -10),

            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: trailing.leadingAnchor, constant: -12),
            timeLabel.widthAnchor.constraint(equalToConstant: 74),

            spinner.trailingAnchor.constraint(equalTo: trailing.leadingAnchor, constant: -8),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 14),
            spinner.heightAnchor.constraint(equalToConstant: 14)
        ])

        applyTheme(ThemeManager.shared.palette)
    }

    // MARK: - Theme

    func applyTheme(_ palette: Palette) {
        self.palette = palette

        let fill = palette.isNative ? NSColor.windowBackgroundColor : palette.surfaceColor
        surface.layer?.backgroundColor = fill.cgColor
        hairline.layer?.backgroundColor = palette.isNative
            ? NSColor.separatorColor.withAlphaComponent(0.6).cgColor
            : palette.mutedColor.withAlphaComponent(0.22).cgColor

        titleLabel.textColor = palette.isNative
            ? .secondaryLabelColor
            : palette.foregroundColor.withAlphaComponent(0.85)
        timeLabel.textColor = palette.isNative ? .tertiaryLabelColor : palette.mutedColor

        let tint = palette.isNative ? NSColor.secondaryLabelColor : palette.mutedColor
        let hover = palette.isNative ? NSColor.labelColor : palette.foregroundColor
        let hoverFill = palette.isNative
            ? NSColor.labelColor.withAlphaComponent(0.08)
            : palette.foregroundColor.withAlphaComponent(0.10)

        for button in [backButton, forwardButton, reloadButton, lyricsButton, appearanceButton, overflowButton] {
            button.contentTintColor = tint
            if let chrome = button as? ChromeButton {
                chrome.normalTint = tint
                chrome.hoverTint = hover
                chrome.hoverFill = hoverFill
            }
        }

        scrubber.trackFillColor = palette.isNative ? .controlAccentColor : palette.accentColor
        setNeedsDisplay(bounds)
    }

    // MARK: - Player state

    func update(state: PlayerState) {
        let text = state.hasTrack ? state.displayText : "Amazon Music"
        if titleLabel.stringValue != text { titleLabel.stringValue = text }
        titleLabel.textColor = state.hasTrack
            ? (palette.isNative ? NSColor.labelColor : palette.foregroundColor)
            : (palette.isNative ? NSColor.secondaryLabelColor : palette.mutedColor)

        guard !scrubber.isHidden else { return }

        // Don't fight the user mid-drag: hold the reported position for a moment after
        // they let go.
        guard Date().timeIntervalSince(lastScrubAt) > 0.8 else { return }

        let duration = max(state.duration, 0.1)
        scrubber.minValue = 0
        scrubber.maxValue = duration
        scrubber.doubleValue = min(max(state.position, 0), duration)
        scrubber.isEnabled = state.duration > 0
        let progress = state.progressText
        if timeLabel.stringValue != progress { timeLabel.stringValue = progress }
    }

    func setSeekControlsEnabled(_ enabled: Bool) {
        scrubber.isHidden = !enabled
        timeLabel.isHidden = !enabled
        titleLabel.alignment = enabled ? .right : .center
        centeredTitle.isActive = !enabled
        leadingTitle.isActive = enabled
        needsLayout = true
    }

    @objc private func scrubberMoved(_ sender: NSSlider) {
        lastScrubAt = Date()
        onSeek?(sender.doubleValue)
    }

    // MARK: - Bits

    func setLoading(_ loading: Bool) {
        loading ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
    }

    func setNavigation(canGoBack: Bool, canGoForward: Bool) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
    }
}
