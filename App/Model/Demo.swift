import Foundation

/// A pretend soundbar for screenshots, and an automatic check against a pretend soundbar
/// (used by the build checks).
enum Demo {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }
    static var isDemo: Bool { arguments.contains { $0.hasPrefix("-SoundstageDemo") } }

    /// Runs before anything loads, so the app starts with the pretend soundbar.
    @MainActor
    static func prepareIfRequested() {
        guard isDemo else { return }
        SoundbarLink.offline = true
        var setup = arguments.contains("-SoundstageDemoWelcome") ? SavedSetup() : sample()
        if arguments.contains("-SoundstageDemoOff") { setup.state.power = false }
        Store.demo = setup
        let connection: SoundbarModel.Connection = arguments.contains("-SoundstageDemoUnreachable") ? .unreachable : .connected
        SoundbarModel.shared.replace(with: setup, connection: connection)
    }

    @MainActor
    static func runIfRequested() async {
        if arguments.contains("-SoundstageSelfTest") {
            await SelfTest.run()
            return
        }
        guard isDemo else { return }
        try? await Task.sleep(for: .milliseconds(300))
        let router = Router.shared
        if arguments.contains("-SoundstageDemoSettings") { router.sheet = .settings }
        if arguments.contains("-SoundstageDemoPreset") { router.sheet = .newPreset }
        if arguments.contains("-SoundstageDemoEQ") { router.scrollTarget = "eq" }
        if arguments.contains("-SoundstageDemoSpeakers") { router.scrollTarget = "speakers" }
    }

    static func sample() -> SavedSetup {
        var setup = SavedSetup()
        setup.soundbar = SoundbarInfo(host: "192.168.1.42", name: "Living Room", model: "Klipsch Cinema 1200",
                                      serial: "KC1200-0042", firmware: "2.6.1")
        setup.state = SoundbarState(power: true, volume: 32, muted: false, input: "hdmiarc", mode: "movie",
                                    night: "nightMode_0", dialogue: "dialog_1", display: "dim",
                                    bass: 2, mid: 0, treble: 1,
                                    levels: ["sub": 2, "surr_L": 0, "surr_R": 0], updated: .now)
        return setup
    }
}

/// Runs every control against the pretend soundbar (scripts/fake_soundbar.py) and writes the
/// results to Documents/selftest.json for the build check to read.
@MainActor
enum SelfTest {
    static func run() async {
        var log: [String] = []
        var passed = true
        func check(_ name: String, _ ok: Bool) {
            log.append("\(ok ? "PASS" : "FAIL") \(name)")
            if !ok { passed = false }
        }

        let model = SoundbarModel.shared
        model.forgetSoundbar()

        // 1. Finding it, without being told where it is.
        let found = await Discovery.find()
        check("found the soundbar on the network (\(found.map(\.host).joined(separator: ", ")))", !found.isEmpty)
        let soundbar = found.first { $0.model.contains("Cinema") } ?? found.first
        if let soundbar {
            check("it reports its name and model (\(soundbar.name), \(soundbar.model))", soundbar.name == "Living Room" && soundbar.model.contains("Cinema 1200"))
            await model.choose(soundbar)
        } else if await model.tryAddress("127.0.0.1") {
            log.append("NOTE fell back to the address typed in by hand")
        }
        check("connected", model.connection == .connected)

        // 2. Every control, through the same path Siri, widgets and Control Centre use.
        let steps: [(String, [SoundbarChange])] = [
            ("power on", [.power(true)]),
            ("volume", [.volume(37)]),
            ("mute", [.muted(true)]),
            ("unmute", [.muted(false)]),
            ("input", [.input(.hdmi1)]),
            ("sound mode", [.mode(.music)]),
            ("night mode", [.night(.high)]),
            ("dialogue", [.dialogue(.medium)]),
            ("equaliser", [.bass(3), .mid(-2), .treble(1)]),
            ("speaker levels", [.level("sub", 4), .level("surr_L", -1), .level("surr_R", 2)]),
            ("display", [.display(.dim)])
        ]
        for (name, changes) in steps {
            do {
                try await SoundbarControl.perform(changes, wakeIfNeeded: false)
                check("sent \(name)", true)
            } catch {
                check("sent \(name): \(error.localizedDescription)", false)
            }
        }

        // 3. Read everything back from the soundbar itself.
        do {
            let state = try await SoundbarControl.refresh()
            check("power is on", state.power)
            check("volume is 37 (\(state.volume))", state.volume == 37)
            check("not muted", !state.muted)
            check("input is HDMI 1 (\(state.input))", state.input == "hdmi1")
            check("mode is Music (\(state.mode))", state.mode == "music")
            check("night mode is high (\(state.night))", state.nightLevel == .high)
            check("dialogue is medium (\(state.dialogue))", state.dialogueLevel == .medium)
            check("equaliser is +3 / -2 / +1 (\(state.bass) / \(state.mid) / \(state.treble))", state.bass == 3 && state.mid == -2 && state.treble == 1)
            check("speaker levels (\(state.levels))", state.levels["sub"] == 4 && state.levels["surr_L"] == -1 && state.levels["surr_R"] == 2)
            check("display is dim (\(state.display))", state.displayLevel == .dim)
        } catch {
            check("read back: \(error.localizedDescription)", false)
        }

        // 4. Volume buttons, a preset, and the power switch.
        do {
            let up = try await SoundbarControl.nudgeVolume(up: true, by: 4)
            check("volume up (\(up.volume))", up.volume == 41)
            let late = Preset.defaults[1]
            try await SoundbarControl.apply(late)
            let state = try await SoundbarControl.refresh()
            check("Late night preset (\(state.mode), \(state.night), sub \(state.levels["sub"] ?? 99))",
                  state.mode == "movie" && state.nightLevel == .high && state.levels["sub"] == -3)
            try await SoundbarControl.togglePower()
            let off = try await SoundbarControl.refresh()
            check("power off", !off.power)
            // Changing the mode while off wakes it first.
            try await SoundbarControl.perform(.mode(.game))
            let woken = try await SoundbarControl.refresh()
            check("waking for a mode change", woken.power && woken.mode == "game")
        } catch {
            check("buttons and presets: \(error.localizedDescription)", false)
        }

        // 5. The app's own controls (sliders) reach the soundbar.
        model.set(.volume(20), smooth: true)
        model.set(.volume(22), smooth: true)
        model.set(.volume(25), smooth: true)
        try? await Task.sleep(for: .seconds(1.5))
        let final = try? await SoundbarControl.refresh()
        check("slider ends on the last value (\(final?.volume ?? -1))", final?.volume == 25)

        let result: [String: Any] = ["result": passed ? "all passed" : "failed", "log": log]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
           let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("selftest.json") {
            try? data.write(to: url)
        }
    }
}
