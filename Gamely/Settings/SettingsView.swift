import SwiftUI

enum SettingsPage: String, CaseIterable {
    case general, forcedApps, status, about

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .forcedApps: String(localized: "Forced Apps")
        case .status: String(localized: "Status")
        case .about: String(localized: "About")
        }
    }

    var icon: Reicon {
        switch self {
        case .general: .setting2
        case .forcedApps: .element
        case .status: .pulse
        case .about: .infoCircle
        }
    }
}

/// Which page Settings shows; the menu can open it on a given page.
@MainActor
@Observable
final class SettingsNavigation {
    var page: SettingsPage = .general
}

/// Flione's settings card: 900 × 600, 32 all round, a 184-wide column of
/// pages, a hairline, then the page 24 in from it.
struct SettingsView: View {
    let controller: AppController
    @Bindable var navigation: SettingsNavigation
    var showGuide: () -> Void
    @AppStorage(Accent.key) private var accent: Accent = .gamely

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings").textStyle(.title).foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, Spacing.s8)
                    .padding(.bottom, Spacing.s20)
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    ForEach(SettingsPage.allCases, id: \.self) { page in
                        SidebarRow(page: page, selected: page == navigation.page) { navigation.page = page }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 184, alignment: .leading)
            .padding(.trailing, Spacing.s16)

            Palette.hairline.frame(width: 1).padding(.vertical, -Spacing.s32)

            VStack(alignment: .leading, spacing: 0) {
                Text(navigation.page.title).textStyle(.heading).foregroundStyle(Palette.ink)
                    .frame(height: 36, alignment: .leading)
                    .padding(.bottom, Spacing.s4)
                ScrollView {
                    Group {
                        switch navigation.page {
                        case .general: GeneralPage(controller: controller, showGuide: showGuide)
                        case .forcedApps: ForcedAppsPage(controller: controller)
                        case .status: StatusPage(controller: controller)
                        case .about: AboutPage(updates: controller.updates)
                        }
                    }
                    .padding(.bottom, Spacing.s24)
                }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
                // Fade at the bottom hints there's more below without a scroller.
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 28)
                    }
                }
            }
            .padding(.leading, Spacing.s24)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        // The traffic lights sit in the top margin, so the columns start a little lower.
        .padding(.horizontal, Spacing.s32)
        .padding(.top, Spacing.s32 + Spacing.s8)
        .padding(.bottom, Spacing.s32)
        .frame(width: 900, height: 600)
        .background {
            ZStack {
                Palette.background
                RadialGradient(colors: [accent.color.opacity(0.08), .clear], center: .top, startRadius: 0, endRadius: 420)
            }
            .ignoresSafeArea()
        }
        .tint(accent.color)
    }
}

private struct SidebarRow: View {
    let page: SettingsPage
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s8) {
                IconView(page.icon, weight: selected ? .filled : .outline, size: 16).frame(width: 20)
                Text(page.title).textStyle(selected ? .bodyEmphasis : .body).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Palette.ink.opacity(0.82)))
            .padding(.horizontal, Spacing.s8)
            .frame(height: 32)
            .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(hovering ? Palette.hover : .clear),
                        in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - General

private struct GeneralPage: View {
    @Bindable var controller: AppController
    var showGuide: () -> Void
    @State private var language = AppLanguage.saved
    @AppStorage(AppAppearance.key) private var appearance: AppAppearance = .system
    @AppStorage(Accent.key) private var accent: Accent = .gamely

    var body: some View {
        VStack(spacing: 0) {
            SettingToggle(title: String(localized: "Pause Hot Corners in Game Mode"),
                          detail: String(localized: "When a full-screen game turns on Game Mode, the four corners do nothing until you leave it."),
                          isOn: $controller.enabled)
            SettingRow(title: String(localized: "Launch at Login"), detail: loginDetail) {
                HStack(spacing: Spacing.s8) {
                    if controller.loginItemNeedsApproval || controller.loginItemError != nil {
                        PillButton(String(localized: "Open Login Items")) { LoginItem.openSystemSettings() }
                    }
                    Toggle(isOn: Binding(get: { controller.loginItemEnabled }, set: { controller.setLoginItem($0) })) {
                        Text("Launch at Login")
                    }
                    .labelsHidden().toggleStyle(PillSwitchStyle())
                }
            }
            SettingToggle(title: String(localized: "Notifications"),
                          detail: String(localized: "Show a banner each time Hot Corners are paused or restored."),
                          isOn: Binding(get: { controller.notifies }, set: { on in
                              controller.notifies = on
                              if on { Task { if !(await Notifier.requestPermission()) { controller.notifies = false } } }
                          }))
            SettingRow(title: String(localized: "Language"),
                       detail: language == AppLanguage.launched ? nil : String(localized: "Takes effect when Gamely opens again.")) {
                HStack(spacing: Spacing.s8) {
                    if language != AppLanguage.launched {
                        PillButton(String(localized: "Reopen")) { AppLanguage.relaunch() }
                    }
                    PillMenu(title: String(localized: "Language"), selection: $language,
                             options: AppLanguage.allCases.map { ($0, $0.title) })
                }
            }
            .onChange(of: language) { AppLanguage.save(language) }
            SettingRow(title: String(localized: "Appearance"), detail: String(localized: "For Gamely's windows.")) {
                PillMenu(title: String(localized: "Appearance"), selection: $appearance,
                         options: AppAppearance.allCases.map { ($0, $0.title) })
            }
            .onChange(of: appearance) { AppAppearance.apply(appearance) }
            SettingRow(title: String(localized: "Accent Color"), detail: String(localized: "Marks what's chosen and what's on.")) {
                PillMenu(title: String(localized: "Accent Color"), selection: $accent,
                         options: Accent.allCases.map { ($0, $0.title) })
            }
            SettingRow(title: String(localized: "How Gamely Works"),
                       detail: String(localized: "What triggers a pause, and what to do with games that don't.")) {
                PillButton(String(localized: "Show Guide"), action: showGuide)
            }
        }
    }

    private var loginDetail: String {
        if let error = controller.loginItemError {
            return String(localized: "Couldn't turn this on: \(error) Open Login Items in System Settings and allow Gamely.")
        }
        if controller.loginItemNeedsApproval {
            return String(localized: "macOS is waiting for your OK: open Login Items in System Settings and allow Gamely.")
        }
        return String(localized: "Start Gamely when you log in, so it's there before your first game.")
    }
}

// MARK: - Forced apps

private struct ForcedAppsPage: View {
    @Bindable var controller: AppController

    var body: some View {
        VStack(spacing: 0) {
            Note(String(localized: "Some games never turn on Game Mode, such as Windows games running through CrossOver, Whisky or some Steam titles. Add them here: Hot Corners pause whenever one of them is in front."))
            ForEach(controller.whitelist, id: \.self) { id in
                SettingRow(title: AppInfo.name(for: id), detail: id, image: AppInfo.icon(for: id)) {
                    PillButton(String(localized: "Remove"), icon: .trash) {
                        controller.whitelist.removeAll { $0 == id }
                    }
                }
            }
            HStack {
                PillButton(String(localized: "Add App…"), icon: .plus, action: chooseApp)
                Spacer()
            }
            .padding(.top, Spacing.s16)
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add")
        panel.message = String(localized: "Choose the games or launchers that should pause Hot Corners.")
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            .filter { $0 != Bundle.main.bundleIdentifier && !controller.whitelist.contains($0) }
        controller.whitelist.append(contentsOf: ids)
    }
}

// MARK: - Status

private struct StatusPage: View {
    let controller: AppController

    var body: some View {
        VStack(spacing: 0) {
            SettingRow(title: String(localized: "Game Mode Detection"), detail: detectionDetail) {
                switch controller.detection {
                case .stopped:
                    PillButton(String(localized: "Retry"), icon: .refresh) { controller.retryDetection() }
                case .running:
                    IconView(.checkCircle, weight: .filled, size: 20).foregroundStyle(Palette.good)
                case .starting:
                    ProgressView().controlSize(.small)
                }
            }
            SettingRow(title: String(localized: "Right Now"), detail: controller.statusText) { EmptyView() }
            SettingRow(title: String(localized: "Last Paused"), detail: Self.format(controller.lastPausedAt)) { EmptyView() }
            SettingRow(title: String(localized: "Last Restored"), detail: Self.format(controller.lastRestoredAt)) { EmptyView() }
            VStack(alignment: .leading, spacing: Spacing.s12) {
                Text(controller.isPaused ? String(localized: "Your Hot Corners (restored when the game ends)") : String(localized: "Your Hot Corners"))
                    .textStyle(.subheading).foregroundStyle(Palette.ink)
                CornerDiagram(corners: controller.hotCorners.realCorners())
            }
            .padding(.vertical, Spacing.s16)
        }
    }

    private var detectionDetail: String {
        switch controller.detection {
        case .running: String(localized: "Watching for Game Mode.")
        case .starting: String(localized: "Starting…")
        case .stopped: String(localized: "Gamely can't read the system log right now, so Game Mode goes unnoticed. Retry; if it keeps stopping, quit and reopen Gamely. Forced apps still work.")
        }
    }

    private static func format(_ date: Date?) -> String {
        guard let date else { return String(localized: "Not yet") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - About

private struct AboutPage: View {
    let updates: UpdateChecker

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s24) {
            DeveloperCard().padding(.top, Spacing.s16)
            HStack(spacing: Spacing.s16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    Text(verbatim: "Gamely").textStyle(.subheading).foregroundStyle(Palette.ink)
                    Text("Hot Corners that stay out of your game.").textStyle(.body).foregroundStyle(Palette.muted)
                    Text("Version \(version)").textStyle(.caption).foregroundStyle(Palette.faint)
                    updateRow.padding(.top, Spacing.s2)
                }
            }
            section(String(localized: "Why Gamely"), [
                String(localized: "In a full-screen game, the pointer slips into a corner and Mission Control, the desktop or the screen saver takes over. It ruins the moment."),
                String(localized: "Gamely sits in the menu bar and turns Hot Corners off while macOS Game Mode is on, then puts your own settings back exactly as they were when it ends."),
            ])
            VStack(alignment: .leading, spacing: Spacing.s12) {
                heading(String(localized: "Thanks"))
                credit("Reicon", url: "https://github.com/dqev/reicon", detail: String(localized: "The menu bar and Settings icons."))
                credit("XcodeGen", url: "https://github.com/yonaskolb/XcodeGen", detail: String(localized: "Generates the Xcode project."))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var updateRow: some View {
        HStack(spacing: Spacing.s8) {
            switch updates.state {
            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking for updates…").textStyle(.caption).foregroundStyle(Palette.muted)
            case .available(let release):
                Text("Gamely \(release.version) is available").textStyle(.caption).foregroundStyle(Palette.ink)
                Button(String(localized: "Download")) { NSWorkspace.shared.open(release.page) }
                    .buttonStyle(.plain).foregroundStyle(.accentText).textStyle(.caption)
            case .upToDate:
                Text("Gamely is up to date.").textStyle(.caption).foregroundStyle(Palette.muted)
                checkButton
            case .failed:
                Text("Couldn't check for updates.").textStyle(.caption).foregroundStyle(Palette.muted)
                checkButton
            case .idle:
                checkButton
            }
        }
    }

    private var checkButton: some View {
        Button(String(localized: "Check for Updates")) { Task { await updates.check(manual: true) } }
            .buttonStyle(.plain).foregroundStyle(.accentText)
            .textStyle(.caption)
    }

    private func heading(_ title: String) -> some View {
        Text(title).textStyle(.micro).textCase(.uppercase).foregroundStyle(Palette.muted)
    }

    private func section(_ title: String, _ paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            heading(title)
            ForEach(paragraphs, id: \.self) { paragraph in
                Text(paragraph).textStyle(.body).foregroundStyle(Palette.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
        }
    }

    private func credit(_ name: String, url: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Link(destination: URL(string: url)!) {
                HStack(spacing: Spacing.s4) {
                    Text(verbatim: name).textStyle(.bodyEmphasis)
                    IconView(.arrowUpRight, size: 11)
                }
                .foregroundStyle(.accentText)
            }
            .buttonStyle(.plain)
            Text(detail).textStyle(.body).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The author card shared with Flione, Wunder and Findly; opens the GitHub
/// profile. The avatar ships in the app, nothing loads from the network.
private struct DeveloperCard: View {
    @State private var hovering = false

    var body: some View {
        Link(destination: URL(string: "https://github.com/rocavence")!) {
            HStack(spacing: Spacing.s12) {
                Image("DeveloperAvatar").resizable().frame(width: 42, height: 42).clipShape(Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text(verbatim: "@rocavence").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text("Author · GitHub").font(.system(size: 12.5)).foregroundStyle(Palette.muted)
                }
            }
            .padding(.leading, Spacing.s8)
            .padding(.trailing, Spacing.s16)
            .padding(.vertical, Spacing.s8)
            .overlay(Capsule().strokeBorder(Palette.hairline))
            .background { if hovering { Capsule().fill(Palette.background).shadow(color: .black.opacity(0.2), radius: 12, y: 6) } }
            .offset(y: hovering ? -2 : 0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: hovering)
        .accessibilityLabel("rocavence on GitHub")
    }
}
