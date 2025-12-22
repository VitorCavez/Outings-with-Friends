// backend/src/controllers/profileController.js
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

/**
 * Helper to decode the current user id.
 *
 * Priority:
 *   1) req.user.id / req.user.userId  (if some auth middleware already ran)
 *   2) JWT in Authorization: Bearer <token>  (decoded without verifying signature)
 *   3) x-user-id header (dev fallback)
 */
function getAuthUserId(req) {
  // 1) Upstream auth middleware (if any)
  if (req.user && (req.user.id || req.user.userId)) {
    return req.user.id || req.user.userId;
  }

  // 2) Decode JWT from Authorization header (no verify, just read payload)
  const authHeader = req.headers.authorization || req.headers.Authorization;
  if (typeof authHeader === 'string' && authHeader.startsWith('Bearer ')) {
    const token = authHeader.slice(7).trim();
    try {
      const parts = token.split('.');
      if (parts.length === 3) {
        const payloadJson = Buffer.from(parts[1], 'base64').toString('utf8');
        const payload = JSON.parse(payloadJson);

        return (
          payload.sub ||
          payload.userId ||
          payload.id ||
          null
        );
      }
    } catch (err) {
      console.warn('getAuthUserId JWT decode error:', err.message);
    }
  }

  // 3) Dev-style override header
  const xUserId = req.headers['x-user-id'];
  if (typeof xUserId === 'string' && xUserId.trim().length > 0) {
    return xUserId.trim();
  }

  return null;
}

/**
 * GET /api/users/:userId/profile
 * Public profile summary.
 *
 * Flutter expects:
 *   { ok: true, data: { user, stats, recentOutings } }
 * and UserProfile.fromJson uses `data.user`.
 */
async function getPublicProfile(req, res) {
  try {
    const { userId } = req.params;
    const me = getAuthUserId(req);
    const isMe = me && me === userId;

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        fullName: true,
        username: true,
        bio: true,
        profilePhotoUrl: true,
        homeLocation: true,
        isProfilePublic: true,
        outingScore: true,
        badges: true,
        createdAt: true,
      },
    });

    if (!user) {
      return res
        .status(404)
        .json({ ok: false, error: 'USER_NOT_FOUND' });
    }

    // Respect privacy, but allow the user to see their own profile
    if (!user.isProfilePublic && !isMe) {
      return res
        .status(403)
        .json({ ok: false, error: 'PROFILE_PRIVATE' });
    }

    // Basic stats
    const [hostedCount, rsvpsCount, favoritesCount] = await Promise.all([
      prisma.outing.count({ where: { createdById: userId } }),
      prisma.outingUser.count({ where: { userId } }),
      prisma.favorite.count({ where: { userId } }),
    ]);

    // Recent activity (last 5 outings user hosted or joined)
    const recentOutings = await prisma.outing.findMany({
      where: {
        OR: [
          { createdById: userId },
          { rsvps: { some: { userId } } },
        ],
      },
      orderBy: { createdAt: 'desc' },
      take: 5,
      select: {
        id: true,
        title: true,
        createdAt: true,
        dateTimeStart: true,
        locationName: true,
      },
    });

    return res.json({
      ok: true,
      data: {
        user: {
          id: user.id,
          fullName: user.fullName,
          username: user.username,
          bio: user.bio,
          profilePhotoUrl: user.profilePhotoUrl,
          homeLocation: user.homeLocation,
          isProfilePublic: user.isProfilePublic,
          outingScore: user.outingScore ?? 0,
          badges: user.badges || [],
        },
        stats: { hostedCount, rsvpsCount, favoritesCount },
        recentOutings,
      },
    });
  } catch (err) {
    console.error('getPublicProfile error:', err);
    return res
      .status(500)
      .json({ ok: false, error: 'SERVER_ERROR' });
  }
}

/**
 * PUT /api/users/me/profile
 * Update the authenticated user's profile.
 *
 * Used by the Flutter ProfileProvider → ProfileService.updateMyProfile().
 */
async function updateMyProfile(req, res) {
  try {
    const me = getAuthUserId(req);
    if (!me) {
      return res
        .status(401)
        .json({ ok: false, error: 'AUTH_REQUIRED' });
    }

    const {
      fullName,
      bio,
      homeLocation,
      isProfilePublic,
      preferredOutingTypes,
      profilePhotoUrl,
      badges,
    } = req.body || {};

    const updated = await prisma.user.update({
      where: { id: me },
      data: {
        ...(fullName !== undefined ? { fullName } : {}),
        ...(bio !== undefined ? { bio } : {}),
        ...(homeLocation !== undefined ? { homeLocation } : {}),
        ...(isProfilePublic !== undefined
          ? { isProfilePublic: !!isProfilePublic }
          : {}),
        ...(Array.isArray(preferredOutingTypes)
          ? { preferredOutingTypes }
          : {}),
        ...(profilePhotoUrl !== undefined ? { profilePhotoUrl } : {}),
        ...(Array.isArray(badges) ? { badges } : {}),
      },
      select: {
        id: true,
        fullName: true,
        username: true,
        bio: true,
        profilePhotoUrl: true,
        homeLocation: true,
        isProfilePublic: true,
        preferredOutingTypes: true,
        badges: true,
        outingScore: true,
      },
    });

    return res.json({ ok: true, data: updated });
  } catch (err) {
    console.error('updateMyProfile error:', err);
    if (err.code === 'P2002') {
      // e.g. unique constraint (username etc.)
      return res
        .status(409)
        .json({ ok: false, error: 'CONFLICT' });
    }
    return res
      .status(500)
      .json({ ok: false, error: 'SERVER_ERROR' });
  }
}

module.exports = {
  getAuthUserId,
  getPublicProfile,
  updateMyProfile,
};
