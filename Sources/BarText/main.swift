import AppKit

// Status-bar-only utility: no Dock icon, no app menu. The activation policy is
// set before the app runs so nothing flashes in the Dock on launch.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
