import AppKit

/// A colour set for the app. Native palettes follow the macOS appearance; the rest pin
/// their own colours so the window chrome, menus and (optionally) the page match.
struct Palette {
    let id: String
    let name: String
    let isDark: Bool
    /// Native palettes defer to the system appearance instead of fixed colours.
    var isNative: Bool = false
    let background: String
    let surface: String
    let foreground: String
    let muted: String
    let accent: String

    var backgroundColor: NSColor { NSColor(hex: background) ?? .windowBackgroundColor }
    var surfaceColor: NSColor { NSColor(hex: surface) ?? .controlBackgroundColor }
    var foregroundColor: NSColor { NSColor(hex: foreground) ?? .labelColor }
    var mutedColor: NSColor { NSColor(hex: muted) ?? .secondaryLabelColor }
    var accentColor: NSColor { NSColor(hex: accent) ?? .controlAccentColor }

    // MARK: - The set

    static let system = Palette(
        id: "system", name: "Match System", isDark: true, isNative: true,
        background: "1c1c1e", surface: "2c2c2e", foreground: "f2f2f7",
        muted: "98989f", accent: "0a84ff"
    )

    static let light = Palette(
        id: "light", name: "Light", isDark: false, isNative: true,
        background: "f5f5f7", surface: "ffffff", foreground: "1d1d1f",
        muted: "86868b", accent: "0071e3"
    )

    static let dark = Palette(
        id: "dark", name: "Dark", isDark: true, isNative: true,
        background: "1c1c1e", surface: "2c2c2e", foreground: "f2f2f7",
        muted: "98989f", accent: "0a84ff"
    )

    static let gruvbox = Palette(
        id: "gruvbox-dark", name: "Gruvbox Dark", isDark: true,
        background: "282828", surface: "3c3836", foreground: "ebdbb2",
        muted: "928374", accent: "fabd2f"
    )

    static let nord = Palette(
        id: "nord", name: "Nord", isDark: true,
        background: "2e3440", surface: "3b4252", foreground: "eceff4",
        muted: "7b88a1", accent: "88c0d0"
    )

    static let catppuccin = Palette(
        id: "catppuccin-mocha", name: "Catppuccin Mocha", isDark: true,
        background: "1e1e2e", surface: "313244", foreground: "cdd6f4",
        muted: "a6adc8", accent: "cba6f7"
    )

    static let tokyoNight = Palette(
        id: "tokyo-night", name: "Tokyo Night", isDark: true,
        background: "1a1b26", surface: "24283b", foreground: "c0caf5",
        muted: "565f89", accent: "7aa2f7"
    )

    static let dracula = Palette(
        id: "dracula", name: "Dracula", isDark: true,
        background: "282a36", surface: "44475a", foreground: "f8f8f2",
        muted: "6272a4", accent: "bd93f9"
    )

    static let oneDark = Palette(
        id: "one-dark", name: "One Dark", isDark: true,
        background: "282c34", surface: "333842", foreground: "abb2bf",
        muted: "5c6370", accent: "61afef"
    )

    static let solarized = Palette(
        id: "solarized-dark", name: "Solarized Dark", isDark: true,
        background: "002b36", surface: "073642", foreground: "93a1a1",
        muted: "657b83", accent: "b58900"
    )

    static let amoled = Palette(
        id: "amoled", name: "AMOLED Black", isDark: true,
        background: "000000", surface: "0d0d0d", foreground: "e8e8e8",
        muted: "7d7d7d", accent: "6ea8fe"
    )

    static let rosePine = Palette(
        id: "rose-pine", name: "Rose Pine", isDark: true,
        background: "191724", surface: "1f1d2e", foreground: "e0def4",
        muted: "6e6a86", accent: "ebbcba"
    )

    static let all: [Palette] = [
        system, light, dark, gruvbox, nord, catppuccin, tokyoNight, dracula,
        oneDark, solarized, amoled, rosePine
    ]

    static func palette(withID id: String) -> Palette {
        all.first { $0.id == id } ?? system
    }
}

final class ThemeManager: NSObject, NSMenuDelegate {
    static let shared = ThemeManager()

    private let themeKey = "zonic.theme"
    private let legacyKey = "zonic.appearance"
    private let skinKey = "zonic.skinPage"
    private let autoUpdateKey = "zonic.autoUpdateCheck"
    private let seekKey = "zonic.seekControls"
    private let finishKey = "zonic.finishTrackSkips"

    private(set) var palette: Palette = .system

    /// Recolour the page itself, best effort. On by default: a themed window with an
    /// untouched page looked half finished.
    var skinsPage: Bool {
        get {
            if UserDefaults.standard.object(forKey: skinKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: skinKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: skinKey)
            NotificationCenter.default.post(name: .themeDidChange, object: nil)
            NotificationCenter.default.post(name: .playerSettingsDidChange, object: nil)
        }
    }

    var autoCheckUpdates: Bool {
        get {
            if UserDefaults.standard.object(forKey: autoUpdateKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: autoUpdateKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoUpdateKey)
            NotificationCenter.default.post(name: .playerSettingsDidChange, object: nil)
        }
    }

    /// Reveals the scrubber and allows seeking inside a track.
    var seekControlsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: seekKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: seekKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: seekKey)
            NotificationCenter.default.post(name: .playerSettingsDidChange, object: nil)
        }
    }

    /// When Amazon refuses a skip, run the current track to its end instead, so playback
    /// rolls on by itself. Amazon counts button presses, not tracks finishing.
    var finishTrackSkips: Bool {
        get {
            if UserDefaults.standard.object(forKey: finishKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: finishKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: finishKey)
            NotificationCenter.default.post(name: .playerSettingsDidChange, object: nil)
        }
    }

    func loadAndApply() {
        let stored = UserDefaults.standard.string(forKey: themeKey)
            ?? UserDefaults.standard.string(forKey: legacyKey)
        palette = Palette.palette(withID: stored ?? Palette.system.id)
        applyAppearance()
    }

    func set(_ next: Palette) {
        palette = next
        UserDefaults.standard.set(next.id, forKey: themeKey)
        applyAppearance()
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
        NotificationCenter.default.post(name: .playerSettingsDidChange, object: nil)
    }

    /// Steps through every palette, so the chrome button is a quick sampler.
    func cycle() {
        let index = Palette.all.firstIndex { $0.id == palette.id } ?? 0
        set(Palette.all[(index + 1) % Palette.all.count])
    }

    private func applyAppearance() {
        if palette.isNative {
            switch palette.id {
            case "light": NSApp.appearance = NSAppearance(named: .aqua)
            case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
            default: NSApp.appearance = nil
            }
        } else {
            NSApp.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        }
    }

    @objc func select(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        set(Palette.palette(withID: id))
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            guard let id = item.representedObject as? String else { continue }
            item.state = id == palette.id ? .on : .off
        }
    }

    // MARK: - Page skin

    /// CSS applied to the Amazon Music page for every palette. Amazon ships hashed class
    /// names, so nothing here may depend on them: the skin works structurally instead,
    /// flattening the site's own fills and painting them again from the palette. Album art
    /// and images are untouched on purpose.
    ///
    /// This is the part most likely to need nudging when Amazon redesigns.
    func pageCSS() -> String {
        guard skinsPage else { return "" }

        let bg = palette.background
        let surface = palette.surface
        let fg = palette.foreground
        let muted = palette.muted
        let accent = palette.accent
        let scheme = palette.isDark ? "dark" : "light"

        return """
        :root { color-scheme: \(scheme) !important; }
        html { background-color: #\(bg) !important; }
        body { background-color: #\(bg) !important; color: #\(fg) !important; }

        /* Flatten every fill, then paint the ones that carry meaning back on. */
        body * {
          background-color: transparent !important;
          border-color: #\(surface) !important;
          outline-color: #\(accent) !important;
        }
        body * { color: inherit; }

        /* Text. Amazon sets explicit whites and blacks all over the place. */
        body, body p, body span, body div, body li, body label, body h1,
        body h2, body h3, body h4, body h5, body h6, body strong, body small,
        body time, body td, body th {
          color: #\(fg) !important;
        }
        body a, body a span { color: #\(fg) !important; }
        body a:hover, body a:hover span { color: #\(accent) !important; }
        [aria-current], [aria-current] span, [aria-selected="true"],
        [aria-selected="true"] span { color: #\(accent) !important; }
        [aria-disabled="true"], [aria-disabled="true"] span,
        [disabled], body small { color: #\(muted) !important; }
        ::selection { background: #\(accent) !important; color: #\(bg) !important; }

        /* Containers sit on the palette background; the player bar gets the surface tone. */
        #root, #nav, #main, #page-container, #main-container, main, header, nav,
        section, aside, article, footer, form, table, tbody, tr, td, th, ul, ol, li,
        div, span { background-color: transparent !important; }

        [data-testid*="player" i], [class*="playerBar" i], [class*="player-bar" i],
        [class*="nowPlaying" i], [class*="playback" i], [class*="miniplayer" i],
        [role="region"][aria-label*="player" i] {
          background-color: #\(surface) !important;
        }

        /* Interactive elements need to read as interactive once their fills are gone. */
        button, [role="button"], [role="menuitem"], [role="option"], [role="tab"] {
          background-color: transparent !important;
          border-radius: 6px !important;
        }
        button:hover, [role="button"]:hover, [role="menuitem"]:hover,
        [role="option"]:hover, [role="tab"]:hover {
          background-color: #\(surface) !important;
        }
        [aria-pressed="true"], [aria-checked="true"], [data-selected="true"] {
          background-color: #\(surface) !important;
          color: #\(accent) !important;
        }

        input, textarea, select, [contenteditable="true"], [role="textbox"],
        [role="searchbox"] {
          background-color: #\(surface) !important;
          color: #\(fg) !important;
          border: 1px solid #\(muted) !important;
          border-radius: 6px !important;
        }
        input::placeholder, textarea::placeholder { color: #\(muted) !important; }

        /* Sliders and progress bars are the clearest signal of the accent colour. */
        input[type="range"], [role="slider"] { accent-color: #\(accent) !important; }
        progress, [role="progressbar"], [role="progressbar"] > * {
          background-color: #\(surface) !important;
          color: #\(accent) !important;
          accent-color: #\(accent) !important;
        }

        /* Dialogs and menus float above the page and need an actual fill. */
        [role="dialog"], [role="menu"], [role="listbox"], [role="tooltip"],
        [role="alertdialog"], [class*="modal" i], [class*="dialog" i],
        [class*="popover" i], [class*="dropdown" i], [class*="menu" i][class*="list" i] {
          background-color: #\(surface) !important;
          color: #\(fg) !important;
          border: 1px solid #\(muted) !important;
          border-radius: 10px !important;
        }

        ::-webkit-scrollbar { width: 10px; height: 10px; }
        ::-webkit-scrollbar-track { background: #\(bg) !important; }
        ::-webkit-scrollbar-thumb {
          background: #\(muted) !important;
          border-radius: 5px !important;
        }
        ::-webkit-scrollbar-thumb:hover { background: #\(accent) !important; }
        """
    }
}

extension NSColor {
    /// Parses `rrggbb` / `#rrggbb` and the 8-digit forms that carry alpha.
    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16) else { return nil }

        let hasAlpha = value.count == 8
        let red = CGFloat((number >> (hasAlpha ? 24 : 16)) & 0xff) / 255
        let green = CGFloat((number >> (hasAlpha ? 16 : 8)) & 0xff) / 255
        let blue = CGFloat((number >> (hasAlpha ? 8 : 0)) & 0xff) / 255
        let alpha = hasAlpha ? CGFloat(number & 0xff) / 255 : 1
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

extension Notification.Name {
    static let themeDidChange = Notification.Name("zonic.themeDidChange")
    static let playerSettingsDidChange = Notification.Name("zonic.playerSettingsDidChange")
}
