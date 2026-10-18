import Foundation
import Network

/// Finds Klipsch soundbars on the home Wi-Fi.
///
/// First it listens for soundbars announcing themselves (they announce as cast and AirPlay
/// speakers), then, if that finds nothing, it asks every address on the network directly.
enum Discovery {
    static func find(progress: (@Sendable (String) -> Void)? = nil) async -> [SoundbarInfo] {
        progress?("Listening for your soundbar…")
        var found = await viaAnnouncements(seconds: 4)
        if found.isEmpty {
            progress?("Checking every address on your Wi-Fi…")
            found = await viaScan()
        }
        var unique: [SoundbarInfo] = []
        for info in found where !unique.contains(where: { $0.host == info.host || ($0.serial != nil && $0.serial == info.serial) }) {
            unique.append(info)
        }
        return unique.sorted { $0.displayName < $1.displayName }
    }

    // MARK: Announcements (Bonjour)

    static func viaAnnouncements(seconds: Double) async -> [SoundbarInfo] {
        let hosts = await announcedHosts(seconds: seconds)
        return await withTaskGroup(of: SoundbarInfo?.self) { group in
            for host in hosts {
                group.addTask { await SoundbarLink(host: host).identify() }
            }
            var result: [SoundbarInfo] = []
            for await info in group { if let info { result.append(info) } }
            return result
        }
    }

    /// The network addresses of everything announcing itself as a cast or AirPlay speaker.
    private static func announcedHosts(seconds: Double) async -> [String] {
        let collector = HostCollector()
        let queue = DispatchQueue(label: "soundstage.discovery")
        var browsers: [NWBrowser] = []
        for type in ["_googlecast._tcp", "_airplay._tcp"] {
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
            browser.browseResultsChangedHandler = { results, _ in
                for result in results { collector.resolve(result.endpoint, on: queue) }
            }
            browser.start(queue: queue)
            browsers.append(browser)
        }
        try? await Task.sleep(for: .seconds(seconds))
        browsers.forEach { $0.cancel() }
        // Give any last addresses a moment to come in.
        try? await Task.sleep(for: .milliseconds(600))
        return collector.finish()
    }

    /// Turns announced names into addresses by briefly connecting to each one.
    private final class HostCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var hosts: Set<String> = []
        private var seen: Set<String> = []
        private var connections: [NWConnection] = []

        func resolve(_ endpoint: NWEndpoint, on queue: DispatchQueue) {
            let key = "\(endpoint)"
            lock.lock()
            let isNew = seen.insert(key).inserted
            lock.unlock()
            guard isNew else { return }

            let parameters = NWParameters.tcp
            if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ip.version = .v4
            }
            let connection = NWConnection(to: endpoint, using: parameters)
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                switch state {
                case .ready:
                    if case .hostPort(let host, _) = connection?.currentPath?.remoteEndpoint {
                        self?.add(Self.text(for: host))
                    }
                    connection?.cancel()
                case .failed, .waiting:
                    connection?.cancel()
                default:
                    break
                }
            }
            lock.lock()
            connections.append(connection)
            lock.unlock()
            connection.start(queue: queue)
        }

        private func add(_ host: String?) {
            guard let host, !host.isEmpty else { return }
            lock.lock()
            hosts.insert(host)
            lock.unlock()
        }

        func finish() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            connections.forEach { $0.cancel() }
            connections.removeAll()
            return Array(hosts)
        }

        private static func text(for host: NWEndpoint.Host) -> String? {
            switch host {
            case .ipv4(let address):
                return address.rawValue.map(String.init).joined(separator: ".")
            case .ipv6(let address):
                // Strip any "%en0" interface suffix.
                return "\(address)".components(separatedBy: "%").first
            case .name(let name, _):
                return name
            @unknown default:
                return nil
            }
        }
    }

    // MARK: Asking every address

    static func viaScan() async -> [SoundbarInfo] {
        let addresses = LocalNetwork.neighbourAddresses()
        guard !addresses.isEmpty else { return [] }
        return await withTaskGroup(of: SoundbarInfo?.self) { group in
            var result: [SoundbarInfo] = []
            var iterator = addresses.makeIterator()
            let parallel = 48
            for _ in 0..<parallel {
                guard let address = iterator.next() else { break }
                group.addTask { await SoundbarLink(host: address).identify(timeout: 1.5) }
            }
            for await info in group {
                if let info { result.append(info) }
                if let address = iterator.next() {
                    group.addTask { await SoundbarLink(host: address).identify(timeout: 1.5) }
                }
            }
            return result
        }
    }
}

/// Works out which addresses are on the same home network as this phone.
enum LocalNetwork {
    struct Interface {
        let address: UInt32
        let mask: UInt32
        let name: String
    }

    static func wifiInterface() -> Interface? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var candidates: [Interface] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let flags = Int32(bitPattern: current.pointee.ifa_flags)
            guard let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  let maskPointer = current.pointee.ifa_netmask,
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: current.pointee.ifa_name)
            let address = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let mask = maskPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            // Skip self-assigned addresses (169.254.x.x).
            if address >> 16 == 0xA9FE { continue }
            candidates.append(Interface(address: address, mask: mask, name: name))
        }
        // Wi-Fi is "en0" on the phone. Elsewhere (the simulator on a Mac) take the first private network.
        return candidates.first { $0.name == "en0" } ?? candidates.first { isPrivate($0.address) } ?? candidates.first
    }

    private static func isPrivate(_ address: UInt32) -> Bool {
        address >> 24 == 10 || address >> 20 == 0xAC1 || address >> 16 == 0xC0A8
    }

    /// Every other address on this network, nearest first. Very large networks are trimmed to the
    /// 1,024 addresses around this phone, which covers any normal home.
    static func neighbourAddresses() -> [String] {
        guard let interface = wifiInterface() else { return [] }
        var mask = interface.mask
        if mask == 0 || ~mask > 1023 { mask = 0xFFFF_FC00 }
        let network = interface.address & mask
        let broadcast = network | ~mask
        guard broadcast > network + 1 else { return [] }
        let hosts = (network + 1)..<broadcast
        let sorted = hosts.sorted { abs(Int64($0) - Int64(interface.address)) < abs(Int64($1) - Int64(interface.address)) }
        return sorted.map(format)
    }

    static func ownAddress() -> String? { wifiInterface().map { format($0.address) } }

    static func format(_ value: UInt32) -> String {
        "\(value >> 24 & 0xFF).\(value >> 16 & 0xFF).\(value >> 8 & 0xFF).\(value & 0xFF)"
    }
}
