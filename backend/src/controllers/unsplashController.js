// backend/src/controllers/unsplashController.js
// Uses Node 18+ global fetch. If you're on Node < 18, run: npm i node-fetch and: const fetch = (...args) => import('node-fetch').then(({default: f}) => f(...args));

const UNSPLASH_BASE = 'https://api.unsplash.com';
const { UNSPLASH_ACCESS_KEY } = process.env;

async function searchUnsplash(req, res) {
  try {
    if (!UNSPLASH_ACCESS_KEY) {
      return res.status(500).json({ ok: false, error: 'UNSPLASH_KEY_MISSING' });
    }

    const query = (req.query.query || '').toString().trim();
    const page = Number(req.query.page || 1);
    const per_page = Math.min(Number(req.query.per_page || 12), 30);

    if (!query) return res.status(400).json({ ok: false, error: 'QUERY_REQUIRED' });

    const url = new URL(`${UNSPLASH_BASE}/search/photos`);
    url.searchParams.set('query', query);
    url.searchParams.set('page', String(page));
    url.searchParams.set('per_page', String(per_page));
    url.searchParams.set('orientation', 'landscape');

    const resp = await fetch(url, {
      headers: {
        Authorization: `Client-ID ${UNSPLASH_ACCESS_KEY}`,
        'Accept-Version': 'v1',
      },
    });

    if (!resp.ok) {
      const text = await resp.text();
      console.error('Unsplash error:', resp.status, text);
      return res.status(resp.status).json({ ok: false, error: 'UNSPLASH_ERROR', details: text });
    }

    const data = await resp.json();

    // Map to the fields we actually use
    const results = (data.results || []).map((p) => ({
      id: p.id,
      description: p.description || p.alt_description || '',
      urls: p.urls,
      width: p.width,
      height: p.height,
      color: p.color,
      blur_hash: p.blur_hash,
      author: {
        name: p.user?.name,
        username: p.user?.username,
        profile_image: p.user?.profile_image,
      },
      links: {
        html: p.links?.html,
      },
      attribution: `Photo by ${p.user?.name} on Unsplash`,
    }));

    return res.json({
      ok: true,
      total: data.total,
      total_pages: data.total_pages,
      results,
    });
  } catch (err) {
    console.error('searchUnsplash error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
}

module.exports = { searchUnsplash };
