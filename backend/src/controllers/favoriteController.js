// backend/src/controllers/favoriteController.js
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

function getAuthUserId(req) {
  // Prefer auth middleware -> req.user.id. Fallbacks allow simple testing.
  return req.user?.id || req.headers['x-user-id'] || req.query.userId || null;
}

/**
 * POST /api/outings/:outingId/favorite
 * Body: (none)
 * Auth: user must be identified (req.user.id or x-user-id / ?userId for testing)
 * Response: 201 { ok, data: { id, userId, outingId, createdAt, outing: {...} } }
 */
async function favoriteOuting(req, res) {
  try {
    const me = getAuthUserId(req);
    if (!me) return res.status(401).json({ ok: false, error: 'AUTH_REQUIRED' });

    const { outingId } = req.params;

    // Ensure outing exists
    const outing = await prisma.outing.findUnique({
      where: { id: outingId },
      select: {
        id: true,
        title: true,
        outingType: true,
        locationName: true,
        address: true,
        dateTimeStart: true,
        dateTimeEnd: true,
      },
    });
    if (!outing) return res.status(404).json({ ok: false, error: 'OUTING_NOT_FOUND' });

    // Upsert to avoid duplicates
    const fav = await prisma.favorite.upsert({
      where: { userId_outingId: { userId: me, outingId } },
      update: {},
      create: { userId: me, outingId },
    });

    // Attach a lightweight outing snapshot in the response
    return res.status(201).json({
      ok: true,
      data: {
        ...fav,
        outing,
      },
    });
  } catch (err) {
    console.error('favoriteOuting error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
}

/**
 * DELETE /api/outings/:outingId/favorite
 * Response: 200 { ok: true, deleted: <number> }
 */
async function unfavoriteOuting(req, res) {
  try {
    const me = getAuthUserId(req);
    if (!me) return res.status(401).json({ ok: false, error: 'AUTH_REQUIRED' });

    const { outingId } = req.params;

    const result = await prisma.favorite.deleteMany({
      where: { userId: me, outingId },
    });

    return res.json({ ok: true, deleted: result.count });
  } catch (err) {
    console.error('unfavoriteOuting error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
}

/**
 * GET /api/users/me/favorites?limit=25&offset=0
 * Returns favorites with a compact outing snapshot + last image for UI cards.
 * Response: 200 { ok, meta: { total, limit, offset }, data: [ ... ] }
 */
async function listMyFavorites(req, res) {
  try {
    const me = getAuthUserId(req);
    if (!me) return res.status(401).json({ ok: false, error: 'AUTH_REQUIRED' });

    const limit = Math.min(parseInt(req.query.limit || '25', 10), 100);
    const offset = parseInt(req.query.offset || '0', 10);

    // Total for pagination
    const total = await prisma.favorite.count({ where: { userId: me } });

    // Pull favorites and include the outing (plus latest image if any)
    const items = await prisma.favorite.findMany({
      where: { userId: me },
      orderBy: { createdAt: 'desc' },
      skip: offset,
      take: limit,
      select: {
        id: true,
        userId: true,
        outingId: true,
        createdAt: true,
        outing: {
          select: {
            id: true,
            title: true,
            outingType: true,
            locationName: true,
            address: true,
            dateTimeStart: true,
            dateTimeEnd: true,
            images: {
              take: 1,
              orderBy: { id: 'desc' },
              select: { imageUrl: true, imageSource: true },
            },
          },
        },
      },
    });

    return res.json({
      ok: true,
      meta: { total, limit, offset },
      data: items.map((f) => ({
        id: f.id,
        userId: f.userId,
        outingId: f.outingId,
        createdAt: f.createdAt,
        outing: {
          ...f.outing,
          coverImageUrl: f.outing?.images?.[0]?.imageUrl || null,
          coverImageSource: f.outing?.images?.[0]?.imageSource || null,
        },
      })),
    });
  } catch (err) {
    console.error('listMyFavorites error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
}

module.exports = {
  favoriteOuting,
  unfavoriteOuting,
  listMyFavorites,
};
