import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var menu: StatusMenu?
    private var settings: SettingsWindow?
    private let welcome = WelcomeWindow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests are hosted in the app; don't touch the real Dock or start
        // watching the log while they run.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        AppAppearance.apply(.saved)

        #if DEBUG
        if let item = ProcessInfo.processInfo.environment["GAMELY_SELFTEST"] {
            SelfTest.run(item)
            return
        }
        #endif

        let controller = AppController(hotCorners: .live)
        let menu = StatusMenu(controller: controller)
        let settings = SettingsWindow(controller: controller) { [weak self] in self?.showGuide() }
        menu.openSettings = { settings.show($0) }
        controller.onChange = { menu.update() }
        controller.onToggle = { menu.flash(paused: $0) }
        controller.start()
        self.controller = controller
        self.menu = menu
        self.settings = settings
        if !Defaults.onboarded { showGuide() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    private func showGuide() {
        guard let controller else { return }
        welcome.show(corners: controller.hotCorners.realCorners()) { [weak self] in
            self?.settings?.show(.forcedApps)
        }
    }
}
