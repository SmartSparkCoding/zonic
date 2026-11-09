import AppKit
import CoreImage

final class LyricsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// A thin progress bar that takes its colours from the palette, so it matches the theme
/// instead of the system accent.
final class LyricsProgressBar: NSView {
    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }
    var trackColor: NSColor = .quaternaryLabelColor
    var fillColor: NSColor = .controlAccentColor

    override func draw(_ dirtyRect: NSRect) {
        let height: CGFloat = 4
        let y = (bounds.height - height) / 2
        let radius = height / 2

        trackColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: y, width: bounds.width, height: height),
                     xRadius: radius, yRadius: radius).fill()

        let width = bounds.width * CGFloat(max(0, min(1, progress)))
        guard width > 0 else { return }
        fillColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: y, width: width, height: height),
                     xRadius: radius, yRadius: radius).fill()
    }
}

/// Full-window lyrics screen: artwork and transport on the left, the words on the right,
/// the current line lit in the theme accent. Modelled on Apple Music, which is the
/// benchmark for this screen.
final class LyricsView: NSView {
    var onSeek: ((TimeInterval) -> Void)?
    var onClose: (() -> Void)?
    var onTransport: ((String) -> Void)?

    private let wash = NSImageView()
    private let scrim = NSView()
    private let gradient = CAGradientLayer()
    private let cover = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let artistLabel = NSTextField(labelWithString: "")
    private let progressBar = LyricsProgressBar()
    private let elapsedLabel = NSTextField(labelWithString: "0:00")
    private let remainingLabel = NSTextField(labelWithString: "0:00")
    private let previousButton = NSButton()
    private let playButton = NSButton()
    private let nextButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let scroll = NSScrollView()
    private let document = LyricsDocumentView()
    private let closeButton = NSButton()

    private var lines: [LyricLine] = []
    private var labels: [NSTextField] = []
    private var activeIndex = -1
    private var trackKey = ""
    private var loadedArtwork: String?
    private var artworkCache: [String: NSImage] = [:]
    private var palette = ThemeManager.shared.palette

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeChanged),
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

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onClose?()
            return
        }
        super.keyDown(with: event)
    }

    override func layout() {
        super.layout()
        gradient.frame = scrim.bounds
    }

    // MARK: - Layout

    private func setUp() {
        wantsLayer = true
        layer?.backgroundColor = palette.backgroundColor.cgColor

        wash.imageScaling = .scaleAxesIndependently
        wash.alphaValue = 0.55
        addSubview(wash)

        scrim.wantsLayer = true
        gradient.colors = [
            palette.backgroundColor.withAlphaComponent(0.55).cgColor,
            palette.backgroundColor.withAlphaComponent(0.97).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        scrim.layer?.addSublayer(gradient)
        addSubview(scrim)

        cover.wantsLayer = true
        cover.layer?.cornerRadius = 14
        cover.layer?.masksToBounds = true
        cover.imageScaling = .scaleProportionallyUpOrDown
        addSubview(cover)

        titleLabel.font = .systemFont(ofSize: 21, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        artistLabel.font = .systemFont(ofSize: 15, weight: .regular)
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.maximumNumberOfLines = 1
        addSubview(artistLabel)

        addSubview(progressBar)

        for label in [elapsedLabel, remainingLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            addSubview(label)
        }
        remainingLabel.alignment = .right

        configure(previousButton, symbol: "backward.fill", tooltip: "Previous", action: #selector(previousTapped))
        configure(playButton, symbol: "play.fill", tooltip: "Play or pause", action: #selector(playTapped))
        configure(nextButton, symbol: "forward.fill", tooltip: "Next", action: #selector(nextTapped))
        for button in [previousButton, playButton, nextButton] {
            addSubview(button)
        }

        statusLabel.font = .systemFont(ofSize: 11, weight: .regular)
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
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        addSubview(closeButton)

        let pinned: [NSView] = [wash, scrim, cover, titleLabel, artistLabel, progressBar,
                                elapsedLabel, remainingLabel, previousButton, playButton,
                                nextButton, statusLabel, scroll, closeButton]
        for view in pinned {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        document.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            wash.leadingAnchor.constraint(equalTo: leadingAnchor),
            wash.trailingAnchor.constraint(equalTo: trailingAnchor),
            wash.topAnchor.constraint(equalTo: topAnchor),
            wash.bottomAnchor.constraint(equalTo: bottomAnchor),

            scrim.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrim.topAnchor.constraint(equalTo: topAnchor),
            scrim.bottomAnchor.constraint(equalTo: bottomAnchor),

            cover.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 56),
            cover.topAnchor.constraint(equalTo: topAnchor, constant: 84),
            cover.widthAnchor.constraint(equalToConstant: 250),
            cover.heightAnchor.constraint(equalToConstant: 250),

            titleLabel.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: cover.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: cover.bottomAnchor, constant: 24),

            artistLabel.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
            artistLabel.trailingAnchor.constraint(equalTo: cover.trailingAnchor),
            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

            progressBar.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: cover.trailingAnchor),
            progressBar.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 22),
            progressBar.heightAnchor.constraint(equalToConstant: 10),

            elapsedLabel.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
            elapsedLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 4),

            remainingLabel.trailingAnchor.constraint(equalTo: cover.trailingAnchor),
            remainingLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 4),

            previousButton.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
            previousButton.topAnchor.constraint(equalTo: elapsedLabel.bottomAnchor, constant: 18),
            previousButton.widthAnchor.constraint(equalToConstant: 30),
            previousButton.heightAnchor.constraint(equalToConstant: 30),

            playButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 18),
            playButton.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 34),
            playButton.heightAnchor.constraint(equalToConstant: 34),

            nextButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 18),
            nextButton.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 30),
            nextButton.heightAnchor.constraint(equalToConstant: 30),

            statusLabel.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: cover.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: previousButton.bottomAnchor, constant: 20),

            scroll.leadingAnchor.constraint(equalTo: cover.trailingAnchor, constant: 56),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -56),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 96),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -56),

            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 44),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22)
        ])

        applyPalette()
    }

    private func configure(_ button: NSButton, symbol: String, tooltip: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.toolTip = tooltip
        button.target = self
        button.action = action
    }

    // MARK: - Theme

    @objc private func themeChanged() {
        palette = ThemeManager.shared.palette
        applyPalette()
        rebuildLines(lines)
        if activeIndex >= 0 { highlight(activeIndex, force: true) }
    }

    private func applyPalette() {
        layer?.backgroundColor = palette.backgroundColor.cgColor
        gradient.colors = [
            palette.backgroundColor.withAlphaComponent(0.55).cgColor,
            palette.backgroundColor.withAlphaComponent(0.97).cgColor
        ]
        titleLabel.textColor = palette.foregroundColor
        artistLabel.textColor = palette.mutedColor
        elapsedLabel.textColor = palette.mutedColor
        remainingLabel.textColor = palette.mutedColor
        statusLabel.textColor = palette.mutedColor
        closeButton.contentTintColor = palette.mutedColor
        progressBar.trackColor = palette.mutedColor.withAlphaComponent(0.35)
        progressBar.fillColor = palette.accentColor
        for button in [previousButton, playButton, nextButton] {
            button.contentTintColor = palette.foregroundColor
        }
    }

    // MARK: - Content

    func update(state: PlayerState) {
        if titleLabel.stringValue != state.title { titleLabel.stringValue = state.title }
        if artistLabel.stringValue != state.artist { artistLabel.stringValue = state.artist }

        let symbol = state.isPlaying ? "pause.fill" : "play.fill"
        if playButton.toolTip != symbol {
            playButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Play or pause")
            playButton.toolTip = symbol
        }

        if state.duration > 0 {
            progressBar.progress = state.position / state.duration
            elapsedLabel.stringValue = PlayerState.clock(state.position)
            remainingLabel.stringValue = "-" + PlayerState.clock(max(0, state.duration - state.position))
        }

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
            cover.image = nil
            wash.image = nil
            return
        }
        let key = url.absoluteString
        if let cached = artworkCache[key] {
            apply(artwork: cached)
            return
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://music.amazon.com/", forHTTPHeaderField: "Referer")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self, let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self.artworkCache[key] = image
                self.apply(artwork: image)
            }
        }.resume()
    }

    private func apply(artwork image: NSImage) {
        cover.image = image
        wash.image = LyricsView.blurred(image, radius: 60) ?? image
    }

    /// A heavy blur of the cover, used as the backdrop so the screen picks up the record's
    /// colours instead of sitting on a flat fill.
    private static func blurred(_ image: NSImage, radius: Double) -> NSImage? {
        guard let tiff = image.tiffRepresentation, let source = CIImage(data: tiff) else { return nil }
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(source.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: source.extent) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let result = NSImage(size: rep.size)
        result.addRepresentation(rep)
        return result
    }

    private func loadLyrics(for state: PlayerState) {
        lines = []
        rebuildLines([])
        statusLabel.stringValue = "Looking for lyrics…"

        LyricsService.shared.lyrics(for: state) { [weak self] lyrics in
            guard let self else { return }
            guard self.trackKey == "\(state.artist)|\(state.title)" else { return }

            guard let lyrics else {
                self.statusLabel.stringValue = "No lyrics for this track."
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
            label.font = .systemFont(ofSize: 26, weight: .semibold)
            label.textColor = palette.foregroundColor.withAlphaComponent(0.38)
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
                    constant: previous == nil ? 24 : 20
                )
            ])
            previous = label
        }

        if let last = labels.last {
            NSLayoutConstraint.activate([
                last.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -180)
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

    private func highlight(_ index: Int, force: Bool = false) {
        guard index >= 0, index < labels.count else {
            activeIndex = -1
            return
        }
        if !force && index == activeIndex { return }
        activeIndex = index

        for (offset, label) in labels.enumerated() {
            let isActive = offset == index
            label.textColor = isActive
                ? palette.accentColor
                : palette.foregroundColor.withAlphaComponent(0.38)
            label.font = .systemFont(ofSize: isActive ? 30 : 26, weight: isActive ? .bold : .semibold)
        }

        let label = labels[index]
        let visible = scroll.contentView.bounds.height
        let documentHeight = document.frame.height
        guard documentHeight > visible else { return }

        let target = max(0, min(label.frame.minY - visible * 0.32, documentHeight - visible))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.allowsImplicitAnimation = true
            scroll.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: target))
        }
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    // MARK: - Actions

    @objc private func lineTapped(_ recogniser: NSClickGestureRecognizer) {
        guard let view = recogniser.view, view.tag < lines.count else { return }
        let time = lines[view.tag].time
        guard time >= 0 else { return }
        onSeek?(time)
    }

    @objc private func previousTapped() { onTransport?("previous") }
    @objc private func playTapped() { onTransport?("toggle") }
    @objc private func nextTapped() { onTransport?("next") }
    @objc private func closeTapped() { onClose?() }
}
