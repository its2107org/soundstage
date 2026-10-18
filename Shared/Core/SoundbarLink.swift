import Foundation

/// Talks to a Klipsch Cinema soundbar over the home Wi-Fi.
///
/// The soundbar runs a small web service with two calls:
///   GET  /api/getData?path=<setting>&roles=value   → [{"type":"i32_","i32_":55}]
///   POST /api/setData  {"path":…, "roles":"value", "value":{"type":…, …}}
/// Values are tagged with their type ("i32_", "bool_", "double_", "string_", or a named one
/// like "cinemaPostProcessorMode").
struct SoundbarLink: Sendable {
    let host: String

    /// Set by the screenshot mode so nothing tries to reach a real soundbar.
    nonisolated(unsafe) static var offline = false

    enum LinkError: Error, LocalizedError {
        case unreachable
        case badReply

        var errorDescription: String? {
            switch self {
            case .unreachable: "Couldn't reach the soundbar."
            case .badReply: "The soundbar sent back something unexpected."
            }
        }
    }

    enum Path {
        static let deviceName = "settings:/deviceName"
        static let manufacturer = "settings:/system/manufacturer"
        static let modelName = "settings:/system/modelName"
        static let serial = "settings:/system/serialNumber"
        static let version = "settings:/version"
        static let powerState = "powermanager:target"
        static let powerRequest = "powermanager:targetRequest"
        static let volume = "player:volume"
        static let mute = "settings:/mediaPlayer/mute"
        static let input = "settings:/cinema/physicalAudioInput"
        static let night = "settings:/cinema/nightMode"
        static let dialogue = "settings:/cinema/dialogMode"
        static let mode = "settings:/cinema/postProcessorMode"
        static let display = "settings:/cinema/ledMode"
        static let levels = "cinema:/channelVolumeSet"
        static let bass = "settings:/cinema/dsp/cinemaBass"
        static let mid = "settings:/cinema/dsp/cinemaMid"
        static let treble = "settings:/cinema/dsp/cinemaTreble"
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private var base: String {
        // Plain IPv6 addresses need brackets in a web address.
        host.contains(":") && host.filter({ $0 == ":" }).count > 1 ? "http://[\(host)]" : "http://\(host)"
    }

    // MARK: Low level

    func get(_ path: String, timeout: TimeInterval = 4) async throws -> [String: Any] {
        if Self.offline { throw LinkError.unreachable }
        guard var components = URLComponents(string: base + "/api/getData") else { throw LinkError.badReply }
        components.queryItems = [URLQueryItem(name: "path", value: path), URLQueryItem(name: "roles", value: "value")]
        // ":" and "/" are fine in a query, but "+" and "&" are not; encode strictly.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw LinkError.badReply }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw LinkError.unreachable
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LinkError.badReply }
        return try Self.unwrap(data)
    }

    func set(_ path: String, _ value: [String: Any], role: String = "value") async throws {
        if Self.offline { throw LinkError.unreachable }
        guard let url = URL(string: base + "/api/setData") else { throw LinkError.badReply }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["path": path, "roles": role, "value": value])
        let response: URLResponse
        do {
            (_, response) = try await Self.session.data(for: request)
        } catch {
            throw LinkError.unreachable
        }
        guard let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { throw LinkError.badReply }
    }

    /// The soundbar replies either with a bare list ([{…}]) or a wrapped object ({"value":{…}}).
    static func unwrap(_ data: Data) throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(with: data)
        if let list = json as? [Any], let first = list.first as? [String: Any] { return first }
        if let object = json as? [String: Any] {
            if let value = object["value"] as? [String: Any] { return value }
            if object["type"] != nil { return object }
        }
        throw LinkError.badReply
    }

    // MARK: Typed reads

    func string(_ path: String) async throws -> String {
        let item = try await get(path)
        if let s = item["string_"] as? String { return s }
        if let type = item["type"] as? String, let s = item[type] as? String { return s }
        throw LinkError.badReply
    }

    func int(_ path: String) async throws -> Int {
        let item = try await get(path)
        if let n = item["i32_"] as? NSNumber { return n.intValue }
        if let n = item["i64_"] as? NSNumber { return n.intValue }
        throw LinkError.badReply
    }

    func bool(_ path: String) async throws -> Bool {
        let item = try await get(path)
        if let b = item["bool_"] as? Bool { return b }
        if let n = item["bool_"] as? NSNumber { return n.boolValue }
        throw LinkError.badReply
    }

    func double(_ path: String) async throws -> Double {
        let item = try await get(path)
        if let n = item["double_"] as? NSNumber { return n.doubleValue }
        if let n = item["i32_"] as? NSNumber { return n.doubleValue }
        throw LinkError.badReply
    }

    /// Named values such as {"type":"cinemaNightMode","cinemaNightMode":"nightMode_1"}.
    func named(_ path: String, _ key: String) async throws -> String {
        let item = try await get(path)
        if let s = item[key] as? String { return s }
        if let type = item["type"] as? String, let s = item[type] as? String { return s }
        if let s = item["string_"] as? String { return s }
        throw LinkError.badReply
    }

    // MARK: Whole-soundbar reads

    /// Checks an address really is a Klipsch soundbar and returns what it's called.
    func identify(timeout: TimeInterval = 2.5) async -> SoundbarInfo? {
        guard let item = try? await get(Path.manufacturer, timeout: timeout),
              let maker = item["string_"] as? String, maker.localizedCaseInsensitiveContains("klipsch") else { return nil }
        async let name = try? string(Path.deviceName)
        async let model = try? string(Path.modelName)
        async let serial = try? string(Path.serial)
        async let version = try? string(Path.version)
        let modelName = await model ?? "Klipsch soundbar"
        return SoundbarInfo(host: host, name: await name ?? "", model: modelName, serial: await serial, firmware: await version)
    }

    func power() async throws -> Bool {
        let item = try await get(Path.powerState)
        if let nested = item["powerTarget"] as? [String: Any], let target = nested["target"] as? String {
            return target.lowercased() == "online"
        }
        if let target = (item["target"] ?? item["string_"]) as? String { return target.lowercased() == "online" }
        throw LinkError.badReply
    }

    func levels() async throws -> [String: Int] {
        let item = try await get(Path.levels)
        let variant = (item["variant"] as? [String: Any]) ?? item.filter { $0.key != "type" }
        var result: [String: Int] = [:]
        for (key, value) in variant {
            if let n = value as? NSNumber { result[key] = n.intValue }
        }
        return result
    }

    /// Reads everything at once. Anything that fails keeps its previous value; if the soundbar
    /// doesn't answer at all, this throws.
    func readState(previous: SoundbarState = SoundbarState()) async throws -> SoundbarState {
        let isOn = try await power()
        var state = previous
        state.power = isOn
        async let volume = try? int(Path.volume)
        async let muted = try? bool(Path.mute)
        async let input = try? named(Path.input, "cinemaPhysicalAudioInput")
        async let mode = try? named(Path.mode, "cinemaPostProcessorMode")
        async let night = try? named(Path.night, "cinemaNightMode")
        async let dialogue = try? named(Path.dialogue, "cinemaDialogMode")
        async let display = try? named(Path.display, "cinemaLEDMode")
        async let bass = try? double(Path.bass)
        async let mid = try? double(Path.mid)
        async let treble = try? double(Path.treble)
        async let channelLevels = try? levels()
        if let v = await volume { state.volume = v }
        if let v = await muted { state.muted = v }
        if let v = await input { state.input = v }
        if let v = await mode { state.mode = v }
        if let v = await night { state.night = v }
        if let v = await dialogue { state.dialogue = v }
        if let v = await display { state.display = v }
        if let v = await bass { state.bass = v }
        if let v = await mid { state.mid = v }
        if let v = await treble { state.treble = v }
        if let v = await channelLevels, !v.isEmpty { state.levels = v }
        state.updated = .now
        return state
    }

    // MARK: Changes

    func apply(_ change: SoundbarChange) async throws {
        switch change {
        case .power(let on):
            try await set(Path.powerRequest, ["type": "target", "target": on ? "online" : "networkStandby"], role: "activate")
        case .volume(let v):
            try await set(Path.volume, ["type": "i32_", "i32_": min(100, max(0, v))])
        case .muted(let m):
            try await set(Path.mute, ["type": "bool_", "bool_": m])
        case .input(let i):
            try await set(Path.input, ["type": "cinemaPhysicalAudioInput", "cinemaPhysicalAudioInput": i.rawValue])
        case .mode(let m):
            try await set(Path.mode, ["type": "cinemaPostProcessorMode", "cinemaPostProcessorMode": m.rawValue])
        case .night(let n):
            try await set(Path.night, ["type": "cinemaNightMode", "cinemaNightMode": n.rawValue])
        case .dialogue(let d):
            try await set(Path.dialogue, ["type": "cinemaDialogMode", "cinemaDialogMode": d.rawValue])
        case .display(let d):
            try await set(Path.display, ["type": "cinemaLEDMode", "cinemaLEDMode": d.rawValue])
        case .bass(let v):
            try await set(Path.bass, ["type": "double_", "double_": Equaliser.clamp(v)])
        case .mid(let v):
            try await set(Path.mid, ["type": "double_", "double_": Equaliser.clamp(v)])
        case .treble(let v):
            try await set(Path.treble, ["type": "double_", "double_": Equaliser.clamp(v)])
        case .level(let key, let v):
            let clamped = min(Channel.range.upperBound, max(Channel.range.lowerBound, v))
            try await set(Path.levels, ["type": "variant", "variant": [key: clamped]])
        }
    }
}
