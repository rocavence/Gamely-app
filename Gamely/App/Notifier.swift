import UserNotifications

/// Optional banners when Hot Corners are paused or restored. Off by default;
/// turning it on asks macOS for permission.
enum Notifier {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
    }

    static func post(paused: Bool, reason: String?) {
        let content = UNMutableNotificationContent()
        content.title = paused
            ? String(localized: "Hot Corners paused")
            : String(localized: "Hot Corners restored")
        if paused, let reason { content.body = reason }
        let request = UNNotificationRequest(identifier: "gamely.state", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
