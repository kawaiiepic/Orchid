const STORAGE_KEY = 'orchid_addons_v1';

/** @typedef {{ baseUrl: string, manifest: object }} Addon */

function loadAddons() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

function saveAddons(addons) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(addons));
}

function normalizeBase(url) {
  let u = url.trim().replace(/\/+$/, '');
  if (u.endsWith('/manifest.json')) {
    u = u.slice(0, -'/manifest.json'.length);
  }
  return u;
}

async function fetchJson(url, useProxy = false) {
  const target = useProxy
    ? `/proxy?url=${encodeURIComponent(url)}`
    : url;
  const res = await fetch(target, { signal: AbortSignal.timeout(15000) });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

async function fetchManifest(baseUrl) {
  const base = normalizeBase(baseUrl);
  const manifestUrl = `${base}/manifest.json`;
  // try direct first, then proxy
  try {
    return { base, manifest: await fetchJson(manifestUrl, false) };
  } catch {
    return { base, manifest: await fetchJson(manifestUrl, true) };
  }
}

function renderAddons() {
  const list = document.getElementById('addon-list');
  const addons = loadAddons();
  list.innerHTML = '';
  if (!addons.length) {
    list.innerHTML = '<li class="muted">No addons yet. Add one above.</li>';
    return;
  }
  for (const a of addons) {
    const li = document.createElement('li');
    const resources = (a.manifest.resources || []).join(', ') || '—';
    li.innerHTML = `
      <div class="addon-meta">
        <strong>${escapeHtml(a.manifest.name || a.manifest.id || 'Addon')}</strong>
        <span>${escapeHtml(a.baseUrl)} · ${escapeHtml(resources)} · v${escapeHtml(a.manifest.version || '?')}</span>
      </div>
      <button type="button" class="danger" data-remove="${escapeAttr(a.baseUrl)}">Remove</button>
    `;
    list.appendChild(li);
  }
  list.querySelectorAll('[data-remove]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const next = loadAddons().filter((x) => x.baseUrl !== btn.dataset.remove);
      saveAddons(next);
      renderAddons();
    });
  });
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
function escapeAttr(s) {
  return escapeHtml(s).replace(/'/g, '&#39;');
}

document.getElementById('add-addon-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const input = document.getElementById('addon-url');
  const url = input.value.trim();
  if (!url) return;
  const btn = e.target.querySelector('button');
  btn.disabled = true;
  btn.textContent = '…';
  try {
    const { base, manifest } = await fetchManifest(url);
    if (!manifest.id || !manifest.name) {
      throw new Error('Invalid manifest (missing id/name)');
    }
    const addons = loadAddons();
    const existing = addons.findIndex((a) => a.baseUrl === base || a.manifest.id === manifest.id);
    const entry = { baseUrl: base, manifest };
    if (existing >= 0) addons[existing] = entry;
    else addons.push(entry);
    saveAddons(addons);
    input.value = '';
    renderAddons();
  } catch (err) {
    alert('Could not add addon: ' + (err.message || err));
  } finally {
    btn.disabled = false;
    btn.textContent = 'Add';
  }
});

document.getElementById('toggle-addons').addEventListener('click', () => {
  const body = document.getElementById('addons-body');
  const btn = document.getElementById('toggle-addons');
  const hidden = body.style.display === 'none';
  body.style.display = hidden ? '' : 'none';
  btn.textContent = hidden ? 'Hide' : 'Show';
});

// ─── Search ─────────────────────────────────────────────────────────────────

document.getElementById('search-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const q = document.getElementById('search-q').value.trim();
  const status = document.getElementById('search-status');
  const resultsEl = document.getElementById('results');
  resultsEl.innerHTML = '';
  if (!q) return;

  const addons = loadAddons().filter((a) =>
    (a.manifest.resources || []).includes('search')
  );
  if (!addons.length) {
    status.textContent = 'Add at least one search-capable addon first.';
    return;
  }

  status.textContent = `Searching ${addons.length} addon(s)…`;
  const allTracks = [];

  await Promise.all(
    addons.map(async (addon) => {
      const searchUrl = `${addon.baseUrl}/search?q=${encodeURIComponent(q)}`;
      try {
        let data;
        try {
          data = await fetchJson(searchUrl, false);
        } catch {
          data = await fetchJson(searchUrl, true);
        }
        const tracks = data.tracks || [];
        for (const t of tracks) {
          allTracks.push({
            ...t,
            _addonBase: addon.baseUrl,
            _addonName: addon.manifest.name || addon.manifest.id
          });
        }
      } catch (err) {
        console.warn('Search failed for', addon.baseUrl, err);
      }
    })
  );

  status.textContent = `${allTracks.length} track(s)`;
  if (!allTracks.length) {
    resultsEl.innerHTML = '<li class="muted">No results</li>';
    return;
  }

  for (const t of allTracks) {
    const li = document.createElement('li');
    const art = t.artworkURL
      ? `<img src="${escapeAttr(t.artworkURL)}" alt="" loading="lazy" />`
      : '<div style="width:44px;height:44px;background:var(--bg);border-radius:6px"></div>';
    li.innerHTML = `
      ${art}
      <div class="track-meta">
        <strong>${escapeHtml(t.title || 'Unknown')}</strong>
        <span>${escapeHtml(t.artist || '')}${t.album ? ' · ' + escapeHtml(t.album) : ''}</span>
        <div class="track-source">${escapeHtml(t._addonName)}</div>
      </div>
    `;
    li.addEventListener('click', () => playTrack(t));
    resultsEl.appendChild(li);
  }
});

// ─── Playback ───────────────────────────────────────────────────────────────

const audio = document.getElementById('audio');
const playerBar = document.getElementById('player-bar');
const btnPlay = document.getElementById('btn-play');
const seek = document.getElementById('seek');
const timeEl = document.getElementById('time');

async function playTrack(track) {
  const streamUrl = `${track._addonBase}/stream/${encodeURIComponent(track.id)}`;
  let data;
  try {
    try {
      data = await fetchJson(streamUrl, false);
    } catch {
      data = await fetchJson(streamUrl, true);
    }
  } catch (err) {
    alert('Could not get stream: ' + (err.message || err));
    return;
  }
  if (!data.url) {
    alert('Addon returned no stream URL');
    return;
  }

  document.getElementById('now-title').textContent = track.title || 'Unknown';
  document.getElementById('now-artist').textContent = track.artist || '';
  const art = document.getElementById('now-art');
  if (track.artworkURL) {
    art.src = track.artworkURL;
    art.hidden = false;
  } else {
    art.removeAttribute('src');
    art.hidden = true;
  }

  playerBar.hidden = false;
  audio.src = data.url;
  try {
    await audio.play();
    btnPlay.textContent = '⏸';
  } catch (err) {
    console.warn('Autoplay blocked or failed', err);
    btnPlay.textContent = '▶';
  }
}

btnPlay.addEventListener('click', () => {
  if (audio.paused) {
    audio.play();
    btnPlay.textContent = '⏸';
  } else {
    audio.pause();
    btnPlay.textContent = '▶';
  }
});

audio.addEventListener('timeupdate', () => {
  if (!audio.duration) return;
  seek.value = (audio.currentTime / audio.duration) * 100;
  timeEl.textContent = `${fmt(audio.currentTime)} / ${fmt(audio.duration)}`;
});

audio.addEventListener('ended', () => {
  btnPlay.textContent = '▶';
});

seek.addEventListener('input', () => {
  if (!audio.duration) return;
  audio.currentTime = (seek.value / 100) * audio.duration;
});

function fmt(sec) {
  if (!Number.isFinite(sec)) return '0:00';
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${String(s).padStart(2, '0')}`;
}

// init
renderAddons();
