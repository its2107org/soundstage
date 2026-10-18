import SwiftUI

struct SettingsView: View {
    @State private var model = SoundbarModel.shared
    @State private var router = Router.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmForget = false

    var body: some View {
        NavigationStack {
            Form {
                if let soundbar = model.soundbar {
                    Section("Soundbar") {
                        LabeledContent("Name", value: soundbar.displayName)
                        LabeledContent("Model", value: soundbar.model)
                        LabeledContent("Address", value: soundbar.host)
                        if let firmware = soundbar.firmware, !firmware.isEmpty {
                            LabeledContent("Software", value: firmware)
                        }
                        Button("Use a different soundbar") { confirmForget = true }
                    }
                }

                Section {
                    Picker("Display", selection: Binding(get: { model.state.displayLevel }, set: { model.set(.display($0)) })) {
                        ForEach(DisplayLevel.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper(value: Binding(get: { model.volumeStep }, set: { model.setVolumeStep($0) }), in: 1...10) {
                        LabeledContent("Volume buttons step", value: "\(model.volumeStep)")
                    }
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Display is the soundbar's front light. Volume buttons step is how much the widget, Siri and Control Centre buttons change the volume.")
                }

                Section {
                    ForEach(model.presets) { preset in
                        Button {
                            router.sheet = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { router.sheet = .editPreset(preset.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: preset.symbol)
                                    .frame(width: 28)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name).foregroundStyle(.primary)
                                    Text(preset.summary).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets.sorted(by: >) { model.deletePreset(model.presets[index]) }
                    }
                    .onMove { model.movePresets(from: $0, to: $1) }
                } header: {
                    HStack {
                        Text("Presets")
                        Spacer()
                        EditButton().font(.footnote)
                    }
                }

                Section {
                    Text("Room tuning, firmware updates and Wi-Fi set-up still happen in the Klipsch app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Use a different soundbar?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Find soundbars") {
                    model.forgetSoundbar()
                    dismiss()
                }
            } message: {
                Text("Soundstage will forget this soundbar and look for others. Your presets are kept.")
            }
            .task { await model.refreshInfo() }
        }
    }
}
