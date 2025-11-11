// backend/src/controllers/profileController.js
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

/**
 * Helper to get auth user id (dev-friendly)
 * If you already have proper auth middleware, replace this with req.user.id
 */
function getAuthUserId(req) {
  return req.user?.id || req.headers['x-user-id'] || null;
}

/**
 * GET /api/users/:userId/profile
 * Public profile summary
 */
async function getPublicProfile(req, res) {
  try {
    const { userId } = req.params;

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true, fullName: true, username: true, bio: true, profilePhotoUrl: true,
        homeLocation: true, isProfilePublic: true,
        outingScore: true, badges: true, createdAt: true,
      },
    });

    if (!user) return res.status(404).json({ ok: false, error: 'USER_NOT_FOUND' });
    if (!user.isProfilePublic) {
      return res.status(403).json({ ok: false, error: 'PROFILE_PRIVATE' });
    }

    // Basic stats
    const [hostedCount, rsvpsCount, favoritesCount] = await Promise.all([
      prisma.outing.count({ where: { createdById: userId } }),
      prisma.outingUser.count({ where: { userId } }),
      prisma.favorite.count({ where: { userId } }),
    ]);

    // Recent activity (last 5)
    const recentOutings = await prisma.outing.findMany({
      where: {
        OR: [{ createdById: userId }, { rsvps: { some: { userId } } }],
      },
      orderBy: { createdAt: 'desc' },
      take: 5,
      select: { id: true, title: true, createdAt: true, dateTimeStart: true, locationName: true },
    });

    return res.json({
      ok: true,
      data: {
        user,
        stats: { hostedCount, rsvpsCount, favoritesCount },
        recentOutings,
      },
    });
  } catch (err) {
    console.error('getPublicProfile error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
}

/**
 * PUT /api/users/me/profile
 * Update the authenticated user's profile
 */
async function updateMyProfile(req, res) {
  try {
    const me = getAuthUserId(req);
    if (!me) return res.status(401).json({ ok: false, error: 'AUTH_REQUIRED' });

    const {
      fullName, bio, homeLocation, isProfilePublic,
      preferredOutingTypes, profilePhotoUrl, badges,
    } = req.body || {};

    const updated = await prisma.user.update({
      where: { id: me },
      data: {
        ...(fullName !== undefined ? { fullName } : {}),
        ...(bio !== undefined ? { bio } : {}),
        ...(homeLocation !== undefined ? { homeLocation } : {}),
        ...(isProfilePublic !== undefined ? { isProfilePublic: !!isProfilePublic } : {}),
        ...(Array.isArray(preferredOutingTypes) ? { preferredOutingTypes } : {}),
        ...(profilePhotoUrl !== undefined ? { profilePhotoUrl } : {}),
        ...(Array.isArray(badges) ? { badges } : {}),
      },
      select: {
        id: true, fullName: true, username: true, bio: true, profilePhotoUrl: true,
        homeLocation: true, isProfilePublic: true, preferredOutingTypes: true,
        badges: true, outingScore: true,
      },
    });

    return res.json({ ok: true, data: updated });
  } catch (err) {
    console.error('updateMyProfile error:', err);
    if (err.code === 'P2002') {
      return res.status(409).json({ ok: false, error: 'CONFLICT' });
    }
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
}

module.exports = {
  getPublicProfile,
  updateMyProfile,
};
