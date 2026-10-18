# Orchid

Simple music player that speaks the **Eclipse addon** protocol.

You install existing Eclipse-compatible addons by URL. Orchid searches them and plays whatever stream URLs they return.

## Features (v0.1)

- Add / remove Eclipse addons (fetches `/manifest.json`)
- Search across all installed addons that advertise `search`
- Play tracks via each addon’s `/stream/{id}`
- Local storage for installed addons (browser)
- Optional server-side proxy if an addon’s CORS is broken

## Run

```bash
npm install
npm start
# open http://localhost:3000
```

1. Paste an addon base URL (or full `…/manifest.json`) and hit **Add**
2. Search for a song
3. Click a result to play

## Eclipse addon contract (what Orchid expects)

| Endpoint | Purpose |
|----------|---------|
| `GET /manifest.json` | id, name, version, resources, … |
| `GET /search?q=` | `{ tracks: [...] }` (and optionally albums/artists) |
| `GET /stream/{id}` | `{ url: "https://…" }` direct audio URL |

Addons should send `Access-Control-Allow-Origin: *`. If they don’t, Orchid falls back to its `/proxy` route.

Docs: https://eclipsemusic.app/docs

## Not included yet

- Queue / next-up
- Album & artist detail pages
- Default-playback / ISRC matching
- Offline, playlists, lyrics
- Mobile install / PWA polish

See `AGENTS.md` for how to extend this.
