# Soundstage

Ian's iPhone app for his Klipsch Cinema 1200 soundbar (with its wireless subwoofer and surrounds). It talks to the soundbar directly over the home Wi-Fi: no Klipsch account, no internet.

- **Main screen:** power, volume (with mute), presets, sound mode (Movie, Music, Game, Standard, Direct, Party), input, night mode, dialogue boost, a three-band equaliser with quick picks, and separate levels for the subwoofer and each surround speaker.
- **Presets:** save the current sound (mode, equaliser, night/dialogue, speaker levels and optionally volume) and bring it back with one tap.
- **Widgets:** Soundbar (power, volume, modes, mute) and Presets on the Home Screen; power and status on the Lock Screen.
- **Control Centre:** power, mute, louder, quieter and a preset button.
- **Siri and Shortcuts:** on/off, volume, mute, sound mode, input, night mode, dialogue boost and presets.

## How it works

- The soundbar runs an undocumented, unauthenticated web service on port 80: `GET /api/getData?path=<setting>&roles=value` and `POST /api/setData` with `{"path", "roles", "value"}`. Values are typed (`i32_`, `bool_`, `double_`, `string_`, or named ones such as `cinemaPostProcessorMode`). Power uses `powermanager:targetRequest` with `roles: "activate"`. The setting names come from the open-source Home Assistant integration [nzlamb/ha-klipsch-cinema](https://github.com/nzlamb/ha-klipsch-cinema) (worked out from the Klipsch Connect app and the soundbar's firmware).
- Soundstage finds the soundbar by listening for its cast/AirPlay announcements, then falls back to asking every address on the Wi-Fi. An address can also be typed in.
- While open, the app refreshes every few seconds. Sliders send a few updates a second and always the final value; changes go out in order.
- Actions for widgets, Control Centre and Siri run in the app's own process (they're `LiveActivityIntent`s), which is where the Local Network permission lives. The set-up is shared with the widget extension through the keychain (like Nudge, Shelf, Murmur and Lumen), so no App Group is needed.
- Native SwiftUI, iOS 26+, iPhone only. The Xcode project is generated from `project.yml` with XcodeGen. The icon is drawn by `scripts/make_icon.py`.

## Workflows

1. **Set up with Apple**: `check` the secrets, create the `identifiers`, then `certificates`, then `testers`.
2. **Check build and screenshots**: runs on every push; builds for the simulator, runs an end-to-end check against a pretend Cinema 1200 (`scripts/fake_soundbar.py`) and saves screenshots to the `screenshots` branch.
3. **Build Soundstage**: builds and uploads to TestFlight. Runs on every push to `main`, monthly (so it never expires) and on demand. Uses the same Apple secrets and `Match-Secrets` certificate store as Ian's other apps.
