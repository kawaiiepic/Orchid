const express = require('express');
const cors = require('cors');

const app = express();
app.use(cors());

const PORT = process.env.PORT || 3000;
const ITUNES_SEARCH = 'https://itunes.apple.com/search';

// ─── Manifest ───────────────────────────────────────────────────────────────
app.get('/manifest.json', (_req, res) => {
  res.json({
    id: 'com.kawaiiepic.orchid',
    name: 'Orchid',
    version: '1.0.0',
    description: 'Search and play songs via iTunes catalog (30s previews). Basic Eclipse Music addon.',
    resources: ['search', 'stream'],
    types: ['track', 'album', 'artist'],
    contentType: 'music'
  });
});

// ─── Search ─────────────────────────────────────────────────────────────────
app.get('/search', async (req, res) => {
  const q = (req.query.q || '').trim();
  if (!q) {
    return res.json({ tracks: [], albums: [], artists: [] });
  }

  try {
    const url = new URL(ITUNES_SEARCH);
    url.searchParams.set('term', q);
    url.searchParams.set('entity', 'song,album,musicArtist');
    url.searchParams.set('limit', '25');
    url.searchParams.set('media', 'music');

    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`iTunes responded ${response.status}`);
    }
    const data = await response.json();
    const results = data.results || [];

    const tracks = [];
    const albums = [];
    const artists = [];

    for (const item of results) {
      if (item.wrapperType === 'track' && item.kind === 'song') {
        tracks.push({
          id: String(item.trackId),
          title: item.trackName || 'Unknown',
          artist: item.artistName || 'Unknown',
          album: item.collectionName || undefined,
          duration: item.trackTimeMillis ? Math.round(item.trackTimeMillis / 1000) : undefined,
          artworkURL: (item.artworkUrl100 || '').replace('100x100bb', '600x600bb') || undefined,
          format: 'm4a'
        });
      } else if (item.wrapperType === 'collection' && item.collectionType === 'Album') {
        albums.push({
          id: String(item.collectionId),
          title: item.collectionName || 'Unknown',
          artist: item.artistName || 'Unknown',
          artworkURL: (item.artworkUrl100 || '').replace('100x100bb', '600x600bb') || undefined,
          trackCount: item.trackCount,
          year: item.releaseDate ? String(item.releaseDate).slice(0, 4) : undefined
        });
      } else if (item.wrapperType === 'artist') {
        artists.push({
          id: String(item.artistId),
          name: item.artistName || 'Unknown',
          artworkURL: undefined, // iTunes artist search rarely returns art here
          genres: item.primaryGenreName ? [item.primaryGenreName] : undefined
        });
      }
    }

    res.json({ tracks, albums, artists });
  } catch (err) {
    console.error('Search error:', err);
    res.status(500).json({ error: 'Search failed', tracks: [], albums: [], artists: [] });
  }
});

// ─── Stream ─────────────────────────────────────────────────────────────────
// Returns the iTunes 30-second preview URL so tracks are immediately playable.
// Full-length streams require a different backend source later.
app.get('/stream/:id', async (req, res) => {
  const id = req.params.id;

  try {
    // Lookup the track by id via iTunes lookup endpoint
    const lookupUrl = `https://itunes.apple.com/lookup?id=${encodeURIComponent(id)}&entity=song`;
    const response = await fetch(lookupUrl);
    if (!response.ok) {
      throw new Error(`iTunes lookup ${response.status}`);
    }
    const data = await response.json();
    const track = (data.results || []).find(r => r.wrapperType === 'track' && String(r.trackId) === id);

    if (!track || !track.previewUrl) {
      return res.status(404).json({ error: 'Track not found or no preview available' });
    }

    res.json({
      url: track.previewUrl,
      format: 'm4a',
      quality: 'preview',
      codec: 'aac',
      container: 'mp4',
      manifest: 'none'
    });
  } catch (err) {
    console.error('Stream error:', err);
    res.status(500).json({ error: 'Failed to resolve stream' });
  }
});

// Health / root
app.get('/', (_req, res) => {
  res.type('text').send('Orchid Eclipse addon is running. Install via GET /manifest.json');
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Orchid addon listening on http://0.0.0.0:${PORT}`);
  console.log(`Manifest: http://localhost:${PORT}/manifest.json`);
});
