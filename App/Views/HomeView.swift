import SwiftUI

struct HomeView: View {
    @State private var model = SoundbarModel.shared
    @State private var router = Router.shared

    private var state: SoundbarState { model.state }
    private var tint: Color { state.soundMode?.colour ?? .accentColor }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                            .padding(.horizontal, 4)
                            .padding(.bottom, 4)
                        switch (model.connection, state.power) {
                        case (.unreachable, _):
                            UnreachableCard()
                        case (_, false):
                            OffCard()
                        default:
                            volumeCard
                            presetsRow
                                .id("presets")
                            modesCard
                            inputCard
                            clarityCard
                            equaliserCard
                                .id("eq")
                            speakersCard
                                .id("speakers")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                    .animation(.smooth(duration: 0.35), value: state.power)
                    .animation(.smooth(duration: 0.35), value: model.connection)
                }
                .scrollIndicators(.hidden)
                .refreshable { await model.refreshNow() }
                .onChange(of: router.scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.smooth) { proxy.scrollTo(target, anchor: .top) }
                    router.scrollTarget = nil
                }
                .onAppear {
                    if let target = router.scrollTarget {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            proxy.scrollTo(target, anchor: .top)
                            router.scrollTarget = nil
                        }
                    }
                }
            }
            .background(AmbientBackground(colour: state.power && model.connection != .unreachable ? tint : nil))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { router.sheet = .settings } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.togglePower() } label: {
                        Image(systemName: "power")
                            .foregroundStyle(state.power ? tint : Color.secondary)
                    }
                    .disabled(model.connection == .unreachable)
                    .accessibilityLabel(state.power ? "Turn off" : "Turn on")
                }
            }
            .overlay(alignment: .bottom) { ProblemToast() }
        }
        .sensoryFeedback(.selection, trigger: state.mode)
        .sensoryFeedback(.selection, trigger: state.input)
        .sensoryFeedback(.impact(weight: .medium), trigger: state.power)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.soundbar?.displayName ?? "Soundbar")
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColour)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
        }
    }

    private var statusColour: Color {
        switch model.connection {
        case .connecting: .secondary
        case .unreachable: .red
        case .connected: state.power ? .green : .secondary
        }
    }

    private var statusText: String {
        let name = model.soundbar?.model.replacingOccurrences(of: "Klipsch ", with: "") ?? ""
        switch model.connection {
        case .connecting: return "Connecting…"
        case .unreachable: return "Not reachable"
        case .connected:
            return state.power ? [name, state.inputTitle, state.modeTitle].filter { !$0.isEmpty }.joined(separator: " · ")
                               : [name, "Standby"].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    // MARK: Volume

    private var volumeCard: some View {
        Card {
            HStack(alignment: .center) {
                RoundIconButton(symbol: "minus") { model.nudgeVolume(-2) }
                    .accessibilityLabel("Quieter")
                Spacer()
                VStack(spacing: 0) {
                    Text("\(state.volume)")
                        .font(.system(size: 60, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(state.volume)))
                        .foregroundStyle(state.muted ? Color.secondary : Color.primary)
                        .animation(.snappy(duration: 0.2), value: state.volume)
                    Text(state.muted ? "Muted" : "Volume")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(state.muted ? Color.red : Color.secondary)
                }
                Spacer()
                RoundIconButton(symbol: "plus") { model.nudgeVolume(2) }
                    .accessibilityLabel("Louder")
            }
            VolumeSlider(value: state.volume, muted: state.muted, tint: tint) { model.set(.volume($0), smooth: true) }
            Button {
                model.set(.muted(!state.muted))
            } label: {
                Label(state.muted ? "Unmute" : "Mute", systemImage: state.muted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(state.muted ? AnyShapeStyle(Color.red.opacity(0.16)) : AnyShapeStyle(Color(.tertiarySystemFill)),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(state.muted ? Color.red : Color.primary)
            }
            .buttonStyle(PressableStyle())
            .sensoryFeedback(.selection, trigger: state.muted)
        }
    }

    // MARK: Presets

    private var presetsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Presets")
                .font(.headline)
                .padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.presets) { preset in
                        Button { model.apply(preset) } label: {
                            Chip(title: preset.name, symbol: preset.symbol, selected: model.matches(preset), tint: tint)
                        }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            Button { router.sheet = .editPreset(preset.id) } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) { model.deletePreset(preset) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    Button { router.sheet = .newPreset } label: {
                        Chip(title: model.presets.isEmpty ? "Save this sound" : "New", symbol: "plus", selected: false)
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: Sound mode

    private var modesCard: some View {
        Card("Sound mode") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(SoundMode.allCases) { mode in
                    let selected = state.mode == mode.rawValue
                    Button { model.set(.mode(mode)) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 22, weight: .semibold))
                                .frame(height: 26)
                            Text(mode.title)
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 82)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(selected ? AnyShapeStyle(mode.colour.gradient) : AnyShapeStyle(Color(.tertiarySystemFill)),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .animation(.snappy(duration: 0.25), value: state.mode)
        }
    }

    // MARK: Input

    private var inputCard: some View {
        Card("Input") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let current = state.soundInput, !current.isSelectable {
                        Chip(title: current.title, symbol: current.symbol, selected: true, tint: tint)
                    } else if state.soundInput == nil {
                        Chip(title: state.inputTitle, symbol: "dot.radiowaves.left.and.right", selected: true, tint: tint)
                    }
                    ForEach(SoundInput.selectable) { input in
                        Button { model.set(.input(input)) } label: {
                            Chip(title: input.title, symbol: input.symbol, selected: state.input == input.rawValue, tint: tint)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: Night and dialogue

    private var clarityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("Night mode", systemImage: "moon.fill")
                    .font(.headline)
                Picker("Night mode", selection: Binding(get: { state.nightLevel }, set: { model.set(.night($0)) })) {
                    ForEach(NightLevel.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Quietens loud moments and lifts quiet ones.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Dialogue boost", systemImage: "person.wave.2.fill")
                    .font(.headline)
                Picker("Dialogue boost", selection: Binding(get: { state.dialogueLevel }, set: { model.set(.dialogue($0)) })) {
                    ForEach(DialogueLevel.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Makes voices clearer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Equaliser

    private var equaliserCard: some View {
        Card("Equaliser") {
            HStack(spacing: 4) {
                BandSlider(title: "Bass", value: state.bass, range: Equaliser.range, tint: tint) { model.set(.bass($0), smooth: true) }
                BandSlider(title: "Mid", value: state.mid, range: Equaliser.range, tint: tint) { model.set(.mid($0), smooth: true) }
                BandSlider(title: "Treble", value: state.treble, range: Equaliser.range, tint: tint) { model.set(.treble($0), smooth: true) }
            }
            .padding(.vertical, 4)
            .sensoryFeedback(.selection, trigger: state.bass)
            .sensoryFeedback(.selection, trigger: state.mid)
            .sensoryFeedback(.selection, trigger: state.treble)
            HStack(spacing: 8) {
                ForEach(Equaliser.picks) { pick in
                    let selected = state.bass == pick.bass && state.mid == pick.mid && state.treble == pick.treble
                    Button { model.applyPick(pick) } label: {
                        Text(pick.name)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(selected ? AnyShapeStyle(tint) : AnyShapeStyle(Color(.tertiarySystemFill)), in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    // MARK: Speakers

    private var speakersCard: some View {
        let keys = Channel.sorted(state.levels.keys)
        let anyChanged = state.levels.values.contains { $0 != 0 }
        return Card("Speaker levels", trailing: anyChanged ? AnyView(
            Button("Reset") { for key in keys { model.set(.level(key, 0)) } }
                .font(.subheadline.weight(.semibold))
        ) : nil) {
            if keys.isEmpty {
                Text("Your soundbar hasn't reported its speakers yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                if index > 0 { Divider() }
                let value = state.levels[key] ?? 0
                VStack(spacing: 6) {
                    HStack {
                        Label(Channel.title(key), systemImage: Channel.symbol(key))
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(signed(value))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(value)))
                            .foregroundStyle(value == 0 ? Color.secondary : Color.primary)
                    }
                    Slider(value: Binding(get: { Double(value) },
                                          set: { model.set(.level(key, Int($0.rounded())), smooth: true) }),
                           in: Double(Channel.range.lowerBound)...Double(Channel.range.upperBound), step: 1)
                        .tint(tint)
                        .accessibilityLabel(Channel.title(key))
                }
                .sensoryFeedback(.selection, trigger: value)
            }
        }
    }
}

// MARK: - Off and unreachable

private struct OffCard: View {
    @State private var model = SoundbarModel.shared

    var body: some View {
        Card {
            VStack(spacing: 18) {
                Button { model.set(.power(true)) } label: {
                    Image(systemName: "power")
                        .font(.system(size: 44, weight: .semibold))
                        .frame(width: 120, height: 120)
                        .background(Color(.tertiarySystemFill), in: Circle())
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .accessibilityLabel("Turn on")
                VStack(spacing: 4) {
                    Text("\(model.soundbar?.displayName ?? "Soundbar") is on standby")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Tap to turn it on.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        }
    }
}

private struct UnreachableCard: View {
    @State private var model = SoundbarModel.shared
    @State private var retrying = false

    var body: some View {
        Card {
            VStack(spacing: 16) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, isActive: retrying)
                VStack(spacing: 6) {
                    Text("Can't reach \(model.soundbar?.displayName ?? "the soundbar")")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Check it's plugged in and that this phone is on the same Wi-Fi.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 10) {
                    Button {
                        Task {
                            retrying = true
                            await model.refreshNow()
                            retrying = false
                        }
                    } label: {
                        Text("Try again")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    Button {
                        Task {
                            retrying = true
                            await model.search()
                            if let first = model.found.first(where: { $0.serial == model.soundbar?.serial }) ?? model.found.first {
                                await model.choose(first)
                            }
                            retrying = false
                        }
                    } label: {
                        Text("Find it again")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
                .disabled(retrying)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}

private struct ProblemToast: View {
    @State private var model = SoundbarModel.shared

    var body: some View {
        Group {
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: problem) {
                        try? await Task.sleep(for: .seconds(3))
                        model.problem = nil
                    }
            }
        }
        .animation(.smooth, value: model.problem)
    }
}
