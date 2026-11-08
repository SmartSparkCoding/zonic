import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: MainWindowController?
    private var settingsWindow: SettingsWindowController?
    private var spaceMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        ThemeManager.shared.loadAndApply()

        let window = MainWindowController()
        window.showWindow(nil)
        mainWindow = window

        installSpaceMonitor()
        NSApp.activate(ignoringOtherApps: true)

        // Quiet check a few seconds after launch, so a fresh version is offered without
        // getting in the way of the first play.
        if ThemeManager.shared.autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                Updater.shared.checkForUpdates(userInitiated: false)
            }
        }
    }

    func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }
        settingsWindow?.present()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Closing the window quits, and the update swap kills the process outright, so grab
    /// the login cookies while there is still a run loop to do it in.
    func applicationWillTerminate(_ notification: Notification) {
        SessionVault.shared.capture()
    }

    func applicationDidResignActive(_ notification: Notification) {
        SessionVault.shared.capture()
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
