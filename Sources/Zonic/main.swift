import AppKit

let zonicDelegate = AppDelegate()
NSApplication.shared.delegate = zonicDelegate
NSApplication.shared.setActivationPolicy(.regular)
NSApplication.shared.run()
