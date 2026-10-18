# AGENTS.md – Orchid

Flutter music player. UI: shadcn_flutter. Protocol for third-party sources: Eclipse addons (https://eclipsemusic.app/docs).

## Search

1. Always query **iTunes Search API** (no key).
2. Also query every installed addon with `resources` containing `"search"`.
3. **Dedupe** by ISRC if present, else normalized `title|artist`.
4. Prefer stream-capable addon hits over iTunes when collapsing duplicates.

## Playback

`AddonService.resolvePlayback(track, addons)`:

1. If the result came from a stream addon → `GET {base}/stream/{id}` (must return direct `{ url }`).
2. Else try each installed stream addon: search `artist title`, score match (ISRC / title / artist / duration), then `/stream/{id}`.
3. Else use iTunes `previewUrl` (30s) if present.

Client-resolved stream payloads (e.g. official YTM) are rejected — need a real audio URL.

## Layout

```
lib/
  main.dart / app.dart
  models/addon.dart
  services/addon_service.dart   # install, iTunes+addon search, dedupe, resolvePlayback
  services/player_service.dart  # just_audio
  screens/home_screen.dart
```

## Rules

- Stay on shadcn_flutter; no Material unless required.
- Soft-fail per addon on search.
- No secrets in repo.
