// backend/src/routes/placeRoutes.js
const express = require('express');
const router = express.Router();
const prisma = require('../../prisma/client');
const { requireAuth } = require('../middleware/auth');

// POST /api/places  (save a custom place)
router.post('/api/places', requireAuth, async (req, res) => {
  try {
    const userId = req.user?.userId;
    const { name, address, latitude, longitude } = req.body || {};
    if (!name || typeof latitude !== 'number' || typeof longitude !== 'number') {
      return res.status(400).json({ ok: false, error: 'INVALID_INPUT', details: 'name, latitude, longitude required' });
    }
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      return res.status(400).json({ ok: false, error: 'INVALID_COORDS' });
    }

    // idempotent-ish: unique by (name, lat, lng)
    const existing = await prisma.savedPlace.findFirst({
      where: { name, latitude, longitude },
    });
    if (existing) return res.json({ ok: true, data: existing });

    const saved = await prisma.savedPlace.create({
      data: {
        name,
        address: address || null,
        latitude,
        longitude,
        createdById: userId,
      },
    });

    return res.status(201).json({ ok: true, data: saved });
  } catch (err) {
    console.error('create place error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
});

// (Optional) GET /api/places?q=...  -> saved places only
router.get('/api/places', async (req, res) => {
  const q = String(req.query.q || '').trim();
  try {
    const rows = await prisma.savedPlace.findMany({
      where: q
        ? {
            OR: [
              { name: { contains: q, mode: 'insensitive' } },
              { address: { contains: q, mode: 'insensitive' } },
            ],
          }
        : {},
      orderBy: [{ createdAt: 'desc' }],
      take: 50,
    });
    res.json({ ok: true, data: rows });
  } catch (err) {
    console.error('list places error:', err);
    res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
});

module.exports = router;
