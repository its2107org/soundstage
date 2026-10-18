import AppIntents
import Foundation

// These actions run inside the Soundstage app itself (in the background), which is where
// permission to reach the soundbar on the home Wi-Fi lives. That's why they're marked as
// live-activity actions.

struct TurnOnIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Turn On Soundbar"
    static let description = IntentDescription("Switches the soundbar on.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SoundbarControl.perform(.power(true))
        return .result(dialog: "Soundbar on.")
    }
}

struct TurnOffIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Turn Off Soundbar"
    static let description = IntentDescription("Puts the soundbar on standby.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SoundbarControl.perform(.power(false))
        return .result(dialog: "Soundbar off.")
    }
}

struct SetVolumeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Set Soundbar Volume"
    static let description = IntentDescription("Sets the soundbar's volume, from 0 to 100.")

    @Parameter(title: "Volume", default: 30, inclusiveRange: (0, 100))
    var volume: Int

    init() {}

    static var parameterSummary: some ParameterSummary { Summary("Set volume to \(\.$volume)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SoundbarControl.perform(.volume(volume))
        return .result(dialog: "Volume \(volume).")
    }
}

struct VolumeUpIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Turn Volume Up"
    static let description = IntentDescription("Turns the soundbar up a little.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = try await SoundbarControl.nudgeVolume(up: true)
        return .result(dialog: "Volume \(state.volume).")
    }
}

struct VolumeDownIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Turn Volume Down"
    static let description = IntentDescription("Turns the soundbar down a little.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = try await SoundbarControl.nudgeVolume(up: false)
        return .result(dialog: "Volume \(state.volume).")
    }
}

struct MuteIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mute Soundbar"
    static let description = IntentDescription("Mutes or unmutes the soundbar.")

    @Parameter(title: "Mute", default: true)
    var mute: Bool

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary("Set mute to \(\.$mute)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SoundbarControl.perform(.muted(mute))
        return .result(dialog: mute ? "Muted." : "Unmuted.")
    }
}

struct SetModeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Set Sound Mode"
    static let description = IntentDescription("Switches the soundbar to Movie, Music, Game or another sound mode.")

    @Parameter(title: "Mode")
    var mode: ModeChoice

    init() {}

    static var parameterSummary: some ParameterSummary { Summary("Switch to \(\.$mode)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SoundbarControl.perform(.mode(mode.mode))
        return .result(dialog: "\(mode.mode.title) mode.")
    }
}

struct SetInputIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Switch Soundbar Input"
    static let description = IntentDescription("Switches the soundbar to TV, HDMI, Optical, Aux or Bluetooth.")

    @Parameter(title: "Input")
    var input: InputChoice

    init() {}

    static var parameterSummary: some ParameterSummary { Summary("Switch to \(\.$input)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SoundbarControl.perform(.input(input.input))
        return .result(dialog: "\(input.input.title).")
    }
}

struct SetNightModeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Set Night Mode"
    static let description = IntentDescription("Evens out loud and quiet moments so you can listen at night.")

    @Parameter(title: "Night mode", default: .high)
    var level: NightChoice

    init() {}

    static var parameterSummary: some ParameterSummary { Summary("Set night mode to \(\.$level)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SoundbarControl.perform(.night(level.level))
        return .result(dialog: "Night mode \(level.level.title.lowercased()).")
    }
}

struct SetDialogueIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Set Dialogue Boost"
    static let description = IntentDescription("Makes voices clearer.")

    @Parameter(title: "Dialogue boost", default: .medium)
    var level: DialogueChoice

    init() {}

    static var parameterSummary: some ParameterSummary { Summary("Set dialogue boost to \(\.$level)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SoundbarControl.perform(.dialogue(level.level))
        return .result(dialog: "Dialogue boost \(level.level.title.lowercased()).")
    }
}

struct ApplyPresetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Use Preset"
    static let description = IntentDescription("Sets the soundbar to one of your saved presets.")

    @Parameter(title: "Preset")
    var preset: PresetEntity

    init() {}
    init(preset: PresetEntity) { self.preset = preset }

    static var parameterSummary: some ParameterSummary { Summary("Use \(\.$preset)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let saved = preset.preset else { return .result(dialog: "That preset no longer exists.") }
        try await SoundbarControl.apply(saved)
        return .result(dialog: "\(saved.name) on.")
    }
}

// MARK: - Control Centre

/// The on/off switch behind the Control Centre power control.
struct SetPowerIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Switch Soundbar"
    static let description = IntentDescription("Switches the soundbar on or off.")
    static let isDiscoverable = false

    @Parameter(title: "On")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        try? await SoundbarControl.perform(.power(value))
        return .result()
    }
}

/// The switch behind the Control Centre mute control.
struct SetMuteIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Mute"
    static let description = IntentDescription("Mutes or unmutes the soundbar.")
    static let isDiscoverable = false

    @Parameter(title: "Muted")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        try? await SoundbarControl.perform(.muted(value))
        return .result()
    }
}

struct PresetControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Preset"
    static let isDiscoverable = false

    @Parameter(title: "Preset")
    var preset: PresetEntity?

    init() {}
}

// MARK: - Widget buttons (quiet: no spoken reply, and no error pop-ups)

struct WidgetPowerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Power"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        try? await SoundbarControl.togglePower()
        return .result()
    }
}

struct WidgetMuteIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mute"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        try? await SoundbarControl.toggleMute()
        return .result()
    }
}

struct WidgetVolumeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Volume"
    static let isDiscoverable = false

    @Parameter(title: "Up")
    var up: Bool

    init() {}
    init(up: Bool) { self.up = up }

    func perform() async throws -> some IntentResult {
        try? await SoundbarControl.nudgeVolume(up: up)
        return .result()
    }
}

struct WidgetModeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Sound Mode"
    static let isDiscoverable = false

    @Parameter(title: "Mode")
    var mode: String

    init() {}
    init(mode: SoundMode) { self.mode = mode.rawValue }

    func perform() async throws -> some IntentResult {
        if let m = SoundMode(rawValue: mode) { try? await SoundbarControl.perform(.mode(m)) }
        return .result()
    }
}

struct WidgetPresetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Preset"
    static let isDiscoverable = false

    @Parameter(title: "Preset ID")
    var presetID: String

    init() {}
    init(presetID: String) { self.presetID = presetID }

    func perform() async throws -> some IntentResult {
        if let preset = Store.load().presets.first(where: { $0.id.uuidString == presetID }) {
            try? await SoundbarControl.apply(preset)
        }
        return .result()
    }
}

/// Used by the Control Centre preset button.
struct RunPresetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Run Preset"
    static let isDiscoverable = false

    @Parameter(title: "Preset")
    var preset: PresetEntity?

    init() {}
    init(preset: PresetEntity?) { self.preset = preset }

    func perform() async throws -> some IntentResult {
        if let saved = preset?.preset { try? await SoundbarControl.apply(saved) }
        return .result()
    }
}
