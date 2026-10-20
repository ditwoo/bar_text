import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var editor: EditorWindowController?
    private var title = "Hello"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "bar-text"
        item.button?.title = title
        item.button?.toolTip = "bar-text"

        let menu = NSMenu()
        let editItem = NSMenuItem(
            title: "Edit text",
            action: #selector(editText),
            keyEquivalent: ""
        )
        editItem.target = self
        menu.addItem(editItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func editText() {
        let controller = editor ?? EditorWindowController()
        editor = controller

        controller.present(initialText: title) { [weak self] newTitle in
            guard let self = self else { return }
            self.title = newTitle
            self.statusItem?.button?.title = newTitle
        }
    }
}
