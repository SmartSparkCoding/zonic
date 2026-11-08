import AppKit

/// Custom titlebar: transports on the left, what's playing in the middle, appearance
/// and overflow actions on the right.
final class ChromeBar: NSView {
    let backButton = ChromeBar.makeButton("chevron.left", "Back")
    let forwardButton = ChromeBar.makeButton("chevron.right", "Forward")
    let reloadButton = ChromeBar.makeButton("arrow.clockwise", "Reload")
    let appearanceButton = ChromeBar.makeButton("circle.lefthalf.filled", "Appearance")
    let overflowButton = ChromeBar.makeButton("ellipsis.circle", "More")

    private let titleLabel = NSTextField(labelWithString: "Amazon Music")
    private let spinner = NSProgressIndicator()

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
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 24)
        ])
        return button
    }

    private func setUp() {
        wantsLayer = true

        let effect = NSVisualEffectView()
        effect.material = .headerView
        effect.blendingMode = .withinWindow
        effect.state = .followsWindowActiveState
        effect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effect)

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        let transport = NSStackView(views: [backButton, forwardButton, reloadButton])
        transport.orientation = .horizontal
        transport.spacing = 2
        transport.translatesAutoresizingMaskIntoConstraints = false

        let trailing = NSStackView(views: [appearanceButton, overflowButton])
        trailing.orientation = .horizontal
        trailing.spacing = 2
        trailing.translatesAutoresizingMaskIntoConstraints = false

        addSubview(transport)
        addSubview(titleLabel)
        addSubview(trailing)
        addSubview(spinner)

        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor),

            transport.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 82),
            transport.centerYAnchor.constraint(equalTo: centerYAnchor),

            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: transport.trailingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -16),

            spinner.trailingAnchor.constraint(equalTo: trailing.leadingAnchor, constant: -8),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    func update(state: PlayerState) {
        titleLabel.stringValue = state.hasTrack ? state.displayText : "Amazon Music"
        titleLabel.textColor = state.hasTrack ? .labelColor : .secondaryLabelColor
    }

    func setLoading(_ loading: Bool) {
        loading ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
    }

    func setAppearanceSymbol(_ name: String) {
        appearanceButton.image = NSImage(systemSymbolName: name, accessibilityDescription: "Appearance")
    }

    func setNavigation(canGoBack: Bool, canGoForward: Bool) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
    }
}
