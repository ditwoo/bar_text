import AppKit
import SwiftUI

/// Owns the single editor window. The window is created once and reused so
/// reopening it pre-fills the current title rather than stacking windows.
final class EditorWindowController {
    private let window: NSWindow
    private let hosting: NSHostingController<EditorView>

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 56),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit text"
        // Keep the window alive after the user closes it (closable, not released).
        window.isReleasedWhenClosed = false

        let hosting = NSHostingController(rootView: EditorView(text: "") { _ in })
        window.contentViewController = hosting

        // Floating is only needed while the editor is open; drop back to the
        // normal level once it closes so it does not linger above other apps.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            window?.level = .normal
        }

        self.window = window
        self.hosting = hosting
    }

    /// Show the window pre-filled with `initialText`. `onSave` receives the
    /// sanitized text when the user commits.
    func present(initialText: String, onSave: @escaping (String) -> Void) {
        hosting.rootView = EditorView(text: initialText) { [weak self] text in
            onSave(TitleFormatting.sanitize(text))
            self?.window.close()
        }

        // Float above other apps' windows, then bring it to the front even if
        // this (accessory) app is not currently active.
        window.level = .floating
        centerOnActiveScreen()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Center the window on the screen under the mouse (the one whose menu bar
    /// was just clicked), falling back to the main screen. `visibleFrame` keeps
    /// it clear of the menu bar and Dock.
    private func centerOnActiveScreen() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let area = screen?.visibleFrame else {
            window.center()
            return
        }

        window.setFrameOrigin(NSPoint(
            x: area.midX - window.frame.width / 2,
            y: area.midY - window.frame.height / 2
        ))
    }
}
