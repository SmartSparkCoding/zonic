import AppKit

/// The "here is what changed" window. Shown once per version, straight after an update
/// lands, and reachable again from the app menu.
final class WhatsNewWindowController: NSWindowController, NSWindowDelegate {
    private static var current: WhatsNewWindowController?
    private static let seenKey = "zonic.lastSeenVersion"

    /// Shows the notes when the running version is not the one last seen. A first launch
    /// just records the version, so nobody gets a changelog before they have played a song.
    static func presentIfNeeded() {
        let version = Updater.shared.currentVersion
        let defaults = UserDefaults.standard

        guard let seen = defaults.string(forKey: seenKey) else {
            defaults.set(version, forKey: seenKey)
            return
        }
        guard seen != version else { return }
        defaults.set(version, forKey: seenKey)
        present()
    }

    static func present() {
        if let existing = current {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = WhatsNewWindowController()
        current = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "What's new in Zonic \(Updater.shared.currentVersion)"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func windowWillClose(_ notification: Notification) {
        WhatsNewWindowController.current = nil
    }

    private func build() {
        guard let window, let content = window.contentView else { return }
        let palette = ThemeManager.shared.palette
        content.wantsLayer = true
        content.layer?.backgroundColor = palette.backgroundColor.cgColor

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.textStorage?.setAttributedString(WhatsNewWindowController.render(notes(), palette: palette))
        scroll.documentView = textView
        content.addSubview(scroll)

        let button = NSButton(title: "Nice", target: self, action: #selector(dismiss))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(button)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            scroll.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -16),

            button.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            button.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            button.widthAnchor.constraint(equalToConstant: 90)
        ])
    }

    @objc private func dismiss() {
        window?.close()
    }

    /// The notes ship inside the bundle, so this works offline and always matches the
    /// build that is running.
    private func notes() -> String {
        if let url = Bundle.main.url(forResource: "RELEASE_NOTES", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8),
           !text.isEmpty {
            return text
        }
        return "This build did not ship its notes, but it is newer than the last one."
    }

    /// A small markdown renderer: headings, bullets and paragraphs. Deliberately not a
    /// full parser, so the styling stays predictable and matches the palette.
    private static func render(_ markdown: String, palette: Palette) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 13)
        let heading = NSFont.systemFont(ofSize: 17, weight: .bold)
        let subheading = NSFont.systemFont(ofSize: 13, weight: .semibold)

        func append(_ text: String, font: NSFont, colour: NSColor, spacing: CGFloat) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = spacing
            paragraph.lineHeightMultiple = 1.08
            output.append(NSAttributedString(
                string: text + "\n",
                attributes: [.font: font, .foregroundColor: colour, .paragraphStyle: paragraph]
            ))
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("# ") {
                append(String(line.dropFirst(2)), font: heading, colour: palette.foregroundColor, spacing: 10)
            } else if line.hasPrefix("### ") {
                append(String(line.dropFirst(4)), font: subheading, colour: palette.accentColor, spacing: 6)
            } else if line.hasPrefix("## ") {
                append(String(line.dropFirst(3)), font: subheading, colour: palette.accentColor, spacing: 6)
            } else if line.hasPrefix("- ") {
                append("  •  " + String(line.dropFirst(2)), font: body, colour: palette.foregroundColor, spacing: 4)
            } else {
                append(line, font: body, colour: palette.foregroundColor, spacing: 6)
            }
        }
        return output
    }
}
