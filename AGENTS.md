# AGENTS.md – Orchid

Flutter music player (shadcn_flutter). Third-party sources use the Eclipse addon protocol.

## Built-in

| Source | Role |
|--------|------|
| **iTunes Search API** | Always-on search + 30s preview fallback |
| **lrclib.net** | Lyrics after play (`/api/get`, then `/api/search`) |

These are not Eclipse addons; they do not need installing.

## External Eclipse addons

User pastes manifest URL. Used for extra search hits and full-length streams.

### Search merge
1. iTunes
2. Installed addons with `search`
3. Dedupe by ISRC or normalized title+artist (prefer stream-addon rows)

### Playback resolve
1. Stream from the result’s addon if it has `stream`
2. Else match on each stream addon via its `/search`
3. Else iTunes preview URL

Requires a normal `{ "url": "…" }` stream response (not client-resolved).

## Files

```
lib/services/addon_service.dart   # iTunes + addons + resolve + debug log
lib/services/lyrics_service.dart  # lrclib
lib/services/player_service.dart  # just_audio + lyrics fetch
lib/screens/home_screen.dart      # UI
```

## Notes

- lrclib asks for a descriptive User-Agent — set in LyricsService.
- Synced lyrics are shown stripped of timestamps for now (plain display).
