# AGENTS.md – Orchid

Orchid is a **music player client** for the Eclipse addon protocol, not an addon itself.

Protocol reference: https://eclipsemusic.app/docs

## Architecture (current)

- `server.js` – Express static server + optional CORS proxy at `GET /proxy?url=`
- `public/` – single-page UI
  - `index.html` / `styles.css` / `app.js`
- Installed addons stored in `localStorage` key `orchid_addons_v1` as:
  `{ baseUrl, manifest }[]`

### Addon lifecycle

1. User pastes URL → normalize (strip trailing slash / `manifest.json`)
2. Fetch `{base}/manifest.json` (direct, then proxy on failure)
3. Require at least `id` + `name`
4. Persist; dedupe by baseUrl or manifest.id

### Search

- Fan-out to every installed addon whose `resources` includes `"search"`
- Aggregate `tracks` arrays; each result is tagged with `_addonBase` and `_addonName`
- No ranking yet — order is whatever the promises resolve in

### Playback

- On click: `GET {base}/stream/{id}` → use returned `url` as `<audio>` src
- Direct audio formats only (MP3, AAC/M4A, FLAC, etc.) as required by Eclipse

## Rules for changes

1. Do not break the Eclipse response shapes when talking to addons.
2. Prefer keeping the UI dependency-free (vanilla JS) unless a real need appears.
3. Proxy exists only as fallback; prefer addons that set proper CORS.
4. Never store secrets in the repo. Addon URLs that embed tokens are the user’s problem and stay in localStorage only.

## Sensible next work

- Queue + play next / previous
- Filter search by selected addon
- Call `/album/{id}` and `/artist/{id}` when present
- Persist last search / now-playing lightly
- Better error surfaces (per-addon failures in the UI)
- PWA manifest + service worker if offline caching of the shell is wanted

## Files that matter

| Path | Role |
|------|------|
| `server.js` | HTTP + proxy |
| `public/app.js` | All client logic |
| `public/index.html` | Shell |
| `public/styles.css` | Layout |
