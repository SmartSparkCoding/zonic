import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: MainWindowController?
    private var spaceMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        ThemeManager.shared.loadAndApply()

        let window = MainWindowController()
        window.showWindow(nil)
        mainWindow = window

        installSpaceMonitor()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindow?.showWindow(nil) }
        return true
    }

    /// Space toggles playback unless a text field on the page has focus.
    private func installSpaceMonitor() {
        spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard event.keyCode == 49, modifiers.isEmpty else { return event }
            guard let web = PlayerBridge.shared.web, web.state.hasTrack, !web.state.isEditing else { return event }

            PlayerBridge.shared.handleRemote(web.state.isPlaying ? "pause" : "play")
            return nil
        }
    }
}
