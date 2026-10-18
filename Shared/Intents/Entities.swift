import AppIntents
import Foundation

/// A saved preset for shortcuts, widgets and Control Centre.
struct PresetEntity: AppEntity, Identifiable {
    let id: String
    let name: String
    let symbol: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Preset"
    static let defaultQuery = PresetQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }

    init(_ preset: Preset) {
        id = preset.id.uuidString
        name = preset.name
        symbol = preset.symbol
    }

    static func all() -> [PresetEntity] { Store.load().presets.map(PresetEntity.init) }

    var preset: Preset? { Store.load().presets.first { $0.id.uuidString == id } }
}

struct PresetQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PresetEntity] {
        let all = PresetEntity.all()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func entities(matching string: String) async throws -> [PresetEntity] {
        let query = string.lowercased()
        return PresetEntity.all().filter { $0.name.lowercased().contains(query) || query.contains($0.name.lowercased()) }
    }

    func suggestedEntities() async throws -> [PresetEntity] { PresetEntity.all() }

    func defaultResult() async -> PresetEntity? { PresetEntity.all().first }
}

enum ModeChoice: String, AppEnum, CaseIterable {
    case movie, music, game, standard, direct, party

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sound Mode"
    static let caseDisplayRepresentations: [ModeChoice: DisplayRepresentation] = [
        .movie: DisplayRepresentation(title: "Movie", image: .init(systemName: "film")),
        .music: DisplayRepresentation(title: "Music", image: .init(systemName: "music.note")),
        .game: DisplayRepresentation(title: "Game", image: .init(systemName: "gamecontroller")),
        .standard: DisplayRepresentation(title: "Standard", image: .init(systemName: "speaker.wave.2")),
        .direct: DisplayRepresentation(title: "Direct", image: .init(systemName: "waveform")),
        .party: DisplayRepresentation(title: "Party", image: .init(systemName: "party.popper"))
    ]

    var mode: SoundMode { SoundMode(rawValue: rawValue) ?? .standard }
}

enum InputChoice: String, AppEnum, CaseIterable {
    case tv, hdmi1, hdmi2, spdif, aux, bluetooth

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Input"
    static let caseDisplayRepresentations: [InputChoice: DisplayRepresentation] = [
        .tv: "TV",
        .hdmi1: "HDMI 1",
        .hdmi2: "HDMI 2",
        .spdif: "Optical",
        .aux: "Aux",
        .bluetooth: "Bluetooth"
    ]

    var input: SoundInput { SoundInput(rawValue: rawValue) ?? .tv }
}

enum NightChoice: String, AppEnum, CaseIterable {
    case off, low, high

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Night Mode"
    static let caseDisplayRepresentations: [NightChoice: DisplayRepresentation] = [
        .off: "Off",
        .low: "Low",
        .high: "High"
    ]

    var level: NightLevel {
        switch self {
        case .off: .off
        case .low: .low
        case .high: .high
        }
    }
}

enum DialogueChoice: String, AppEnum, CaseIterable {
    case off, low, medium, high

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Dialogue Boost"
    static let caseDisplayRepresentations: [DialogueChoice: DisplayRepresentation] = [
        .off: "Off",
        .low: "Low",
        .medium: "Medium",
        .high: "High"
    ]

    var level: DialogueLevel {
        switch self {
        case .off: .off
        case .low: .low
        case .medium: .medium
        case .high: .high
        }
    }
}
