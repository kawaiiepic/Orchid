# Orchid

Eclipse Music addon that provides **search** and **stream** endpoints.

Right now it uses the public iTunes Search / Lookup APIs so you can search real songs and play the official 30-second previews immediately. Full-length playback needs a different source later.

## Endpoints

| Endpoint | Required | What it does |
|----------|----------|--------------|
| `GET /manifest.json` | Yes | Addon description |
| `GET /search?q={query}` | Yes | Search tracks / albums / artists |
| `GET /stream/{id}` | Yes | Returns a playable preview URL |

## Quick start (local)

```bash
npm install
npm start
# → http://localhost:3000
```

In Eclipse:

1. Settings → Connections → Add Connection → Addon
2. Paste `http://localhost:3000` (or your machine IP if testing on phone)
3. Install

The addon then shows up in the search dropdown.

## Deploy

Any HTTPS host works (Cloudflare Workers, Vercel, Railway, Fly, etc.). Point Eclipse at the public base URL.

## Notes

- Previews are AAC/M4A (~30 s). Eclipse plays them fine.
- Album / artist results are returned from search but detail endpoints (`/album/{id}`, `/artist/{id}`) are not implemented yet.
- No API keys required for the current iTunes backend.

See [Eclipse addon docs](https://eclipsemusic.app/docs) for the full protocol.
