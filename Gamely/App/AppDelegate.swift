import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var menu: StatusMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests are hosted in the app; don't touch the real Dock or start
        // watching the log while they run.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }

        #if DEBUG
        if let item = ProcessInfo.processInfo.environment["GAMELY_SELFTEST"] {
            SelfTest.run(item)
            return
        }
        #endif

        let controller = AppController(hotCorners: .live)
        menu = StatusMenu(controller: controller)
        controller.onChange = { [weak self] in self?.menu?.update() }
        controller.start()
        self.controller = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}
