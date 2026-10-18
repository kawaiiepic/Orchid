# AGENTS.md – Orchid (Eclipse Music Addon)

This file is for future AI agents / collaborators working on the repo.

## What this project is

Orchid is an **Eclipse Music addon**. Eclipse is a music player app; addons are plain HTTP servers that supply search results and streamable audio URLs. Eclipse handles UI, queue, playback engine, lyrics, etc.

Official protocol docs: https://eclipsemusic.app/docs

### Required endpoints (must keep working)

- `GET /manifest.json` – static description of the addon
- `GET /search?q={query}` – returns `{ tracks, albums, artists, playlists }` (arrays optional)
- `GET /stream/{id}` – returns `{ url, format?, quality?, ... }` with a direct audio URL

Optional later: `/album/{id}`, `/artist/{id}`, `/playlist/{id}`, `/resolve-isrc`, settings, catalogs.

### Current implementation (v1.0.0)

- Node.js + Express + CORS
- Search + stream backed by Apple’s public iTunes Search / Lookup APIs (no key)
- Streams are **30-second previews** only (AAC/M4A). Enough for basic “search and play” demo.
- Track IDs are iTunes `trackId` strings.

## Design constraints for future changes

1. Keep the three required endpoints stable. Eclipse clients cache the manifest and expect the same response shapes.
2. Stream URLs must be direct audio (MP3 / AAC / M4A / FLAC / WAV / OGG). No HTML pages or login redirects.
3. Prefer adding a real full-track source (own catalog, licensed API, self-hosted files, etc.) rather than extending the preview path forever.
4. If you add settings, declare them in the manifest under `settings` and read the corresponding query params on every request.
5. CORS is already enabled; keep it for local + remote clients.

## Useful files

- `index.js` – the whole server right now
- `package.json` – deps and start script
- `README.md` – human install / run instructions

## Suggested next steps (in priority order)

- [ ] Real full-length streams (replace or supplement iTunes previews)
- [ ] Implement `GET /album/{id}` and `GET /artist/{id}` so browsing works without Apple Music fallback
- [ ] Optional ISRC support (`resources` + `/resolve-isrc`) for better matching when used as default playback source
- [ ] Deploy instructions / Dockerfile / Cloudflare Worker port if desired
- [ ] Basic tests that hit the three endpoints with a known query

## Style / conventions

- Keep the server small and readable.
- Log errors to stderr; return JSON error objects with appropriate HTTP status.
- Do not commit secrets. Current backend needs none.
