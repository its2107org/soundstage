import AppIntents
import SwiftUI
import WidgetKit

@main
struct SoundstageWidgets: WidgetBundle {
    var body: some Widget {
        SoundbarWidget()
        PresetsWidget()
        PowerControl()
        MuteControl()
        VolumeUpControl()
        VolumeDownControl()
        PresetControl()
    }
}

// MARK: - Shared bits

extension SoundMode {
    var widgetColour: Color {
        switch self {
        case .movie: Color(red: 1.0, green: 0.6, blue: 0.24)
        case .music: Color(red: 0.62, green: 0.42, blue: 1.0)
        case .game: Color(red: 0.24, green: 0.8, blue: 0.48)
        case .standard: Color(red: 0.32, green: 0.58, blue: 1.0)
        case .direct: Color(red: 0.16, green: 0.76, blue: 0.78)
        case .party: Color(red: 1.0, green: 0.34, blue: 0.58)
        }
    }
}

struct SetupEntry: TimelineEntry {
    let date: Date
    let setup: SavedSetup
}

struct SetupProvider: TimelineProvider {
    func placeholder(in context: Context) -> SetupEntry { SetupEntry(date: .now, setup: WidgetSample.setup) }

    func getSnapshot(in context: Context, completion: @escaping (SetupEntry) -> Void) {
        let setup = Store.load()
        completion(SetupEntry(date: .now, setup: setup.soundbar == nil && context.isPreview ? WidgetSample.setup : setup))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SetupEntry>) -> Void) {
        let entry = SetupEntry(date: .now, setup: Store.load())
        // The app and the buttons refresh this whenever something changes.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

enum WidgetSample {
    static let setup: SavedSetup = {
        var setup = SavedSetup()
        setup.soundbar = SoundbarInfo(host: "", name: "Living Room", model: "Klipsch Cinema 1200")
        setup.state.power = true
        setup.state.volume = 32
        setup.state.mode = SoundMode.movie.rawValue
        return setup
    }()
}

private struct NoSoundbarView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "hifispeaker.2")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open Soundstage to find your soundbar")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WidgetCircleButton: View {
    var symbol: String
    var filled = false
    var tint: Color = .accentColor
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .bold))
            .frame(width: size, height: size)
            .foregroundStyle(filled ? Color.white : Color.primary)
            .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(Color.primary.opacity(0.1)), in: Circle())
    }
}

// MARK: - Soundbar widget

struct SoundbarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SoundstageSoundbar", provider: SetupProvider()) { entry in
            SoundbarWidgetView(setup: entry.setup)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Soundbar")
        .description("Power, volume and sound mode.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct SoundbarWidgetView: View {
    let setup: SavedSetup
    @Environment(\.widgetFamily) private var family

    private var state: SoundbarState { setup.state }
    private var tint: Color { state.soundMode?.widgetColour ?? .orange }
    private var name: String { setup.soundbar?.displayName ?? "Soundbar" }

    var body: some View {
        if setup.soundbar == nil {
            switch family {
            case .accessoryCircular, .accessoryRectangular, .accessoryInline:
                Image(systemName: "hifispeaker.2")
            default:
                NoSoundbarView()
            }
        } else {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            case .systemMedium: medium
            default: small
            }
        }
    }

    private var statusLine: String {
        guard state.power else { return "Standby" }
        return state.muted ? "\(state.modeTitle) · Muted" : "\(state.modeTitle) · \(state.volume)"
    }

    private var circular: some View {
        Button(intent: WidgetPowerIntent()) {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "power")
                    .font(.title2.weight(.bold))
                    .opacity(state.power ? 1 : 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.power ? "Turn soundbar off" : "Turn soundbar on")
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            Button(intent: WidgetPowerIntent()) {
                Image(systemName: state.power ? "hifispeaker.fill" : "hifispeaker")
                    .font(.title2.weight(.semibold))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.headline).lineLimit(1)
                Text(statusLine).font(.caption).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var inline: some View {
        Label("\(name) · \(statusLine)", systemImage: state.power ? "hifispeaker.fill" : "hifispeaker")
    }

    private var volumeRow: some View {
        HStack(spacing: 8) {
            Button(intent: WidgetVolumeIntent(up: false)) { WidgetCircleButton(symbol: "minus") }
                .buttonStyle(.plain)
                .accessibilityLabel("Quieter")
            Text(state.muted ? "–" : "\(state.volume)")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(state.volume)))
                .frame(minWidth: 44)
            Button(intent: WidgetVolumeIntent(up: true)) { WidgetCircleButton(symbol: "plus") }
                .buttonStyle(.plain)
                .accessibilityLabel("Louder")
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.headline).lineLimit(1)
                    Text(state.power ? state.modeTitle : "Standby")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(state.power ? tint : .secondary)
                }
                Spacer(minLength: 4)
                Button(intent: WidgetPowerIntent()) { WidgetCircleButton(symbol: "power", filled: state.power, tint: tint, size: 34) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(state.power ? "Turn off" : "Turn on")
            }
            Spacer()
            if state.power {
                volumeRow
                    .frame(maxWidth: .infinity)
            } else {
                Text("Tap the power button to turn it on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            small
                .frame(maxWidth: .infinity)
            if state.power {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        modeButton(.movie)
                        modeButton(.music)
                    }
                    HStack(spacing: 6) {
                        modeButton(.game)
                        Button(intent: WidgetMuteIntent()) {
                            VStack(spacing: 3) {
                                Image(systemName: state.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(state.muted ? "Unmute" : "Mute").font(.caption2.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .foregroundStyle(state.muted ? Color.white : Color.primary)
                            .background(state.muted ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.primary.opacity(0.1)),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func modeButton(_ mode: SoundMode) -> some View {
        let selected = state.mode == mode.rawValue
        return Button(intent: WidgetModeIntent(mode: mode)) {
            VStack(spacing: 3) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(mode.title).font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? AnyShapeStyle(mode.widgetColour) : AnyShapeStyle(Color.primary.opacity(0.1)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Presets widget

struct PresetsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SoundstagePresets", provider: SetupProvider()) { entry in
            PresetsWidgetView(setup: entry.setup)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Presets")
        .description("Switch to a saved sound with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PresetsWidgetView: View {
    let setup: SavedSetup
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let presets = Array(setup.presets.prefix(family == .systemMedium ? 6 : 4))
        if setup.soundbar == nil {
            NoSoundbarView()
        } else if presets.isEmpty {
            Text("Save a preset in Soundstage")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: family == .systemMedium ? 3 : 2)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(presets) { preset in
                    Button(intent: WidgetPresetIntent(presetID: preset.id.uuidString)) {
                        VStack(spacing: 4) {
                            Image(systemName: preset.symbol)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(preset.mode?.widgetColour ?? .orange)
                            Text(preset.name)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Control Centre

struct PowerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SoundstagePower", provider: PowerValueProvider()) { isOn in
            ControlWidgetToggle("Soundbar", isOn: isOn, action: SetPowerIntent()) { on in
                Label(on ? "On" : "Standby", systemImage: on ? "hifispeaker.fill" : "hifispeaker")
            }
            .tint(.orange)
        }
        .displayName("Soundbar power")
        .description("Switch the soundbar on or off.")
    }
}

struct PowerValueProvider: ControlValueProvider {
    var previewValue: Bool { true }
    func currentValue() async throws -> Bool { Store.load().state.power }
}

struct MuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SoundstageMute", provider: MuteValueProvider()) { muted in
            ControlWidgetToggle("Mute", isOn: muted, action: SetMuteIntent()) { on in
                Label(on ? "Muted" : "Sound on", systemImage: on ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .tint(.red)
        }
        .displayName("Mute soundbar")
        .description("Mute or unmute the soundbar.")
    }
}

struct MuteValueProvider: ControlValueProvider {
    var previewValue: Bool { false }
    func currentValue() async throws -> Bool { Store.load().state.muted }
}

struct VolumeUpControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SoundstageVolumeUp") {
            ControlWidgetButton(action: WidgetVolumeIntent(up: true)) {
                Label("Louder", systemImage: "speaker.plus.fill")
            }
        }
        .displayName("Soundbar louder")
        .description("Turn the soundbar up a little.")
    }
}

struct VolumeDownControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SoundstageVolumeDown") {
            ControlWidgetButton(action: WidgetVolumeIntent(up: false)) {
                Label("Quieter", systemImage: "speaker.minus.fill")
            }
        }
        .displayName("Soundbar quieter")
        .description("Turn the soundbar down a little.")
    }
}

struct PresetControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: PresetControlConfiguration) -> PresetEntity? { configuration.preset }
    func currentValue(configuration: PresetControlConfiguration) async throws -> PresetEntity? { configuration.preset }
}

struct PresetControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "SoundstagePreset", provider: PresetControlProvider()) { preset in
            ControlWidgetButton(action: RunPresetIntent(preset: preset)) {
                Label(preset?.name ?? "Preset", systemImage: preset?.symbol ?? "slider.horizontal.3")
            }
        }
        .displayName("Soundbar preset")
        .description("Switch to one of your saved presets.")
        .promptsForUserConfiguration()
    }
}
