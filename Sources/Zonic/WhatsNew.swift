import AppKit

/// The "here is what changed" window. Shown once per version, straight after an update
/// lands, and reachable again from the app menu.
final class WhatsNewWindowController: NSWindowController, NSWindowDelegate {
    private static var current: WhatsNewWindowController?
    private static let seenKey = "zonic.lastSeenVersion"
    private static let repo = "SmartSparkCoding/zonic"

    private let version: String
    private let scrollView = NSScrollView()
    private let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 552, height: 420))

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
        let controller = WhatsNewWindowController(version: Updater.shared.currentVersion)
        current = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(version: String) {
        self.version = version
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "What's new in Zonic \(version)"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 460, height: 320)
        window.center()
        super.init(window: window)
        window.delegate = self
        build()
        loadNotes()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func windowWillClose(_ notification: Notification) {
        WhatsNewWindowController.current = nil
    }

    func windowDidResize(_ notification: Notification) {
        resizeDocument()
    }

    // MARK: - Layout

    private func build() {
        guard let window, let content = window.contentView else { return }
        let palette = ThemeManager.shared.palette
        content.wantsLayer = true
        content.layer?.backgroundColor = palette.backgroundColor.cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        // A text view built with NSTextView() has a zero frame, and a scroll view will not
        // grow its document view for you, so the window came up empty. Size it explicitly
        // and let it track the clip view's width.
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 14)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        content.addSubview(scrollView)

        let release = NSButton(title: "View release", target: self, action: #selector(openRelease))
        release.bezelStyle = .rounded
        release.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(release)

        let button = NSButton(title: "Nice", target: self, action: #selector(dismiss))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(button)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            scrollView.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -16),

            release.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            release.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),

            button.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            button.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            button.widthAnchor.constraint(equalToConstant: 90)
        ])
    }

    private func resizeDocument() {
        guard let container = textView.textContainer, let layout = textView.layoutManager else { return }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let width = max(scrollView.contentSize.width, 240)
        let height = max(used.height + textView.textContainerInset.height * 2, scrollView.contentSize.height)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    @objc private func dismiss() {
        window?.close()
    }

    @objc private func openRelease() {
        guard let url = URL(string: "https://github.com/\(Self.repo)/releases/tag/v\(version)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Notes

    /// The bundled notes appear immediately, then the release's own notes and the commits
    /// in this build replace them once GitHub answers. Cached per version, so the second
    /// open is instant and works offline.
    private func loadNotes() {
        render(bundledNotes())
        fetchRemoteNotes()
    }

    private func bundledNotes() -> String {
        if let url = Bundle.main.url(forResource: "RELEASE_NOTES", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8),
           !text.isEmpty {
            return text
        }
        return "### What changed\n- This build did not ship its notes, so here is the short version: it is newer than the one you had."
    }

    private func fetchRemoteNotes() {
        let cacheKey = "zonic.notes.\(version)"
        if let cached = UserDefaults.standard.string(forKey: cacheKey), !cached.isEmpty {
            render(cached)
            return
        }

        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases?per_page=10") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Zonic for macOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return }
            let tag = "v\(self.version)"
            guard let index = list.firstIndex(where: { ($0["tag_name"] as? String) == tag }) else { return }

            let release = list[index]
            let body = (release["body"] as? String) ?? ""
            let published = release["published_at"] as? String
            let previous = index + 1 < list.count ? (list[index + 1]["tag_name"] as? String) : nil

            self.fetchCommits(from: previous, to: tag) { commits in
                let text = Self.compose(body: body, published: published, commits: commits)
                guard !text.isEmpty else { return }
                UserDefaults.standard.set(text, forKey: cacheKey)
                DispatchQueue.main.async { self.render(text) }
            }
        }.resume()
    }

    private func fetchCommits(from previous: String?, to tag: String, completion: @escaping ([String]) -> Void) {
        guard let previous,
              let url = URL(string: "https://api.github.com/repos/\(Self.repo)/compare/\(previous)...\(tag)") else {
            completion([])
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Zonic for macOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let commits = object["commits"] as? [[String: Any]] else {
                completion([])
                return
            }
            var lines: [String] = []
            for entry in commits.reversed() {
                guard let commit = entry["commit"] as? [String: Any],
                      let message = commit["message"] as? String else { continue }
                let subject = (message.components(separatedBy: .newlines).first ?? message)
                    .trimmingCharacters(in: .whitespaces)
                if subject.isEmpty { continue }
                if subject.hasPrefix("Merge pull request") || subject.hasPrefix("Merge branch") { continue }
                lines.append(subject)
                if lines.count >= 15 { break }
            }
            completion(lines)
        }.resume()
    }

    private static func compose(body: String, published: String?, commits: [String]) -> String {
        var parts: [String] = []
        let cleaned = clean(body)
        if !cleaned.isEmpty { parts.append(cleaned) }
        if !commits.isEmpty {
            parts.append("### Commits in this build")
            parts.append(contentsOf: commits.map { "- " + $0 })
        }
        return parts.joined(separator: "\n")
    }

    /// GitHub appends a compare link to generated notes, which is noise in a small window.
    private static func clean(_ body: String) -> String {
        let kept = body
            .components(separatedBy: .newlines)
            .filter { !$0.contains("Full Changelog") }
            .joined(separator: "\n")
        return kept.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Rendering

    private func render(_ markdown: String) {
        let palette = ThemeManager.shared.palette
        textView.textStorage?.setAttributedString(Self.render(markdown, palette: palette))
        resizeDocument()
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    /// A small markdown renderer: headings, bullets, paragraphs and **bold**. Deliberately
    /// not a full parser, so the styling stays predictable and matches the palette.
    private static func render(_ markdown: String, palette: Palette) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 13)
        let heading = NSFont.systemFont(ofSize: 18, weight: .bold)
        let subheading = NSFont.systemFont(ofSize: 13, weight: .semibold)

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("# ") {
                append(output, text: String(line.dropFirst(2)), font: heading, colour: palette.foregroundColor, spacing: 10)
            } else if line.hasPrefix("### ") {
                append(output, text: String(line.dropFirst(4)), font: subheading, colour: palette.accentColor, spacing: 6)
            } else if line.hasPrefix("## ") {
                append(output, text: String(line.dropFirst(3)), font: subheading, colour: palette.accentColor, spacing: 6)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                append(output, text: "  •  " + String(line.dropFirst(2)), font: body, colour: palette.foregroundColor, spacing: 4)
            } else {
                append(output, text: line, font: body, colour: palette.foregroundColor, spacing: 6)
            }
        }
        return output
    }

    private static func append(_ output: NSMutableAttributedString,
                               text: String,
                               font: NSFont,
                               colour: NSColor,
                               spacing: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = spacing
        paragraph.lineHeightMultiple = 1.1
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)

        // Split on ** so inline bold survives without a real parser.
        for (index, piece) in text.components(separatedBy: "**").enumerated() where !piece.isEmpty {
            let cleaned = piece.replacingOccurrences(of: "`", with: "")
            output.append(NSAttributedString(string: cleaned, attributes: [
                .font: index % 2 == 1 ? bold : font,
                .foregroundColor: colour,
                .paragraphStyle: paragraph
            ]))
        }
        output.append(NSAttributedString(string: "\n", attributes: [
            .font: font,
            .foregroundColor: colour,
            .paragraphStyle: paragraph
        ]))
    }
}
