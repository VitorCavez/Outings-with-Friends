// backend/src/routes/geoRoutes.js
const express = require('express');
const router = express.Router();
const prisma = require('../../prisma/client');

async function searchOSM(q, limit = 6) {
  if (!q || q.trim().length < 2) return [];
  const url = `https://nominatim.openstreetmap.org/search?format=jsonv2&q=${encodeURIComponent(q)}&limit=${limit}`;
  const resp = await fetch(url, {
    headers: {
      'User-Agent': 'OutingsWithFriends/1.0 (contact: support@example.com)',
      'Accept': 'application/json',
    },
  });
  if (!resp.ok) return [];
  const rows = await resp.json();
  return (rows || []).map((r) => ({
    source: 'osm',
    id: String(r.place_id),
    name: r.display_name?.split(',')[0]?.trim() || r.display_name || 'Unknown',
    address: r.display_name || null,
    latitude: parseFloat(r.lat),
    longitude: parseFloat(r.lon),
  })).filter(p => Number.isFinite(p.latitude) && Number.isFinite(p.longitude));
}

// GET /api/geo/search?q=term
router.get('/api/geo/search', async (req, res) => {
  const q = String(req.query.q || '').trim();
  if (!q) return res.json({ ok: true, data: [] });

  try {
    // saved places first
    const saved = await prisma.savedPlace.findMany({
      where: {
        OR: [
          { name: { contains: q, mode: 'insensitive' } },
          { address: { contains: q, mode: 'insensitive' } },
        ],
      },
      orderBy: [{ createdAt: 'desc' }],
      take: 10,
    });

    const savedMapped = saved.map((s) => ({
      source: 'saved',
      id: s.id,
      name: s.name,
      address: s.address,
      latitude: s.latitude,
      longitude: s.longitude,
      isVerified: s.isVerified,
    }));

    // external search (OSM)
    const external = await searchOSM(q, 6);

    // de-duplicate by (name + lat/lng)
    const key = (p) => `${p.name.toLowerCase()}_${p.latitude.toFixed(6)}_${p.longitude.toFixed(6)}`;
    const map = new Map();
    for (const p of [...savedMapped, ...external]) {
      const k = key(p);
      if (!map.has(k)) map.set(k, p);
    }

    return res.json({ ok: true, data: Array.from(map.values()) });
  } catch (err) {
    console.error('geo search error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
});

module.exports = router;
