import AppKit

/// A fallback for when the log holds no Game Mode transition: is the frontmost
/// app a game (by its App Store category, as Game Mode itself decides) showing
/// a window the size of a screen?
enum FrontmostGame {
    @MainActor
    static func isFullScreenGame() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let url = app.bundleURL,
              let category = Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String,
              isGameCategory(category) else { return false }
        let screens = Set(NSScreen.screens.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" })
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let raw = window[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: raw as! CFDictionary) else { return false }
            return screens.contains("\(Int(bounds.width))x\(Int(bounds.height))")
        }
    }

    /// public.app-category.games and its sub-genres (action-games, puzzle-games…).
    static func isGameCategory(_ category: String) -> Bool {
        category.hasPrefix("public.app-category.") && category.hasSuffix("games")
    }
}
