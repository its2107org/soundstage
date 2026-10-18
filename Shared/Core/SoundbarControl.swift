import Foundation
import WidgetKit

/// Soundbar actions used by Siri, Shortcuts, widgets and Control Centre.
/// They run inside the app (see the intents), where permission to reach the home Wi-Fi lives.
enum SoundbarControl {
    enum ControlError: Error, LocalizedError {
        case noSoundbar
        case unreachable

        var errorDescription: String? {
            switch self {
            case .noSoundbar: "Open Soundstage once to find your soundbar."
            case .unreachable: "Couldn't reach the soundbar. Check it's plugged in and on the same Wi-Fi."
            }
        }
    }

    static func currentLink() throws -> SoundbarLink {
        guard let soundbar = Store.load().soundbar else { throw ControlError.noSoundbar }
        return SoundbarLink(host: soundbar.host)
    }

    /// Reads the soundbar and remembers what it said.
    @discardableResult
    static func refresh() async throws -> SoundbarState {
        let link = try currentLink()
        let previous = Store.load().state
        guard let state = try? await link.readState(previous: previous) else { throw ControlError.unreachable }
        Store.update { $0.state = state }
        reloadWidgets()
        return state
    }

    /// Makes one or more changes, switching the soundbar on first if needed.
    @discardableResult
    static func perform(_ changes: [SoundbarChange], wakeIfNeeded: Bool = true) async throws -> SoundbarState {
        let link = try currentLink()
        var state = Store.load().state
        if wakeIfNeeded, !changes.contains(where: { $0.field == "power" }) {
            if let on = try? await link.power(), !on {
                try? await link.apply(.power(true))
                state.power = true
                // The soundbar needs a moment to wake before it takes other settings.
                try? await Task.sleep(for: .seconds(2))
            }
        }
        do {
            for change in changes {
                try await link.apply(change)
                change.apply(to: &state)
            }
        } catch {
            throw ControlError.unreachable
        }
        state.updated = .now
        Store.update { $0.state = state }
        reloadWidgets()
        return state
    }

    @discardableResult
    static func perform(_ change: SoundbarChange) async throws -> SoundbarState {
        try await perform([change], wakeIfNeeded: change.wakes)
    }

    /// Volume up or down by the saved step. Reads the current volume first so it never jumps.
    @discardableResult
    static func nudgeVolume(up: Bool, by step: Int? = nil) async throws -> SoundbarState {
        let link = try currentLink()
        let amount = step ?? Store.load().volumeStep
        guard let current = try? await link.int(SoundbarLink.Path.volume) else { throw ControlError.unreachable }
        return try await perform([.volume(current + (up ? amount : -amount))], wakeIfNeeded: false)
    }

    @discardableResult
    static func togglePower() async throws -> SoundbarState {
        let link = try currentLink()
        guard let on = try? await link.power() else { throw ControlError.unreachable }
        return try await perform([.power(!on)], wakeIfNeeded: false)
    }

    @discardableResult
    static func toggleMute() async throws -> SoundbarState {
        let link = try currentLink()
        guard let muted = try? await link.bool(SoundbarLink.Path.mute) else { throw ControlError.unreachable }
        return try await perform([.muted(!muted)], wakeIfNeeded: false)
    }

    @discardableResult
    static func apply(_ preset: Preset) async throws -> SoundbarState {
        try await perform(preset.changes)
    }

    static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }
}

extension SoundbarChange {
    /// Whether making this change should switch the soundbar on first. Volume and mute don't,
    /// so a volume button never surprises anyone by waking it.
    var wakes: Bool {
        switch self {
        case .power, .volume, .muted, .display: false
        default: true
        }
    }
}
