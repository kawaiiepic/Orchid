# Miniaudio migration (experimental)

This branch replaces `just_audio` with `miniaudio_player ^3.0.2` for music playback. It uses **MiniaudioEngine<String>**, the dual-deck crossfade API, via `OrchidAudioPlayer`, which preserves the small transport interface already consumed by Orchid's lyrics, mini-player, and `audio_service` lock-screen integration.

## Features

- Cross-platform 10-band ISO 266 EQ with presets and individually persisted Custom bands.
- Crossfade duration 0–12 seconds (default 0) with the miniaudio equal-power mixer and a short manual skip fade.
- Per-track loudness normalization toggle using the native engine's ReplayGain handling.
- System audio output enumeration and selection where native routing permits it. The iOS AirPlay picker remains separate and unchanged.
- Lazy next-song pre-resolution via Orchid's existing Eclipse addon resolver, then insertion into the standby deck for track-to-track crossfades.
- Preserves Orchid's account history and Petal listening tracking through the PlayerService event layer.

## Important limitations

**Do not merge until platform testing is complete.** `miniaudio_player` is a new package with native components, and the local coding environment did not have Flutter/Dart installed to run an analyzer or native build.

The next-track URL must be resolved before the fade window; short URLs, slow addons, and network failures can still fall back to a normal cut. Suggested radio/Keep Playing tracks that are discovered at the end of the queue may not overlap without advance resolution.

Orchid currently updates original queue state separately from the native mixer queue. Validate queue edits, shuffle, manually skipping, repeat-one, and Jam transitions carefully. On iOS, verify `AVAudioSession`, Control Center, wired/Bluetooth/headset commands and AirPlay on an actual device.

The existing video playback uses media_kit and stays unchanged. Chromecast discovery is not included.

## iOS native build fix (miniaudio_player 3.0.2)

The published miniaudio_player 3.0.2 Cargo build script passes its iOS
`miniaudio_device_bridge.c` to the C compiler unchanged. Upstream miniaudio
requires Objective-C for iOS; otherwise clang reports invalid Foundation
declarations (`NSObjCRuntime.h`, `NSString`). Orchid carries a narrowly
version-checked, idempotent hotfix in
`scripts/patch_miniaudio_ios.py` until the package is fixed upstream.

Use Orchid's wrapper for a local unsigned iOS release build:

```sh
bash scripts/build_ios.sh --release --no-codesign
```

The wrapper runs `flutter pub get`, applies the patch and invokes
`flutter build ios`. If invoking Flutter directly, run
`python3 scripts/patch_miniaudio_ios.py` after `flutter pub get` first.

The script patches only the resolved package's `rust/build.rs` (not Apple's
SDK), passing `-x objective-c` to the `cc` builder on iOS and linking
Foundation. CI and TestFlight run it automatically. Re-run it after
`flutter pub cache repair`, updating the package version, or clearing
Flutter dependencies. Because it patches a dependency cache, this is a
temporary workaround rather than an upstream fix; remove it once a newer
package release fixes the native build.

## Local verification

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d linux
# also build/test iOS, Android, Windows and macOS
```

Verify:

1. Start iTunes previews and Eclipse addon streams; seek, pause, resume and skip.
2. Test MP3/FLAC/AAC/HLS sources and expiry of signed URLs.
3. Start playback, lock the phone, pause/skip from Control Center, use Bluetooth headphones.
4. Select EQ presets and individually adjust each of ten bands. Restart to verify persistence.
5. Test 0, 3 and 12 second crossfades on a multi-track playlist.
6. Change the next track mid-song; confirm the standby deck is replaced.
7. Validate auto-next, manually skipping, repeat-one, shuffle, Radio and Keep Playing.
8. Check karaoke lyric timestamp accuracy during crossfade.
9. Test Orchid Connect transfers and Jam guests on miniaudio.
10. Test switching output devices on desktop and AirPlay on iOS.
