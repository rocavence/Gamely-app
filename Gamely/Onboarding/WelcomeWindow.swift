import SwiftUI

/// The first-run guide: when Gamely pauses Hot Corners, what to do with games
/// that never turn on Game Mode, and the corners it will be looking after.
struct WelcomeView: View {
    let corners: [String: Int]
    var openForcedApps: () -> Void
    var done: () -> Void
    @AppStorage(Accent.key) private var accent: Accent = .orange

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s20) {
            HStack(spacing: Spacing.s12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text("Welcome to Gamely").textStyle(.heading).foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("It lives in the menu bar, under the gamepad icon.").textStyle(.body).foregroundStyle(Palette.muted)
                }
            }
            step(1, String(localized: "Hot Corners pause by themselves"),
                 String(localized: "When you play a game full screen and macOS turns on Game Mode, the four corners stop doing anything. When you leave the game, your own settings come back."))
            step(2, String(localized: "Some games need adding"),
                 String(localized: "Games running through CrossOver, Whisky or some Steam titles never turn on Game Mode. Add them under Forced Apps and Gamely pauses whenever one is in front."))
            VStack(alignment: .leading, spacing: Spacing.s8) {
                Text("The Hot Corners Gamely looks after").textStyle(.subheading).foregroundStyle(Palette.ink)
                CornerDiagram(corners: corners)
            }
            HStack {
                PillButton(String(localized: "Add Forced Apps…"), icon: .plus, action: openForcedApps)
                Spacer()
                Button(action: done) {
                    Text("Got It").textStyle(.bodyEmphasis).foregroundStyle(.white)
                        .padding(.horizontal, Spacing.s20).frame(height: 32)
                        .background(.tint, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.s32)
        .frame(width: 560)
        .background(Palette.background.ignoresSafeArea())
        .tint(accent.color)
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s12) {
            Text(verbatim: "\(number)").textStyle(.bodyEmphasis).foregroundStyle(.tint)
                .frame(width: 24, height: 24)
                .background(.tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text(title).textStyle(.subheading).foregroundStyle(Palette.ink)
                Text(detail).textStyle(.body).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

@MainActor
final class WelcomeWindow {
    private var window: NSWindow?

    func show(corners: [String: Int], openForcedApps: @escaping () -> Void, activate: Bool = true) {
        window?.close()
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = String(localized: "Welcome to Gamely")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WelcomeView(corners: corners, openForcedApps: { [weak self] in
            self?.close()
            openForcedApps()
        }, done: { [weak self] in self?.close() }))
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        if activate { NSApp.activate() }
        self.window = window
    }

    func close() {
        window?.close()
        Defaults.onboarded = true
    }

    func snapshot() -> NSBitmapImageRep? { window?.contentView?.snapshot() }
}
