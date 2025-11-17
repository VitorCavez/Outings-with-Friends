// backend/src/routes/discoverRoutes.js
const { Router } = require('express');
const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();
const router = Router();

/**
 * Shared handler for both:
 *   GET /discover
 *   GET /api/discover
 *
 * Query:
 *   lat, lng, radiusKm=10, types=CSV, limit<=50
 *
 * Response:
 *   { featured: [...], suggested: [...] }
 *
 * Notes on visibility:
 * - We read req.user?.id if some upstream auth middleware set it.
 * - If no user, we only return PUBLIC items.
 * - Later we can plug an optionalAuth middleware to populate req.user.
 */
async function handleDiscover(req, res) {
  const userId = req.user?.id || null; // populated if you run optional auth upstream

  // Parse & sanitize query
  const lat = Number.parseFloat(String(req.query.lat ?? '0'));
  const lng = Number.parseFloat(String(req.query.lng ?? '0'));
  const radiusKm = Number.isFinite(Number(req.query.radiusKm))
    ? Math.max(0, Number(req.query.radiusKm))
    : 10;
  const limit = Math.min(
    Number.isFinite(Number(req.query.limit)) ? Number(req.query.limit) : 20,
    50
  );

  const typesCsv = String(req.query.types ?? '').trim();
  const types = typesCsv
    ? typesCsv.split(',').map((s) => s.trim()).filter(Boolean)
    : [];

  // Quick bbox (≈111 km per degree). For accuracy, move to PostGIS later.
  const deg = radiusKm / 111.0;

  try {
    const whereBase = {
      isPublished: true,
      latitude: { gte: lat - deg, lte: lat + deg },
      longitude: { gte: lng - deg, lte: lng + deg },
      ...(types.length > 0 ? { outingType: { in: types } } : {}),
    };

    const visibilityOr = [
      { visibility: 'PUBLIC' },
      ...(userId
        ? [
            {
              AND: [
                { visibility: 'INVITED' },
                { participants: { some: { userId } } },
              ],
            },
            {
              AND: [
                { visibility: 'GROUPS' },
                { group: { members: { some: { userId } } } },
              ],
            },
            {
              AND: [
                { visibility: 'CONTACTS' },
                {
                  OR: [
                    // owner in my contacts
                    {
                      createdBy: {
                        inContactsOf: { some: { ownerUserId: userId } },
                      },
                    },
                    // I am in owner's contacts
                    {
                      createdBy: {
                        contactsOwned: {
                          some: { contactUserId: userId },
                        },
                      },
                    },
                  ],
                },
              ],
            },
          ]
        : [])
    ];

    const visible = await prisma.outing.findMany({
      where: { AND: [whereBase, { OR: visibilityOr }] },
      select: {
        id: true,
        title: true,
        address: true,
        outingType: true,
        latitude: true,
        longitude: true,
        createdAt: true,
        dateTimeStart: true,
      },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });

    const featured = visible.slice(0, Math.min(4, visible.length));
    const suggested = visible.slice(featured.length);

    const map = (x) => ({
      id: x.id,
      title: x.title,
      subtitle: x.address || '',
      type: x.outingType || 'Other',
      lat: x.latitude,
      lng: x.longitude,
      imageUrl: null, // UI has a fallback
    });

    return res.json({
      featured: featured.map(map),
      suggested: suggested.map(map),
    });
  } catch (e) {
    console.error('discover error:', e);
    return res
      .status(500)
      .json({ message: 'Failed to load discover', error: String(e?.message ?? e) });
  }
}

// Legacy public endpoint
router.get('/discover', handleDiscover);

// Preferred namespaced endpoint
router.get('/api/discover', handleDiscover);

module.exports = router;
