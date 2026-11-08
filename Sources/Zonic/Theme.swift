import AppKit

enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var next: AppearanceMode {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

final class ThemeManager: NSObject, NSMenuDelegate {
    static let shared = ThemeManager()

    private let defaultsKey = "zonic.appearance"
    private(set) var mode: AppearanceMode = .system

    func loadAndApply() {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey),
           let stored = AppearanceMode(rawValue: raw) {
            mode = stored
        }
        NSApp.appearance = mode.nsAppearance
    }

    func cycle() { set(mode.next) }

    func set(_ mode: AppearanceMode) {
        self.mode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: defaultsKey)
        NSApp.appearance = mode.nsAppearance
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
    }

    @objc func select(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let picked = AppearanceMode(rawValue: raw) else { return }
        set(picked)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            guard let raw = item.representedObject as? String,
                  let itemMode = AppearanceMode(rawValue: raw) else { continue }
            item.state = itemMode == mode ? .on : .off
        }
    }
}

extension Notification.Name {
    static let themeDidChange = Notification.Name("zonic.themeDidChange")
}
