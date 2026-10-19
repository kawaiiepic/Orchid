# AGENTS.md – Orchid

Flutter music player (shadcn_flutter). Third-party sources use the Eclipse addon protocol.

## Built-in

| Source | Role |
|--------|------|
| **iTunes Search API** | Primary search + 30s preview fallback |
| **Spotify Web API** | Secondary search fallback (when iTunes fails) |
| **Spicy Lyrics** | Lyrics after play (Apple Music syllable sync via Spotify track ID) |

These are not Eclipse addons; they do not need installing.

## External Eclipse addons

User pastes manifest URL. Used for extra search hits and full-length streams.

### Search merge
1. iTunes
2. Installed addons with `search`
3. Dedupe by ISRC or normalized title+artist (prefer stream-addon rows)

### Playback resolve
1. Stream from the result's addon if it has `stream`
2. Else match on each stream addon via its `/search`
3. Else iTunes preview URL

Requires a normal `{ "url": "…" }` stream response (not client-resolved).

## Files

```
lib/services/addon_service.dart   # iTunes + addons + resolve + debug log
lib/services/lyrics_service.dart  # Spicy Lyrics API (Spotify track ID required)
lib/services/spotify_service.dart # Spotify Web API client
lib/services/player_service.dart  # just_audio + lyrics fetch
lib/screens/home_screen.dart      # UI
```

## Notes

- **Spicy Lyrics** returns Apple Music syllable-level sync (karaoke timing).
- **Requires Spotify track IDs**: Songs must be resolved to Spotify URLs first.
- Zero auth, CORS-enabled — works from any Flutter client.
- Lookup method: `GET /v1/lyrics/{SPOTIFY_TRACK_ID}` with Bearer token auth

### Resolution Strategy (Multi-Provider)

Orchid now supports multiple resolution methods in the following order:

1. **Direct Spotify Track ID** - If available from stream addon or iTunes response
2. **iTunes Search Resolution** - Search iTunes for title+artist, extract Spotify URL if present
3. **Spotify Search Fallback** - Search Spotify Web API for title+artist, use result's track ID

This multi-provider approach ensures lyrics load even when individual services have gaps.

### How Spicy Lyrics Works

Spicy Lyrics uses Spotify's track ID (22 base62 characters) as its unique identifier. To use it:

1. **Resolve songs to Spotify URLs** - iTunes API or addon searches can provide Spotify URLs
2. **Extract track ID from Spotify URL** - e.g., `https://open.spotify.com/track/7MXVkk9dbS6I95tUf04r1a` → `7MXVkk9dbS6I95tUf04r1a`
3. **Query Spicy Lyrics API** - Use the extracted ID with Bearer token authentication

### Adding Spotify Track ID Support

To enable lyrics loading automatically, add `spotifyTrackId` field to your song search results:

```dart
// In addon search responses, extract Spotify track ID:
Map<String, dynamic> addonResult = {...};
String? spotifyTrackId;

if (addonResult.containsKey('url')) {
  final url = addonResult['url'] as String? ?? '';
  if (url.contains('open.spotify.com/track/')) {
    // Extract the track ID from URL
    final id = url.split('/track/').last.split('?')[0];
    spotifyTrackId = id;
  }
}

// Then create TrackResult with the Spotify ID:
final track = TrackResult(
  title: result['title'],
  artist: result['artist'],
  previewUrl: result['previewURL'],
  spotifyTrackId: spotifyTrackId,  // <-- Add this!
);
```

## Spicy Lyrics Usage Examples

```dart
/// WORKING API CALL:
/// GET /v1/lyrics/{SPOTIFY_TRACK_ID} with Bearer token auth

final trackId = '7MXVkk9dbS6I95tUf04r1a';  // From Spotify URL
final url = Uri.parse('https://api.spicylyrics.org/v1/lyrics/$trackId');
final headers = {
  'Authorization': 'Bearer sl_sk_169LGcgCR0Jd02kORnaebr1XxJm59eIjb5NpDJ7zgKM',
};

/// Usage in your app:
// Requires spotifyTrackId field in TrackResult model
final lyrics = await LyricsService().fetchFor(track);

/// Response structure:
/// {
///   "Body": {
///     "plain": "...",           // Plain text lyrics
///     "sync": [...],             // Sync timestamps for karaoke
///     "source": "apple_music"    // Which provider provided the lyrics
///   },
///   "Status": 200,
///   "Type": "object"
/// }
```

API Base: `https://api.spicylyrics.org/v1/lyrics/{SPOTIFY_TRACK_ID}`  
Auth Header: `Authorization: Bearer sl_sk_169LGcgCR0Jd02kORnaebr1XxJm59eIjb5NpDJ7zgKM`

## Development Environment
- **Flutter SDK**: `/home/mia/Documents/sdk/flutter` (use this path for build/analyze commands)

## Project Architecture

The Orchid music player is built using Flutter with a modular architecture that:

1. **Core Services**:
   - `AddonService`: Manages Eclipse addons and handles search/resolve logic
   - `LyricsService`: Fetches lyrics using Spicy Lyrics API
   - `SpotifyService`: Handles Spotify Web API interactions
   - `PlayerService`: Manages audio playback with just_audio

2. **UI Components**:
   - `HomeScreen`: Main interface for searching and playing music
   - `ShellScreen`: Navigation between search and settings screens
   - Various widgets for player controls, lyrics display, and UI elements

3. **Eclipse Addon Protocol**:
   - Supports both `search` and `stream` capabilities in addons
   - Implements a multi-layered resolution strategy
   - Provides fallback mechanisms for when primary sources fail

The project follows a clean architecture pattern with clear separation of concerns between UI, business logic, and data access layers.