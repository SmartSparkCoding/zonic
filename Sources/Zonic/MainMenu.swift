import AppKit

enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Zonic")
        appItem.submenu = appMenu
        main.addItem(appItem)

        add(appMenu, "About Zonic", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        appMenu.addItem(.separator())
        add(appMenu, "Hide Zonic", #selector(NSApplication.hide(_:)), "h")
        let hideOthers = add(appMenu, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        add(appMenu, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        appMenu.addItem(.separator())
        add(appMenu, "Quit Zonic", #selector(NSApplication.terminate(_:)), "q")

        // Edit menu, so the web view's text fields behave
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        main.addItem(editItem)

        add(editMenu, "Undo", Selector(("undo:")), "z")
        let redo = add(editMenu, "Redo", Selector(("redo:")), "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        add(editMenu, "Cut", #selector(NSText.cut(_:)), "x")
        add(editMenu, "Copy", #selector(NSText.copy(_:)), "c")
        add(editMenu, "Paste", #selector(NSText.paste(_:)), "v")
        add(editMenu, "Select All", #selector(NSText.selectAll(_:)), "a")

        // Playback menu
        let playbackItem = NSMenuItem()
        let playbackMenu = NSMenu(title: "Playback")
        playbackItem.submenu = playbackMenu
        main.addItem(playbackItem)

        let playPause = NSMenuItem(title: "Play / Pause", action: #selector(PlayerBridge.playPause(_:)), keyEquivalent: "p")
        playPause.target = PlayerBridge.shared
        playbackMenu.addItem(playPause)

        let next = NSMenuItem(title: "Next Track", action: #selector(PlayerBridge.nextTrack(_:)), keyEquivalent: "\u{F703}")
        next.keyEquivalentModifierMask = [.command]
        next.target = PlayerBridge.shared
        playbackMenu.addItem(next)

        let previous = NSMenuItem(title: "Previous Track", action: #selector(PlayerBridge.previousTrack(_:)), keyEquivalent: "\u{F702}")
        previous.keyEquivalentModifierMask = [.command]
        previous.target = PlayerBridge.shared
        playbackMenu.addItem(previous)

        // View menu
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        let reload = NSMenuItem(title: "Reload", action: #selector(PlayerBridge.reloadPage(_:)), keyEquivalent: "r")
        reload.target = PlayerBridge.shared
        viewMenu.addItem(reload)

        let back = NSMenuItem(title: "Back", action: #selector(PlayerBridge.goBack(_:)), keyEquivalent: "[")
        back.target = PlayerBridge.shared
        viewMenu.addItem(back)

        let forward = NSMenuItem(title: "Forward", action: #selector(PlayerBridge.goForward(_:)), keyEquivalent: "]")
        forward.target = PlayerBridge.shared
        viewMenu.addItem(forward)

        viewMenu.addItem(.separator())

        let zoomIn = NSMenuItem(title: "Zoom In", action: #selector(PlayerBridge.zoomIn(_:)), keyEquivalent: "=")
        zoomIn.target = PlayerBridge.shared
        viewMenu.addItem(zoomIn)

        let zoomOut = NSMenuItem(title: "Zoom Out", action: #selector(PlayerBridge.zoomOut(_:)), keyEquivalent: "-")
        zoomOut.target = PlayerBridge.shared
        viewMenu.addItem(zoomOut)

        let zoomReset = NSMenuItem(title: "Actual Size", action: #selector(PlayerBridge.zoomReset(_:)), keyEquivalent: "0")
        zoomReset.target = PlayerBridge.shared
        viewMenu.addItem(zoomReset)

        viewMenu.addItem(.separator())

        let appearance = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu()
        appearanceMenu.delegate = ThemeManager.shared
        for mode in AppearanceMode.allCases {
            let item = NSMenuItem(title: mode.label, action: #selector(ThemeManager.select(_:)), keyEquivalent: "")
            item.target = ThemeManager.shared
            item.representedObject = mode.rawValue
            item.state = mode == ThemeManager.shared.mode ? .on : .off
            appearanceMenu.addItem(item)
        }
        appearance.submenu = appearanceMenu
        viewMenu.addItem(appearance)

        viewMenu.addItem(.separator())

        let fullScreen = NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fullScreen)

        // Window menu
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        add(windowMenu, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(windowMenu, "Zoom", #selector(NSWindow.performZoom(_:)))
        NSApp.windowsMenu = windowMenu

        return main
    }

    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menu.addItem(item)
        return item
    }
}
