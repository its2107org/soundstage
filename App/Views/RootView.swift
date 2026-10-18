import SwiftUI

struct RootView: View {
    @State private var model = SoundbarModel.shared
    @State private var router = Router.shared

    var body: some View {
        Group {
            if model.soundbar == nil {
                WelcomeView()
            } else {
                HomeView()
            }
        }
        .animation(.smooth, value: model.soundbar == nil)
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .settings:
                SettingsView()
            case .newPreset:
                PresetEditor(existing: nil)
            case .editPreset(let id):
                PresetEditor(existing: model.presets.first { $0.id == id })
            case .roomTune:
                RoomTuneView()
            }
        }
    }
}

// MARK: - First run

struct WelcomeView: View {
    @State private var model = SoundbarModel.shared
    @State private var address = ""
    @State private var trying = false
    @State private var addressFailed = false
    @FocusState private var addressFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                SoundWaves(animate: model.isSearching)
                    .frame(width: 190, height: 190)
                    .padding(.top, 60)

                VStack(spacing: 10) {
                    Text("Soundstage")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text(model.searchMessage ?? "Control your Klipsch soundbar over your home Wi-Fi.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                }
                .padding(.horizontal, 32)

                if model.found.count > 1 {
                    VStack(spacing: 10) {
                        ForEach(model.found, id: \.host) { info in
                            Button { Task { await model.choose(info) } } label: {
                                HStack {
                                    Image(systemName: "hifispeaker.2.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.accentColor)
                                    VStack(alignment: .leading) {
                                        Text(info.displayName).font(.headline)
                                        Text(info.model).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .padding(16)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                }

                if model.searchFinished && model.found.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Check that:")
                            .font(.headline)
                        Label("The soundbar is plugged in and set up on Wi-Fi in the Klipsch app.", systemImage: "wifi")
                        Label("This phone is on the same Wi-Fi.", systemImage: "iphone.radiowaves.left.and.right")
                        Label("Local Network is on for Soundstage in Settings › Privacy & Security.", systemImage: "lock.shield")
                    }
                    .font(.subheadline)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 20)
                }

                if !model.isSearching {
                    VStack(spacing: 14) {
                        Button {
                            Task { await model.search() }
                        } label: {
                            Text(model.searchFinished ? "Search again" : "Find my soundbar")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)

                        if model.searchFinished {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Or enter its address")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    TextField("e.g. 192.168.1.40", text: $address)
                                        .keyboardType(.numbersAndPunctuation)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .focused($addressFocused)
                                        .submitLabel(.go)
                                        .onSubmit { tryAddress() }
                                        .padding(.horizontal, 14)
                                        .frame(height: 48)
                                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    Button { tryAddress() } label: {
                                        if trying { ProgressView() } else { Text("Connect").font(.headline) }
                                    }
                                    .frame(width: 96, height: 48)
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.roundedRectangle(radius: 14))
                                    .disabled(address.isEmpty || trying)
                                }
                                if addressFailed {
                                    Text("No soundbar answered at that address.")
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                }
                                Text("You'll find it in the Klipsch app under the soundbar's settings, or in your router's list of devices.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 40)
            .animation(.smooth, value: model.isSearching)
            .animation(.smooth, value: model.found)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .task {
            if !Demo.isDemo && !model.searchFinished { await model.search() }
        }
    }

    private func tryAddress() {
        guard !address.isEmpty, !trying else { return }
        addressFocused = false
        trying = true
        addressFailed = false
        Task {
            let ok = await model.tryAddress(address)
            trying = false
            addressFailed = !ok
        }
    }
}

/// Rings of sound spreading out, used while looking for the soundbar.
struct SoundWaves: View {
    var animate: Bool

    var body: some View {
        TimelineView(.animation(paused: !animate)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius = min(size.width, size.height) / 2
                for ring in 0..<4 {
                    let phase = animate ? (time / 2.4 + Double(ring) / 4).truncatingRemainder(dividingBy: 1) : Double(ring + 1) / 4.6
                    let radius = maxRadius * (0.3 + 0.7 * phase)
                    let rect = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: rect), with: .color(Color.accentColor.opacity(0.75 * (1 - phase))), lineWidth: 3)
                }
                let core = maxRadius * 0.3
                context.fill(Path(ellipseIn: CGRect(x: centre.x - core, y: centre.y - core, width: core * 2, height: core * 2)),
                             with: .linearGradient(Gradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)]),
                                                   startPoint: CGPoint(x: centre.x - core, y: centre.y - core),
                                                   endPoint: CGPoint(x: centre.x + core, y: centre.y + core)))
            }
            .overlay {
                Image(systemName: "hifispeaker.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}
