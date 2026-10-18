import AppIntents
import SwiftUI

@main
struct SoundstageApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Demo.prepareIfRequested()
        SoundstageShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { Router.shared.handle($0) }
                .task { await Demo.runIfRequested() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: SoundbarModel.shared.appBecameActive()
            case .background: SoundbarModel.shared.appWentToBackground()
            default: break
            }
        }
    }
}

/// Which sheet is showing. Widgets and links can open one.
@MainActor
@Observable
final class Router {
    static let shared = Router()

    var sheet: Sheet?
    /// A section of the main screen to scroll to.
    var scrollTarget: String?

    enum Sheet: Identifiable, Hashable {
        case settings
        case newPreset
        case editPreset(UUID)
        case roomTune

        var id: String {
            switch self {
            case .roomTune: "room-tune"
            case .settings: "settings"
            case .newPreset: "new-preset"
            case .editPreset(let id): "preset-\(id)"
            }
        }
    }

    private init() {}

    /// soundstage://settings, soundstage://eq and so on.
    func handle(_ url: URL) {
        guard url.scheme == "soundstage" else { return }
        switch url.host() {
        case "settings": sheet = .settings
        case "tune": sheet = .roomTune
        case "eq", "speakers", "presets": sheet = nil; scrollTarget = url.host()
        default: sheet = nil
        }
    }
}
