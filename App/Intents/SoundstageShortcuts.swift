import AppIntents

struct SoundstageShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ApplyPresetIntent(),
            phrases: [
                "Use \(\.$preset) in \(.applicationName)",
                "\(.applicationName) \(\.$preset)",
                "Use a preset in \(.applicationName)"
            ],
            shortTitle: "Use Preset",
            systemImageName: "slider.horizontal.3"
        )
        AppShortcut(
            intent: SetModeIntent(),
            phrases: [
                "Switch to \(\.$mode) mode in \(.applicationName)",
                "\(.applicationName) \(\.$mode) mode",
                "Change sound mode in \(.applicationName)"
            ],
            shortTitle: "Sound Mode",
            systemImageName: "film"
        )
        AppShortcut(
            intent: TurnOnIntent(),
            phrases: [
                "Turn on \(.applicationName)",
                "Turn on the soundbar with \(.applicationName)"
            ],
            shortTitle: "Turn On",
            systemImageName: "power"
        )
        AppShortcut(
            intent: TurnOffIntent(),
            phrases: [
                "Turn off \(.applicationName)",
                "Turn off the soundbar with \(.applicationName)"
            ],
            shortTitle: "Turn Off",
            systemImageName: "power"
        )
        AppShortcut(
            intent: VolumeUpIntent(),
            phrases: [
                "Turn it up with \(.applicationName)",
                "\(.applicationName) louder"
            ],
            shortTitle: "Volume Up",
            systemImageName: "speaker.plus"
        )
        AppShortcut(
            intent: VolumeDownIntent(),
            phrases: [
                "Turn it down with \(.applicationName)",
                "\(.applicationName) quieter"
            ],
            shortTitle: "Volume Down",
            systemImageName: "speaker.minus"
        )
        AppShortcut(
            intent: SetVolumeIntent(),
            phrases: [
                "Set the volume with \(.applicationName)",
                "Change volume in \(.applicationName)"
            ],
            shortTitle: "Set Volume",
            systemImageName: "speaker.wave.2"
        )
        AppShortcut(
            intent: MuteIntent(),
            phrases: [
                "Mute \(.applicationName)",
                "Mute the soundbar with \(.applicationName)"
            ],
            shortTitle: "Mute",
            systemImageName: "speaker.slash"
        )
        AppShortcut(
            intent: SetNightModeIntent(),
            phrases: [
                "Night mode in \(.applicationName)",
                "Turn on night mode with \(.applicationName)"
            ],
            shortTitle: "Night Mode",
            systemImageName: "moon"
        )
        AppShortcut(
            intent: SetInputIntent(),
            phrases: [
                "Switch to \(\.$input) in \(.applicationName)",
                "Change input in \(.applicationName)"
            ],
            shortTitle: "Input",
            systemImageName: "tv"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .orange
}
