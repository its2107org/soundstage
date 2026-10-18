import Accelerate
import AVFoundation
import Foundation

/// Works out equaliser and subwoofer settings for the room.
///
/// The phone plays pink noise (a hiss with equal energy in every octave) through the soundbar,
/// listens with its microphone from the listening seat, and compares how loud each octave
/// arrives. Octaves the room makes too loud are turned down, and quiet ones up.
enum RoomTuning {
    /// Centre frequencies of the octave bands that are measured.
    static let bands: [Double] = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000]

    struct Result: Equatable, Sendable {
        var bass: Double
        var mid: Double
        var treble: Double
        var sub: Int
        /// Measured level of each band relative to the middle of the range, in dB.
        var response: [Double]
    }

    enum TuneError: Error, LocalizedError, Equatable {
        case tooQuiet
        case noMicrophone

        var errorDescription: String? {
            switch self {
            case .tooQuiet: "The test sound was too quiet to measure. Turn the volume up a little and try again."
            case .noMicrophone: "Soundstage needs the microphone to hear the test sound. You can turn it on in Settings › Soundstage."
            }
        }
    }

    // MARK: Analysis (pure, so the build check can test it)

    /// Power in each octave band, in dB.
    static func bandLevels(_ samples: [Float], sampleRate: Double) -> [Double] {
        let n = 8192
        let log2n = vDSP_Length(13)
        guard samples.count >= n, let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return bands.map { _ in -200 }
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var power = [Double](repeating: 0, count: n / 2)
        var windowed = [Float](repeating: 0, count: n)
        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)

        var start = 0
        while start + n <= samples.count {
            samples.withUnsafeBufferPointer { source in
                vDSP_vmul(source.baseAddress! + start, 1, window, 1, &windowed, 1, vDSP_Length(n))
            }
            real.withUnsafeMutableBufferPointer { r in
                imag.withUnsafeMutableBufferPointer { i in
                    var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                    windowed.withUnsafeBufferPointer { w in
                        w.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complex in
                            vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(n / 2))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    for k in 1..<(n / 2) {
                        power[k] += Double(r[k] * r[k] + i[k] * i[k])
                    }
                }
            }
            start += n / 2
        }

        let binWidth = sampleRate / Double(n)
        return bands.map { centre in
            let low = centre / 2.0.squareRoot()
            let high = centre * 2.0.squareRoot()
            var total = 0.0
            for k in 1..<(n / 2) {
                let f = Double(k) * binWidth
                if f >= low && f < high { total += power[k] }
            }
            return 10 * log10(max(total, 1e-20))
        }
    }

    /// Turns measured band levels (test sound playing, and silence) into settings.
    static func corrections(noise: [Double], ambient: [Double]) throws -> Result {
        // The test sound must be well above the room's background noise in the middle bands.
        let middle = [3, 4, 5, 6, 7] // 250 Hz to 4 kHz
        let margin = middle.map { noise[$0] - ambient[$0] }.reduce(0, +) / Double(middle.count)
        guard margin >= 10 else { throw TuneError.tooQuiet }

        let reference = [3, 4, 5, 6].map { noise[$0] }.reduce(0, +) / 4 // 250 Hz to 2 kHz
        let response = noise.map { $0 - reference }
        func average(_ indexes: [Int]) -> Double { indexes.map { response[$0] }.reduce(0, +) / Double(indexes.count) }

        // Correct most, not all, of each difference: rooms vary seat to seat, and gentle is safer.
        func setting(_ deviation: Double, scale: Double, range: ClosedRange<Double>) -> Double {
            min(range.upperBound, max(range.lowerBound, (-deviation * scale).rounded()))
        }
        let sub = Int(setting(average([0, 1]), scale: 0.7, range: -6...6))
        let bass = setting(average([2, 3]), scale: 0.7, range: -6...6)
        let mid = setting(average([4, 5, 6]), scale: 0.7, range: -6...6)
        let treble = setting(average([7, 8]), scale: 0.5, range: -6...4)
        return Result(bass: bass, mid: mid, treble: treble, sub: sub, response: response)
    }

    /// Pink noise (Paul Kellet's filter), stereo, at a comfortable level.
    static func pinkNoise(seconds: Double, sampleRate: Double) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * sampleRate)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = buffer.frameCapacity
        var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0
        var generator = SystemRandomNumberGenerator()
        for i in 0..<Int(buffer.frameLength) {
            let white = Double.random(in: -1...1, using: &generator)
            b0 = 0.99886 * b0 + white * 0.0555179
            b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520
            b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522
            b5 = -0.7616 * b5 - white * 0.0168980
            let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
            b6 = white * 0.115926
            let value = Float(pink * 0.08)
            channels[0][i] = value
            channels[1][i] = value
        }
        return buffer
    }

    // MARK: Is the sound going to the soundbar?

    static var outputIsWireless: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            [.airPlay, .bluetoothA2DP, .bluetoothLE].contains($0.portType)
        }
    }

    static var outputName: String? {
        AVAudioSession.sharedInstance().currentRoute.outputs.first {
            [.airPlay, .bluetoothA2DP, .bluetoothLE].contains($0.portType)
        }?.portName
    }
}

/// Plays the test sound and records what the microphone hears.
final class RoomListener: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let lock = NSLock()
    private var samples: [Float] = []
    private(set) var sampleRate: Double = 48_000

    static func requestMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Lets the test sound go to AirPlay or Bluetooth speakers while the microphone listens.
    static func prepareSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowAirPlay, .allowBluetoothA2DP])
        try session.setActive(true)
    }

    static func endSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        sampleRate = inputFormat.sampleRate
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let data = buffer.floatChannelData else { return }
            let count = Int(buffer.frameLength)
            let chunk = Array(UnsafeBufferPointer(start: data[0], count: count))
            self.lock.lock()
            self.samples.append(contentsOf: chunk)
            self.lock.unlock()
        }
        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let playRate = outputRate > 0 ? outputRate : 48_000
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: playRate, channels: 2))
        try engine.start()
    }

    func playNoise() {
        let rate = player.outputFormat(forBus: 0).sampleRate
        guard let noise = RoomTuning.pinkNoise(seconds: 6, sampleRate: rate > 0 ? rate : 48_000) else { return }
        player.scheduleBuffer(noise, at: nil, options: .loops)
        player.play()
    }

    func stopNoise() {
        player.stop()
    }

    /// Everything recorded since the last call.
    func take() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let result = samples
        samples.removeAll(keepingCapacity: true)
        return result
    }

    func stop() {
        player.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

/// Runs a whole room test and applies the result.
@MainActor
@Observable
final class RoomTuner {
    enum Phase: Equatable {
        case ready
        case listeningToRoom
        case playing(progress: Double)
        case done(RoomTuning.Result)
        case failed(String)
    }

    private(set) var phase: Phase = .ready
    private var before: SoundbarState?
    private var task: Task<Void, Never>?

    var isRunning: Bool {
        switch phase {
        case .listeningToRoom, .playing: true
        default: false
        }
    }

    func start() {
        task?.cancel()
        task = Task { await run() }
    }

    func cancel() {
        task?.cancel()
        task = nil
        restore()
        phase = .ready
    }

    private func run() async {
        let model = SoundbarModel.shared
        guard await RoomListener.requestMicrophone() else {
            phase = .failed(RoomTuning.TuneError.noMicrophone.localizedDescription)
            return
        }
        before = model.state
        let listener = RoomListener()
        do {
            try RoomListener.prepareSession()
            // Measure with nothing coloured: flat equaliser, subwoofer at 0, plain processing.
            model.set(.mode(.direct))
            model.set(.bass(0))
            model.set(.mid(0))
            model.set(.treble(0))
            if model.state.levels["sub"] != nil { model.set(.level("sub", 0)) }

            try listener.start()
            phase = .listeningToRoom
            try await Task.sleep(for: .seconds(2))
            let ambient = listener.take()

            listener.playNoise()
            // Wireless speakers lag a second or two behind; let the sound settle before measuring.
            let total = 12.0
            var elapsed = 0.0
            var recorded: [Float] = []
            while elapsed < total {
                try await Task.sleep(for: .milliseconds(250))
                elapsed += 0.25
                phase = .playing(progress: elapsed / total)
                let chunk = listener.take()
                if elapsed > 5 { recorded.append(contentsOf: chunk) }
            }
            listener.stop()
            RoomListener.endSession()

            let rate = listener.sampleRate
            let result = try RoomTuning.corrections(noise: RoomTuning.bandLevels(recorded, sampleRate: rate),
                                                   ambient: RoomTuning.bandLevels(ambient, sampleRate: rate))
            apply(result)
            phase = .done(result)
        } catch is CancellationError {
            listener.stop()
            RoomListener.endSession()
        } catch {
            listener.stop()
            RoomListener.endSession()
            restore()
            phase = .failed(error.localizedDescription)
        }
    }

    /// Puts back the user's sound mode and input, with the new equaliser and subwoofer level.
    private func apply(_ result: RoomTuning.Result) {
        let model = SoundbarModel.shared
        if let before {
            if let mode = before.soundMode { model.set(.mode(mode)) }
            if let input = before.soundInput, input.isSelectable { model.set(.input(input)) }
        }
        model.set(.bass(result.bass))
        model.set(.mid(result.mid))
        model.set(.treble(result.treble))
        if model.state.levels["sub"] != nil { model.set(.level("sub", result.sub)) }
    }

    /// Keeps the new settings.
    func keep() {
        before = nil
        phase = .ready
    }

    /// Goes back to exactly how it sounded before the test.
    func restore() {
        guard let before else { return }
        let model = SoundbarModel.shared
        if let mode = before.soundMode { model.set(.mode(mode)) }
        if let input = before.soundInput, input.isSelectable { model.set(.input(input)) }
        model.set(.bass(before.bass))
        model.set(.mid(before.mid))
        model.set(.treble(before.treble))
        if let sub = before.levels["sub"] { model.set(.level("sub", sub)) }
        self.before = nil
    }
}
