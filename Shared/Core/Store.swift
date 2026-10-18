import Foundation

/// What Soundstage remembers: which soundbar, how it last looked, and the saved presets.
/// Shared with the widgets through the keychain (see SharedVault).
struct SavedSetup: Codable, Equatable, Sendable {
    var soundbar: SoundbarInfo?
    var state = SoundbarState()
    var presets: [Preset] = Preset.defaults
    /// How much the volume buttons (widgets, Siri, Control Centre) change the volume by.
    var volumeStep = 4
}

enum Store {
    private static let service = "soundstage"
    private static let account = "setup"

    /// Used by the screenshot mode instead of the real saved set-up.
    nonisolated(unsafe) static var demo: SavedSetup?

    /// When the keychain isn't available (unsigned simulator builds), keep a file copy instead.
    private static var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("setup.json")
    }

    static func load() -> SavedSetup {
        if let demo { return demo }
        let decoder = JSONDecoder()
        if let data = SharedVault.read(service: service, account: account),
           let setup = try? decoder.decode(SavedSetup.self, from: data) {
            return setup
        }
        if let url = fileURL, let data = try? Data(contentsOf: url),
           let setup = try? decoder.decode(SavedSetup.self, from: data) {
            return setup
        }
        return SavedSetup()
    }

    static func save(_ setup: SavedSetup) {
        if demo != nil { demo = setup; return }
        guard let data = try? JSONEncoder().encode(setup) else { return }
        if !SharedVault.write(data, service: service, account: account), let url = fileURL {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func update(_ change: (inout SavedSetup) -> Void) {
        var setup = load()
        change(&setup)
        save(setup)
    }
}
