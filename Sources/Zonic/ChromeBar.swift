import AppKit

/// Custom titlebar: transports on the left, what's playing in the middle, appearance
/// and overflow actions on the right. Kept deliberately thin so it reads as chrome
/// rather than a toolbar.
final class ChromeBar: NSView {
    static let height: CGFloat = 30

    let backButton = ChromeBar.makeButton("chevron.left", "Back")
    let forwardButton = ChromeBar.makeButton("chevron.right", "Forward")
    let reloadButton = ChromeBar.makeButton("arrow.clockwise", "Reload")
    let appearanceButton = ChromeBar.makeButton("paintbrush.pointed", "Theme")
    let overflowButton = ChromeBar.makeButton("ellipsis", "More")

    /// Called while the user drags the scrubber.
    var onSeek: ((Double) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Amazon Music")
    private let timeLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let scrubber = NSSlider()
    private let effect = NSVisualEffectView()
    private let tint = NSView()

    private var lastScrubAt = Date.distantPast
    private var palette = Palette.system

    private lazy var centeredTitle = titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
    private lazy var leadingTitle = titleLabel.trailingAnchor.constraint(equalTo: scrubber.leadingAnchor, constant: -10)

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
        let button = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.setButtonType(.momentaryChange)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 22),
            button.heightAnchor.constraint(equalToConstant: 20)
        ])
        return button
    }

    private func setUp() {
        wantsLayer = true

        effect.material = .headerView
        effect.blendingMode = .withinWindow
        effect.state = .followsWindowActiveState
        effect.translatesAutoresizingMaskIntoConstraints = false

        tint.wantsLayer = true
        tint.isHidden = true
        tint.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        scrubber.controlSize = .mini
        scrubber.isContinuous = true
        scrubber.target = self
        scrubber.action = #selector(scrubberMoved(_:))
        scrubber.isHidden = true
        scrubber.translatesAutoresizingMaskIntoConstraints = false

        let transport = NSStackView(views: [backButton, forwardButton, reloadButton])
        transport.orientation = .horizontal
        transport.spacing = 1
        transport.translatesAutoresizingMaskIntoConstraints = false

        let trailing = NSStackView(views: [appearanceButton, overflowButton])
        trailing.orientation = .horizontal
        trailing.spacing = 1
        trailing.translatesAutoresizingMaskIntoConstraints = false

        addSubview(effect)
        addSubview(tint)
        addSubview(transport)
        addSubview(titleLabel)
        addSubview(timeLabel)
        addSubview(scrubber)
        addSubview(trailing)
        addSubview(spinner)

        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor),

            tint.leadingAnchor.constraint(equalTo: leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: trailingAnchor),
            tint.topAnchor.constraint(equalTo: topAnchor),
            tint.bottomAnchor.constraint(equalTo: bottomAnchor),

            transport.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 78),
            transport.centerYAnchor.constraint(equalTo: centerYAnchor),

            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: transport.trailingAnchor, constant: 12),
            centeredTitle,
            centeredTitle,
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -12),

            scrubber.centerYAnchor.constraint(equalTo: centerYAnchor),
            scrubber.widthAnchor.constraint(equalToConstant: 130),
            scrubber.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -8),

            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: trailing.leadingAnchor, constant: -10),

            spinner.trailingAnchor.constraint(equalTo: trailing.leadingAnchor, constant: -6),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 14),
            spinner.heightAnchor.constraint(equalToConstant: 14)
        ])

        applyTheme(ThemeManager.shared.palette)
    }

    // MARK: - Theme

    func applyTheme(_ palette: Palette) {
        self.palette = palette

        if palette.isNative {
            effect.isHidden = false
            tint.isHidden = true
            titleLabel.textColor = .secondaryLabelColor
            timeLabel.textColor = .tertiaryLabelColor
            for button in [backButton, forwardButton, reloadButton, appearanceButton, overflowButton] {
                button.contentTintColor = .secondaryLabelColor
            }
        } else {
            effect.isHidden = true
            tint.isHidden = false
            tint.layer?.backgroundColor = palette.surfaceColor.cgColor
            titleLabel.textColor = palette.foregroundColor.withAlphaComponent(0.82)
            timeLabel.textColor = palette.mutedColor
            for button in [backButton, forwardButton, reloadButton, appearanceButton, overflowButton] {
                button.contentTintColor = palette.mutedColor
            }
        }
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
