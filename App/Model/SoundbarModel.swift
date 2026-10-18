import Foundation
import Observation
import SwiftUI
import WidgetKit

/// The app's live view of the soundbar. Keeps itself up to date while the app is open and sends
/// changes straight away (sliders are smoothed so the soundbar isn't flooded).
@MainActor
@Observable
final class SoundbarModel {
    static let shared = SoundbarModel()

    enum Connection: Equatable {
        case connecting
        case connected
        case unreachable
    }

    private(set) var soundbar: SoundbarInfo?
    private(set) var presets: [Preset] = []
    private(set) var volumeStep = 4
    var state = SoundbarState()
    private(set) var connection: Connection = .connecting

    // Finding the soundbar
    private(set) var isSearching = false
    private(set) var searchMessage: String?
    private(set) var found: [SoundbarInfo] = []
    private(set) var searchFinished = false

    /// A change that couldn't be sent, shown briefly at the bottom of the screen.
    var problem: String?

    private var pollTask: Task<Void, Never>?
    private var sendTasks: [String: Task<Void, Never>] = [:]
    /// Settings changed in the last moment, which a refresh shouldn't overwrite.
    private var heldUntil: [String: Date] = [:]
    private var lastSent: [String: Date] = [:]
    private var sendChain: Task<Void, Never>?
    private var failures = 0

    private init() {
        load()
    }

    var link: SoundbarLink? { soundbar.map { SoundbarLink(host: $0.host) } }

    func load() {
        let setup = Store.load()
        soundbar = setup.soundbar
        presets = setup.presets
        volumeStep = setup.volumeStep
        state = setup.state
    }

    // MARK: Staying up to date

    func appBecameActive() {
        load()
        startPolling()
    }

    func appWentToBackground() {
        pollTask?.cancel()
        pollTask = nil
        saveState()
    }

    func startPolling() {
        pollTask?.cancel()
        guard soundbar != nil, !Demo.isDemo else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                let delay: Double = (self?.connection == .unreachable) ? 6 : 2.5
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func refreshNow() async {
        guard let link, !Demo.isDemo else { return }
        do {
            let fresh = try await link.readState(previous: state)
            merge(fresh)
            failures = 0
            connection = .connected
        } catch {
            failures += 1
            // One missed answer is normal on Wi-Fi; only say it's unreachable after a few.
            if failures >= 2 || connection == .connecting { connection = .unreachable }
        }
    }

    /// Takes a fresh reading, keeping anything changed in the last moment as the user set it.
    private func merge(_ fresh: SoundbarState) {
        var merged = fresh
        let now = Date()
        func held(_ field: String) -> Bool { (heldUntil[field] ?? .distantPast) > now }
        if held("power") { merged.power = state.power }
        if held("volume") { merged.volume = state.volume }
        if held("muted") { merged.muted = state.muted }
        if held("input") { merged.input = state.input }
        if held("mode") { merged.mode = state.mode }
        if held("night") { merged.night = state.night }
        if held("dialogue") { merged.dialogue = state.dialogue }
        if held("display") { merged.display = state.display }
        if held("bass") { merged.bass = state.bass }
        if held("mid") { merged.mid = state.mid }
        if held("treble") { merged.treble = state.treble }
        for key in state.levels.keys where held("level-\(key)") { merged.levels[key] = state.levels[key] }
        if merged != state {
            let widgetsCare = merged.power != state.power || merged.volume != state.volume || merged.muted != state.muted
                || merged.mode != state.mode
            state = merged
            if widgetsCare { saveState() }
        }
    }

    private func saveState() {
        guard !Demo.isDemo else { return }
        let current = state
        Store.update { $0.state = current }
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }

    // MARK: Changes

    /// Shows the change at once, then sends it. `smooth` waits a moment for a slider to settle.
    func set(_ change: SoundbarChange, smooth: Bool = false) {
        change.apply(to: &state)
        let field = change.field
        heldUntil[field] = Date().addingTimeInterval(smooth ? 3 : 2.5)
        // Only a send that's still waiting is cancelled; one already on its way is left to finish.
        sendTasks[field]?.cancel()
        sendTasks[field] = nil
        guard let link, !Demo.isDemo else { return }
        // While a slider moves, send at most a few times a second, and always the final value.
        let recentlySent = Date().timeIntervalSince(lastSent[field] ?? .distantPast) < 0.25
        if smooth && recentlySent {
            sendTasks[field] = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(160))
                if Task.isCancelled { return }
                self?.lastSent[field] = Date()
                self?.send(change, via: link)
            }
        } else {
            lastSent[field] = Date()
            send(change, via: link)
        }
    }

    private func send(_ change: SoundbarChange, via link: SoundbarLink) {
        let field = change.field
        // Changes go out one after another so the soundbar always ends on the latest one.
        let previous = sendChain
        sendChain = Task { [weak self] in
            await previous?.value
            do {
                try await link.apply(change)
                self?.heldUntil[field] = Date().addingTimeInterval(1.5)
                if case .power = change { self?.saveState() }
                if case .mode = change { self?.saveState() }
            } catch {
                self?.problem = "Couldn't reach the soundbar."
                self?.heldUntil[field] = nil
            }
        }
    }

    func togglePower() { set(.power(!state.power)) }

    func nudgeVolume(_ delta: Int) { set(.volume(state.volume + delta)) }

    func applyPick(_ pick: Equaliser.Pick) {
        set(.bass(pick.bass))
        set(.mid(pick.mid))
        set(.treble(pick.treble))
    }

    func apply(_ preset: Preset) {
        for change in preset.changes { change.apply(to: &state) }
        for change in preset.changes { heldUntil[change.field] = Date().addingTimeInterval(4) }
        guard let link, !Demo.isDemo else { return }
        // One at a time, in order: the sound mode goes first.
        for change in preset.changes { send(change, via: link) }
    }

    // MARK: Presets

    func savePreset(_ preset: Preset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        storePresets()
    }

    func deletePreset(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        storePresets()
    }

    func movePresets(from source: IndexSet, to destination: Int) {
        presets.move(fromOffsets: source, toOffset: destination)
        storePresets()
    }

    private func storePresets() {
        let current = presets
        Store.update { $0.presets = current }
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }

    func setVolumeStep(_ step: Int) {
        volumeStep = step
        Store.update { $0.volumeStep = step }
    }

    /// Whether the soundbar's current settings match a preset.
    func matches(_ preset: Preset) -> Bool {
        if let mode = preset.mode, mode.rawValue != state.mode { return false }
        if let night = preset.night, night.rawValue != state.night { return false }
        if let dialogue = preset.dialogue, dialogue.rawValue != state.dialogue { return false }
        if let bass = preset.bass, bass != state.bass { return false }
        if let mid = preset.mid, mid != state.mid { return false }
        if let treble = preset.treble, treble != state.treble { return false }
        for (key, value) in preset.levels ?? [:] where state.levels[key] != nil && state.levels[key] != value { return false }
        if let volume = preset.volume, volume != state.volume { return false }
        return true
    }

    // MARK: Finding and choosing the soundbar

    func search() async {
        guard !isSearching else { return }
        isSearching = true
        searchFinished = false
        found = []
        searchMessage = "Looking for your soundbar…"
        let results = await Discovery.find { message in
            Task { @MainActor in SoundbarModel.shared.searchMessage = message }
        }
        found = results
        isSearching = false
        searchFinished = true
        searchMessage = results.isEmpty ? "No soundbar found." : nil
        // Only one soundbar and none chosen yet: use it.
        if soundbar == nil, results.count == 1, let only = results.first { await choose(only) }
    }

    /// Tries an address typed in by hand. Returns false if no soundbar answered there.
    func tryAddress(_ text: String) async -> Bool {
        let host = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, let info = await SoundbarLink(host: host).identify(timeout: 4) else { return false }
        await choose(info)
        return true
    }

    func choose(_ info: SoundbarInfo) async {
        soundbar = info
        connection = .connecting
        Store.update { $0.soundbar = info }
        await refreshNow()
        saveState()
        startPolling()
    }

    func forgetSoundbar() {
        pollTask?.cancel()
        soundbar = nil
        found = []
        searchFinished = false
        state = SoundbarState()
        Store.update {
            $0.soundbar = nil
            $0.state = SoundbarState()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Picks up a new name or firmware version after the soundbar changes.
    func refreshInfo() async {
        guard let link, let info = await link.identify(timeout: 4) else { return }
        soundbar = info
        Store.update { $0.soundbar = info }
    }

    // MARK: Screenshots

    func replace(with setup: SavedSetup, connection: Connection) {
        soundbar = setup.soundbar
        presets = setup.presets
        state = setup.state
        volumeStep = setup.volumeStep
        self.connection = connection
    }
}
