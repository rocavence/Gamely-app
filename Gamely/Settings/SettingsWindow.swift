import SwiftUI

/// Hosts `SettingsView` in a window with the traffic lights over the card.
@MainActor
final class SettingsWindow {
    let navigation = SettingsNavigation()
    private let window: NSWindow

    init(controller: AppController, showGuide: @escaping () -> Void) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                          styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = String(localized: "Settings")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: SettingsView(controller: controller, navigation: navigation, showGuide: showGuide))
        hosting.sizingOptions = []   // the window sets the size, not the view
        window.contentView = hosting
        // The card runs under the transparent title bar, so the whole frame is the card.
        window.setFrame(NSRect(x: 0, y: 0, width: 900, height: 600), display: false)
    }

    func show(_ page: SettingsPage, activate: Bool = true) {
        navigation.page = page
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        if activate { NSApp.activate() }
    }

    func close() { window.close() }

    /// The window's content as an image; for the self-test.
    func snapshot() -> NSBitmapImageRep? { window.contentView?.snapshot() }
}

extension NSView {
    func snapshot() -> NSBitmapImageRep? {
        layoutSubtreeIfNeeded()
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        return rep
    }
}
