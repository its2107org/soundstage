import SwiftUI

/// Saves how the soundbar sounds right now as a preset, or edits one.
struct PresetEditor: View {
    let existing: Preset?

    @State private var model = SoundbarModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = Preset.symbols[0]
    @State private var includeVolume = false
    @State private var useCurrentSound = true

    private var draft: Preset {
        var preset: Preset
        if let existing, !useCurrentSound {
            preset = existing
        } else {
            preset = Preset.capture(model.state, name: name, symbol: symbol, includeVolume: includeVolume)
            if let existing { preset.id = existing.id }
        }
        preset.name = name.trimmingCharacters(in: .whitespaces)
        preset.symbol = symbol
        if existing != nil, !useCurrentSound {
            preset.volume = includeVolume ? (existing?.volume ?? model.state.volume) : nil
        }
        return preset
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: symbol)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        TextField("Name", text: $name)
                            .font(.title3.weight(.semibold))
                            .submitLabel(.done)
                    }
                    .padding(.vertical, 4)
                }

                Section("Symbol") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                        ForEach(Preset.symbols, id: \.self) { option in
                            Button { symbol = option } label: {
                                Image(systemName: option)
                                    .font(.body.weight(.semibold))
                                    .frame(width: 42, height: 42)
                                    .foregroundStyle(option == symbol ? Color.white : Color.primary)
                                    .background(option == symbol ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.tertiarySystemFill)), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    if existing != nil {
                        Toggle("Use the soundbar's current sound", isOn: $useCurrentSound)
                    }
                    Toggle("Include volume", isOn: $includeVolume)
                } footer: {
                    Text(draft.summary.isEmpty ? " " : draft.summary)
                }

                if let existing {
                    Section {
                        Button("Delete preset", role: .destructive) {
                            model.deletePreset(existing)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New preset" : "Edit preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.savePreset(draft)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    symbol = existing.symbol
                    includeVolume = existing.volume != nil
                    useCurrentSound = false
                } else {
                    name = model.state.soundMode?.title ?? ""
                    symbol = Preset.symbols.first { $0.hasPrefix(model.state.soundMode?.symbol ?? "-") } ?? Preset.symbols[0]
                }
            }
        }
        .presentationDetents([.large])
    }
}
