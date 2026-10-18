import Foundation

// The settings a Klipsch Cinema soundbar understands, with the names it uses for them on the wire.

enum SoundMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case movie, music, game, standard, direct, party

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movie: "Movie"
        case .music: "Music"
        case .game: "Game"
        case .standard: "Standard"
        case .direct: "Direct"
        case .party: "Party"
        }
    }

    var symbol: String {
        switch self {
        case .movie: "film"
        case .music: "music.note"
        case .game: "gamecontroller"
        case .standard: "speaker.wave.2"
        case .direct: "waveform"
        case .party: "party.popper"
        }
    }
}

enum SoundInput: String, CaseIterable, Codable, Identifiable, Sendable {
    case tv, hdmiarc, hdmi1, hdmi2, spdif, aux, bluetooth
    // Streaming inputs. The soundbar switches to these itself when something starts playing to it.
    case googlecast, spotify, alexa, airplay

    var id: String { rawValue }

    static let selectable: [SoundInput] = [.tv, .hdmi1, .hdmi2, .spdif, .aux, .bluetooth]

    /// The Cinema 1200 calls its TV connection "hdmiarc" rather than "tv".
    static func choices(arc: Bool) -> [SoundInput] {
        arc ? [.hdmiarc, .hdmi1, .hdmi2, .spdif, .aux, .bluetooth] : selectable
    }

    var isSelectable: Bool { Self.selectable.contains(self) || self == .hdmiarc }

    /// Whether this soundbar names its TV input "hdmiarc".
    static func usesARC(model: String?, current: String) -> Bool {
        current == SoundInput.hdmiarc.rawValue || (model ?? "").contains("1200")
    }

    var title: String {
        switch self {
        case .tv, .hdmiarc: "TV"
        case .hdmi1: "HDMI 1"
        case .hdmi2: "HDMI 2"
        case .spdif: "Optical"
        case .aux: "Aux"
        case .bluetooth: "Bluetooth"
        case .googlecast: "Google Cast"
        case .spotify: "Spotify"
        case .alexa: "Alexa"
        case .airplay: "AirPlay"
        }
    }

    var symbol: String {
        switch self {
        case .tv, .hdmiarc: "tv"
        case .hdmi1, .hdmi2: "cable.connector.horizontal"
        case .spdif: "fibrechannel"
        case .aux: "cable.coaxial"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .googlecast, .airplay: "airplayaudio"
        case .spotify: "music.note.list"
        case .alexa: "mic"
        }
    }
}

enum NightLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    case off = "nightMode_0"
    case low = "nightMode_1"
    case high = "nightMode_2"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .high: "High"
        }
    }
}

enum DialogueLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    case off = "dialog_0"
    case low = "dialog_1"
    case medium = "dialog_2"
    case high = "dialog_3"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

enum DisplayLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    case off
    case dim
    case normal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .dim: "Dim"
        case .normal: "Bright"
        }
    }
}

/// One speaker level the soundbar reports (subwoofer, each surround, and any others it has).
enum Channel {
    static let range: ClosedRange<Int> = -6...6
    static let order = ["sub", "surr_L", "surr_R"]

    static func title(_ key: String) -> String {
        switch key {
        case "sub": return "Subwoofer"
        case "surr_L": return "Left surround"
        case "surr_R": return "Right surround"
        case "center", "centre": return "Centre"
        default:
            // Turn names like "height_L" or "frontHeight" into "Height L" / "Front height".
            var words: [String] = []
            var current = ""
            for ch in key {
                if ch == "_" || ch == " " {
                    if !current.isEmpty { words.append(current) }
                    current = ""
                } else if ch.isUppercase && !current.isEmpty && current.last?.isLowercase == true {
                    words.append(current)
                    current = String(ch)
                } else {
                    current.append(ch)
                }
            }
            if !current.isEmpty { words.append(current) }
            let mapped = words.map { word -> String in
                switch word.lowercased() {
                case "l": return "left"
                case "r": return "right"
                case "surr": return "surround"
                default: return word.lowercased()
                }
            }
            let text = mapped.joined(separator: " ")
            return text.prefix(1).uppercased() + text.dropFirst()
        }
    }

    static func symbol(_ key: String) -> String {
        switch key {
        case "sub": return "hifispeaker.fill"
        case "surr_L": return "speaker.wave.2.fill"
        case "surr_R": return "speaker.wave.2.fill"
        default: return "speaker.fill"
        }
    }

    static func sorted(_ keys: some Collection<String>) -> [String] {
        keys.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? Int.max
            let ib = order.firstIndex(of: b) ?? Int.max
            return ia == ib ? a < b : ia < ib
        }
    }
}

enum Equaliser {
    static let range: ClosedRange<Double> = -10...6

    struct Pick: Identifiable, Hashable {
        let name: String
        let bass: Double
        let mid: Double
        let treble: Double
        var id: String { name }
    }

    static let picks: [Pick] = [
        Pick(name: "Flat", bass: 0, mid: 0, treble: 0),
        Pick(name: "Voice", bass: -2, mid: 3, treble: 1),
        Pick(name: "Bass", bass: 4, mid: 0, treble: -1),
        Pick(name: "Bright", bass: -1, mid: 0, treble: 3)
    ]
}

/// Everything the app shows about the soundbar right now.
struct SoundbarState: Codable, Equatable, Sendable {
    var power = false
    var volume = 0
    var muted = false
    var input = SoundInput.tv.rawValue
    var mode = SoundMode.standard.rawValue
    var night = NightLevel.off.rawValue
    var dialogue = DialogueLevel.off.rawValue
    var display = DisplayLevel.normal.rawValue
    var bass = 0.0
    var mid = 0.0
    var treble = 0.0
    var levels: [String: Int] = [:]
    var updated: Date?

    var soundMode: SoundMode? { SoundMode(rawValue: mode) }
    var soundInput: SoundInput? { SoundInput(rawValue: input) }
    var nightLevel: NightLevel { NightLevel(rawValue: night) ?? .off }
    var dialogueLevel: DialogueLevel { DialogueLevel(rawValue: dialogue) ?? .off }
    var displayLevel: DisplayLevel { DisplayLevel(rawValue: display) ?? .normal }

    var inputTitle: String { soundInput?.title ?? input.capitalized }
    var modeTitle: String { soundMode?.title ?? mode.capitalized }
}

/// The soundbar this phone controls.
struct SoundbarInfo: Codable, Equatable, Hashable, Sendable {
    /// The soundbar's address on the home network, e.g. "192.168.1.40" (or "host:port").
    var host: String
    var name: String
    var model: String
    var serial: String?
    var firmware: String?

    var displayName: String { name.isEmpty ? model : name }
}

/// A saved combination of settings, applied with one tap.
struct Preset: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var symbol: String
    var mode: SoundMode?
    var night: NightLevel?
    var dialogue: DialogueLevel?
    var bass: Double?
    var mid: Double?
    var treble: Double?
    var levels: [String: Int]?
    var volume: Int?

    static let defaults: [Preset] = [
        Preset(name: "Film", symbol: "film.fill", mode: .movie, night: .off, dialogue: .off,
               bass: 2, mid: 0, treble: 0, levels: ["sub": 2]),
        Preset(name: "Late night", symbol: "moon.stars.fill", mode: .movie, night: .high, dialogue: .medium,
               bass: -2, mid: 1, treble: 0, levels: ["sub": -3]),
        Preset(name: "Music", symbol: "music.note", mode: .music, night: .off, dialogue: .off,
               bass: 0, mid: 0, treble: 0, levels: ["sub": 0]),
        Preset(name: "Sport", symbol: "sportscourt.fill", mode: .standard, night: .off, dialogue: .low,
               bass: 0, mid: 1, treble: 1)
    ]

    static let symbols = ["film.fill", "moon.stars.fill", "music.note", "sportscourt.fill", "gamecontroller.fill",
                          "tv.fill", "popcorn.fill", "headphones", "mic.fill", "party.popper.fill",
                          "sun.max.fill", "bed.double.fill", "sofa.fill", "star.fill", "heart.fill", "speaker.wave.3.fill"]

    /// A preset holding how the soundbar sounds right now.
    static func capture(_ state: SoundbarState, name: String, symbol: String, includeVolume: Bool) -> Preset {
        Preset(name: name, symbol: symbol, mode: state.soundMode, night: state.nightLevel, dialogue: state.dialogueLevel,
               bass: state.bass, mid: state.mid, treble: state.treble,
               levels: state.levels.isEmpty ? nil : state.levels, volume: includeVolume ? state.volume : nil)
    }

    /// Short description such as "Movie · Night high · Sub +2".
    var summary: String {
        var parts: [String] = []
        if let mode { parts.append(mode.title) }
        if let night, night != .off { parts.append("Night \(night.title.lowercased())") }
        if let dialogue, dialogue != .off { parts.append("Dialogue \(dialogue.title.lowercased())") }
        if let sub = levels?["sub"], sub != 0 { parts.append("Sub \(sub > 0 ? "+" : "")\(sub)") }
        if let volume { parts.append("Volume \(volume)") }
        return parts.joined(separator: " · ")
    }
}

/// One change to make on the soundbar.
enum SoundbarChange: Sendable, Equatable {
    case power(Bool)
    case volume(Int)
    case muted(Bool)
    case input(SoundInput)
    case mode(SoundMode)
    case night(NightLevel)
    case dialogue(DialogueLevel)
    case display(DisplayLevel)
    case bass(Double)
    case mid(Double)
    case treble(Double)
    case level(String, Int)

    /// Which setting this touches (used so a slow refresh doesn't undo a change in flight).
    var field: String {
        switch self {
        case .power: "power"
        case .volume: "volume"
        case .muted: "muted"
        case .input: "input"
        case .mode: "mode"
        case .night: "night"
        case .dialogue: "dialogue"
        case .display: "display"
        case .bass: "bass"
        case .mid: "mid"
        case .treble: "treble"
        case .level(let key, _): "level-\(key)"
        }
    }

    func apply(to state: inout SoundbarState) {
        switch self {
        case .power(let on): state.power = on
        case .volume(let v): state.volume = min(100, max(0, v))
        case .muted(let m): state.muted = m
        case .input(let i): state.input = i.rawValue
        case .mode(let m): state.mode = m.rawValue
        case .night(let n): state.night = n.rawValue
        case .dialogue(let d): state.dialogue = d.rawValue
        case .display(let d): state.display = d.rawValue
        case .bass(let v): state.bass = Equaliser.clamp(v)
        case .mid(let v): state.mid = Equaliser.clamp(v)
        case .treble(let v): state.treble = Equaliser.clamp(v)
        case .level(let key, let v): state.levels[key] = min(Channel.range.upperBound, max(Channel.range.lowerBound, v))
        }
    }
}

extension Equaliser {
    /// Keeps a value in range, to the nearest half step (the app only offers half steps when the
    /// soundbar has shown it keeps them).
    static func clamp(_ value: Double) -> Double { min(range.upperBound, max(range.lowerBound, (value * 2).rounded() / 2)) }
}

extension Preset {
    /// The changes needed to apply this preset. The sound mode goes first because the soundbar
    /// can reset other settings when it switches mode.
    var changes: [SoundbarChange] {
        var list: [SoundbarChange] = []
        if let mode { list.append(.mode(mode)) }
        if let night { list.append(.night(night)) }
        if let dialogue { list.append(.dialogue(dialogue)) }
        if let bass { list.append(.bass(bass)) }
        if let mid { list.append(.mid(mid)) }
        if let treble { list.append(.treble(treble)) }
        for key in Channel.sorted((levels ?? [:]).keys) { list.append(.level(key, levels![key]!)) }
        if let volume { list.append(.volume(volume)) }
        return list
    }
}
