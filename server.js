const express = require('express');
const cors = require('cors');
const path = require('path');

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

const PORT = process.env.PORT || 3000;

// Optional proxy so browser can reach addons that are picky about CORS
app.get('/proxy', async (req, res) => {
  const target = req.query.url;
  if (!target || typeof target !== 'string') {
    return res.status(400).json({ error: 'Missing url query param' });
  }
  try {
    const u = new URL(target);
    if (!['http:', 'https:'].includes(u.protocol)) {
      return res.status(400).json({ error: 'Only http/https allowed' });
    }
    const upstream = await fetch(target, {
      headers: { Accept: 'application/json' },
      signal: AbortSignal.timeout(12000)
    });
    const text = await upstream.text();
    res.status(upstream.status);
    res.set('Content-Type', upstream.headers.get('content-type') || 'application/json');
    res.send(text);
  } catch (err) {
    console.error('Proxy error:', err.message);
    res.status(502).json({ error: 'Proxy failed', detail: err.message });
  }
});

app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Orchid player → http://localhost:${PORT}`);
});
