import AppKit

final class LyricsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// Full-window lyrics screen: dimmed lines, the current one lit up and bold, artwork on
/// the left. Modelled on Apple Music, which is the benchmark for this screen.
final class LyricsView: NSView {
    var onSeek: ((TimeInterval) -> Void)?
    var onClose: (() -> Void)?

    private let backdrop = NSVisualEffectView()
    private let artworkWash = NSImageView()
    private let scrim = NSView()
    private let cover = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let artistLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let scroll = NSScrollView()
    private let document = LyricsDocumentView()
    private let closeButton = NSButton()

    private var lines: [LyricLine] = []
    private var labels: [NSTextField] = []
    private var activeIndex = -1
    private var trackKey = ""
    private var loadedArtwork: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onClose?()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Layout

    private func setUp() {
        wantsLayer = true

        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 0
        addSubview(backdrop)

        artworkWash.imageScaling = .scaleAxesIndependently
        artworkWash.alphaValue = 0.32
        addSubview(artworkWash)

        scrim.wantsLayer = true
        scrim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        addSubview(scrim)

        cover.wantsLayer = true
        cover.layer?.cornerRadius = 10
        cover.layer?.masksToBounds = true
        cover.imageScaling = .scaleProportionallyUpOrDown
        addSubview(cover)

        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        artistLabel.font = .systemFont(ofSize: 15, weight: .regular)
        artistLabel.textColor = .secondaryLabelColor
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.maximumNumberOfLines = 1
        addSubview(artistLabel)

        statusLabel.font = .systemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3
        addSubview(statusLabel)

        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.verticalScrollElasticity = .allowed
        scroll.documentView = document
        addSubview(scroll)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close lyrics")
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        addSubview(closeButton)

        let pinned: [NSView] = [backdrop, artworkWash, scrim, cover, titleLabel,
                                artistLabel, statusLabel, scroll, closeButton]
        for view in pinned {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        document.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),

            artworkWash.leadingAnchor.constraint(equalTo: leadingAnchor),
            artworkWash.trailingAnchor.constraint(equalTo: trailingAnchor),
            artworkWash.topAnchor.constraint(equalTo: topAnchor),
            artworkWash.bottomAnchor.constraint(equalTo: bottomAnchor),

            scrim.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrim.topAnchor.constraint(equalTo: topAnchor),
            scrim.bottomAnchor.constraint(equalTo: bottomAnchor),

            cover.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 48),
            cover.topAnchor.constraint(equalTo: topAnchor, constant: 76),
            cover.widthAnchor.constraint(equalToConstant: 200),
            cover.heightAnchor.constraint(equalToConstant: 200),

            titleLabel.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: cover.bottomAnchor, constant: 20),
            titleLabel.widthAnchor.constraint(equalToConstant: 200),

            artistLabel.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            artistLabel.widthAnchor.constraint(equalToConstant: 200),

            statusLabel.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 14),
            statusLabel.widthAnchor.constraint(equalToConstant: 200),

            scroll.leadingAnchor.constraint(equalTo: cover.trailingAnchor, constant: 44),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -48),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 72),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -40),

            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    // MARK: - Content

    func update(state: PlayerState) {
        if titleLabel.stringValue != state.title { titleLabel.stringValue = state.title }
        if artistLabel.stringValue != state.artist { artistLabel.stringValue = state.artist }

        if let url = state.artworkURL?.absoluteString, url != loadedArtwork {
            loadedArtwork = url
            loadArtwork(state.artworkURL)
        }

        let key = "\(state.artist)|\(state.title)"
        if key != trackKey {
            trackKey = key
            activeIndex = -1
            loadLyrics(for: state)
        }

        sync(to: state.position)
    }

    private func loadArtwork(_ url: URL?) {
        guard let url else {
            artworkWash.image = nil
            cover.image = nil
            return
        }
        let request = URLRequest(url: url)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.artworkWash.image = image
                self?.cover.image = image
            }
        }.resume()
    }

    private func loadLyrics(for state: PlayerState) {
        lines = []
        rebuildLines([])
        statusLabel.stringValue = "Looking for lyrics…"

        LyricsService.shared.lyrics(for: state) { [weak self] lyrics in
            guard let self else { return }
            guard self.trackKey == "\(state.artist)|\(state.title)" else { return }

            guard let lyrics else {
                self.statusLabel.stringValue = "No lyrics found for this track."
                return
            }
            self.statusLabel.stringValue = lyrics.isSynced
                ? ""
                : "Unsynced lyrics, so they will not follow the song."
            self.lines = lyrics.isSynced
                ? lyrics.lines
                : lyrics.plain
                    .components(separatedBy: .newlines)
                    .map { LyricLine(time: -1, text: $0.trimmingCharacters(in: .whitespaces)) }
                    .filter { !$0.text.isEmpty }
            self.activeIndex = -1
            self.rebuildLines(self.lines)
        }
    }

    private func rebuildLines(_ lines: [LyricLine]) {
        labels.forEach { $0.removeFromSuperview() }
        labels = []
        document.subviews.forEach { $0.removeFromSuperview() }

        var previous: NSView?
        for (index, line) in lines.enumerated() {
            let label = NSTextField(labelWithString: line.text.isEmpty ? " " : line.text)
            label.font = .systemFont(ofSize: 23, weight: .semibold)
            label.textColor = NSColor.labelColor.withAlphaComponent(0.42)
            label.isEditable = false
            label.isSelectable = false
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            label.tag = index
            label.addGestureRecognizer(
                NSClickGestureRecognizer(target: self, action: #selector(lineTapped(_:)))
            )
            document.addSubview(label)
            labels.append(label)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: document.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: document.trailingAnchor),
                label.topAnchor.constraint(
                    equalTo: previous?.bottomAnchor ?? document.topAnchor,
                    constant: previous == nil ? 20 : 16
                )
            ])
            previous = label
        }

        if let last = labels.last {
            NSLayoutConstraint.activate([
                last.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -160)
            ])
        }
    }

    private func sync(to position: TimeInterval) {
        guard lines.contains(where: { $0.time >= 0 }) else { return }
        var index = -1
        for (offset, line) in lines.enumerated() where line.time >= 0 && line.time <= position + 0.2 {
            index = offset
        }
        guard index != activeIndex else { return }
        highlight(index)
    }

    private func highlight(_ index: Int) {
        guard index >= 0, index < labels.count else {
            activeIndex = -1
            return
        }
        activeIndex = index

        for (offset, label) in labels.enumerated() {
            let isActive = offset == index
            label.textColor = isActive
                ? NSColor.labelColor
                : NSColor.labelColor.withAlphaComponent(0.42)
            label.font = .systemFont(ofSize: 23, weight: isActive ? .bold : .semibold)
        }
        let label = labels[index]
        let visible = scroll.contentView.bounds.height
        let documentHeight = document.frame.height
        guard documentHeight > visible else { return }

        let target = max(0, min(label.frame.minY - visible * 0.35, documentHeight - visible))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            scroll.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: target))
        }
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    @objc private func lineTapped(_ recogniser: NSClickGestureRecognizer) {
        guard let view = recogniser.view, view.tag < lines.count else { return }
        let time = lines[view.tag].time
        guard time >= 0 else { return }
        onSeek?(time)
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
