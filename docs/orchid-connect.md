# Orchid Connect

The fullscreen player already has an audio route sheet. Orchid Connect extends it with authenticated device presence, playback handoff and a minimal host-controlled Jam.

## Backend rollout

The shared Petal backend repository contains migration `0029_orchid_connect.sql` and routes mounted at `/orchid/connect`. **Apply the migration and deploy the Worker before shipping this Flutter change.** Until then, the Connect sheet reports that the service is unavailable, and local playback and the existing iOS AirPlay picker remain usable.

Follow the backend's deployment process (`npm run deploy` from the backend checkout) to apply migrations and deploy with the maintenance guard. Do not run this against production without backing up D1.

## Device transfer

A client registers one persistent random device ID in local preferences. Every five seconds, while signed in and the application shell is running, it publishes its playback state. The server lists only the same account's devices seen within 90 seconds. Selecting a device sends a bounded playback snapshot to its command inbox. The destination resolves and plays the music itself, seeks to the transferred position, and acknowledges the transfer so the source pauses. Devices must be open and connected; this does not remotely launch a closed app.

## Jams

The host creates a 12-character code. Other signed-in users can join by entering that code. The host publishes position/track/playing state on the normal polling interval; guests mirror the playback. The invite code is copied from the expanded Jam section. Host-controlled playback only, with approximately 5-second synchronization granularity. This is not a sample-accurate party player, and sharing song metadata does not grant guests access to streaming addons they haven't configured.

## Platform outputs and Audio Pipeline

iOS uses the existing native `AVRoutePickerView` for AirPlay/Bluetooth. Android opens native Bluetooth settings, and other platforms may not expose an audio-output selector yet. Network Chromecast/DLNA rendering is **not implemented**; the UI says so. The existing Audio Pipeline is a local control panel for volume, shuffle, repeat and source, not yet a DSP equalizer or crossfade engine.

## Validation checklist

- Deploy the backend first, launch two devices signed into the same account and confirm both appear.
- Transfer a track to the second device, verify queue/position, and verify the first pauses when the destination acknowledges.
- Start a Jam on one account and join with a different account/code.
- Pause/seek/skip on the host and check that the guest catches up on the next poll.
- Leave the Jam, then confirm local playback still works.
- Verify AirPlay routing on a physical iOS device.
- Run `flutter analyze` and platform builds locally before release.
