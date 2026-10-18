# Orchid

Flutter music player that uses **Eclipse addons** as sources.

- Add any Eclipse-compatible addon by URL
- Search across installed addons
- Play streams returned by `/stream/{id}`

UI is built with [shadcn_flutter](https://pub.dev/packages/shadcn_flutter) (no Material).

## Setup

```bash
git clone https://github.com/kawaiiepic/Orchid
cd Orchid
flutter create . --project-name orchid   # generates android/ios/web/… platforms
flutter pub get
flutter run
```

`flutter create .` is only needed once on a fresh clone so platform folders exist.

## Usage

1. Paste an addon base URL (or full `…/manifest.json`) → **Add**
2. Search for a song
3. Tap a result to play

Addons must implement the Eclipse protocol:

| Endpoint | Role |
|----------|------|
| `GET /manifest.json` | id, name, resources, … |
| `GET /search?q=` | `{ "tracks": [ … ] }` |
| `GET /stream/{id}` | `{ "url": "https://…" }` |

Docs: https://eclipsemusic.app/docs

## Stack

- Flutter + shadcn_flutter
- `http` for addon calls
- `just_audio` for playback
- `shared_preferences` for installed addons
- `cached_network_image` for artwork

## Not in v0.1

- Queue / next-previous
- Album & artist detail pages
- Background audio / lock-screen controls polish
- Addon settings passthrough

See `AGENTS.md` for extension notes.
