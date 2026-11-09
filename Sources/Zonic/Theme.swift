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
    private let skinKey = "zonic.skinMode"
    private let legacySkinKey = "zonic.skinPage"
    private let autoUpdateKey = "zonic.autoUpdateCheck"
    private let seekKey = "zonic.seekControls"
    private let finishKey = "zonic.finishTrackSkips"

    private(set) var palette: Palette = .system

    /// How the Amazon Music page itself gets recoloured.
    enum SkinMode: String, CaseIterable {
        case off, tint, invert

        var label: String {
            switch self {
            case .off: return "Leave the page alone"
            case .tint: return "Tint the page"
            case .invert: return "Invert the page"
            }
        }
    }

    /// What to do with the page. Defaults to inverting for custom palettes, since that is
    /// the only technique that does not depend on Amazon's obfuscated class names.
    var skinMode: SkinMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: skinKey),
               let mode = SkinMode(rawValue: raw) {
                return mode
            }
            if let legacy = UserDefaults.standard.object(forKey: legacySkinKey) as? Bool {
                return legacy ? (palette.isNative ? .off : .invert) : .off
            }
            return palette.isNative ? .off : .invert
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: skinKey)
            NotificationCenter.default.post(name: .themeDidChange, object: nil)
            NotificationCenter.default.post(name: .playerSettingsDidChange, object: nil)
        }
    }

    /// Kept for callers that only care whether the page is being touched at all.
    var skinsPage: Bool { skinMode != .off }

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
        switch skinMode {
        case .off: return ""
        case .tint: return tintCSS()
        case .invert: return palette.isDark ? invertCSS() : tintCSS()
        }
    }

    /// Optical skin: invert the whole page and flip the artwork back. This cannot miss,
    /// because it does not care what Amazon calls its elements.
    private func invertCSS() -> String {
        let bg = palette.background
        let accent = palette.accent
        return """
        :root, html { color-scheme: dark !important; }
        html {
          background-color: #ffffff !important;
          filter: invert(0.93) hue-rotate(180deg) saturate(0.92) !important;
        }
        img, picture, video, canvas, svg, [style*="background-image" i] {
          filter: invert(1) hue-rotate(180deg) !important;
        }
        html::after {
          content: "";
          position: fixed;
          inset: 0;
          pointer-events: none;
          z-index: 2147483646;
          background-color: #__ACCENT__;
          opacity: 0.14;
          mix-blend-mode: color;
        }
        ::-webkit-scrollbar { width: 10px; height: 10px; }
        ::-webkit-scrollbar-track { background: #__BG__ !important; }
        ::-webkit-scrollbar-thumb { background: #__ACCENT__ !important; border-radius: 5px; }
        """
        .replacingOccurrences(of: "__BG__", with: bg)
        .replacingOccurrences(of: "__ACCENT__", with: accent)
    }

    /// Structural skin: repaint the page from the palette. Selectors are attribute and
    /// ARIA based, and repeat [class] to out-specify Amazon's generated class names,
    /// which is why the earlier universal rules never took effect.
    private func tintCSS() -> String {
        let bg = palette.background
        let surface = palette.surface
        let fg = palette.foreground
        let muted = palette.muted
        let accent = palette.accent
        let scheme = palette.isDark ? "dark" : "light"

        return """
        :root { color-scheme: __SCHEME__ !important; }
        html, body { background-color: #__BG__ !important; color: #__FG__ !important; }

        html body [class][class][class]:not(img):not(video):not(canvas):not(svg):not(picture):not(path),
        html body [id][id]:not(img):not(video):not(canvas):not(svg):not(picture):not(path),
        html body div:not([class]):not([id]),
        html body span:not([class]):not([id]),
        html body section:not([class]),
        html body ul:not([class]),
        html body li:not([class]) {
          background-color: transparent !important;
          border-color: #__SURFACE__ !important;
        }

        html body [class][class][class] { color: #__FG__ !important; }
        html body h1, html body h2, html body h3, html body h4,
        html body p, html body li, html body label, html body time,
        html body strong, html body td, html body th { color: #__FG__ !important; }
        html body a, html body a * { color: #__FG__ !important; }
        html body a:hover, html body a:hover * { color: #__ACCENT__ !important; }
        html body [aria-current], html body [aria-current] *,
        html body [aria-selected="true"], html body [aria-selected="true"] * {
          color: #__ACCENT__ !important;
        }
        html body [aria-disabled="true"] *, html body [disabled] { color: #__MUTED__ !important; }
        html body small, html body [class][class][class] small { color: #__MUTED__ !important; }
        ::selection { background: #__ACCENT__ !important; color: #__BG__ !important; }

        [data-testid*="player" i], [class*="playerBar" i], [class*="player-bar" i],
        [class*="nowPlaying" i], [class*="playback" i], [class*="miniplayer" i],
        [role="region"][aria-label*="player" i] {
          background-color: #__SURFACE__ !important;
        }

        button, [role="button"], [role="menuitem"], [role="option"], [role="tab"] {
          background-color: transparent !important;
          color: #__FG__ !important;
          border-radius: 6px !important;
        }
        button:hover, [role="button"]:hover, [role="menuitem"]:hover,
        [role="option"]:hover, [role="tab"]:hover {
          background-color: #__SURFACE__ !important;
        }
        [aria-pressed="true"], [aria-checked="true"], [data-selected="true"] {
          background-color: #__SURFACE__ !important;
        }

        input, textarea, select, [contenteditable="true"], [role="textbox"],
        [role="searchbox"] {
          background-color: #__SURFACE__ !important;
          color: #__FG__ !important;
          border: 1px solid #__MUTED__ !important;
          border-radius: 6px !important;
        }
        input::placeholder, textarea::placeholder { color: #__MUTED__ !important; }

        input[type="range"], [role="slider"] {
          accent-color: #__ACCENT__ !important;
          background-color: #__MUTED__ !important;
        }
        progress, [role="progressbar"], [role="progressbar"] > * {
          background-color: #__SURFACE__ !important;
          color: #__ACCENT__ !important;
          accent-color: #__ACCENT__ !important;
        }

        [role="dialog"], [role="menu"], [role="listbox"], [role="tooltip"],
        [role="alertdialog"], [class*="modal" i], [class*="dialog" i],
        [class*="popover" i], [class*="dropdown" i] {
          background-color: #__SURFACE__ !important;
          color: #__FG__ !important;
          border: 1px solid #__MUTED__ !important;
          border-radius: 10px !important;
        }

        ::-webkit-scrollbar { width: 10px; height: 10px; }
        ::-webkit-scrollbar-track { background: #__BG__ !important; }
        ::-webkit-scrollbar-thumb { background: #__MUTED__ !important; border-radius: 5px; }
        ::-webkit-scrollbar-thumb:hover { background: #__ACCENT__ !important; }
        """
        .replacingOccurrences(of: "__SCHEME__", with: scheme)
        .replacingOccurrences(of: "__SURFACE__", with: surface)
        .replacingOccurrences(of: "__MUTED__", with: muted)
        .replacingOccurrences(of: "__ACCENT__", with: accent)
        .replacingOccurrences(of: "__FG__", with: fg)
        .replacingOccurrences(of: "__BG__", with: bg)
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
