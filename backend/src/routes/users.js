// backend/src/routes/users.js
const express = require('express');
const router = express.Router();
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

// Use the shared helpers/controller logic
const {
  getPublicProfile,
  updateMyProfile,
  getAuthUserId,
} = require('../controllers/profileController');

/**
 * PUT /api/users/me/profile
 * Update the authenticated user's profile.
 *
 * NOTE: getAuthUserId() will pull the user id from:
 *   - req.user.id / req.user.userId (if upstream auth middleware exists), or
 *   - the JWT in Authorization: Bearer <token>, or
 *   - x-user-id header (dev fallback).
 */
router.put('/me/profile', updateMyProfile);

/**
 * GET /api/users/me/favorites
 * Lists the current user's favourited outings with a nested `outing` object.
 * Shape matches what the Flutter ProfileScreen expects:
 *   [{ id, outingId, createdAt, outing: { id,title,locationName,dateTimeStart,coverImageUrl } }]
 */
router.get('/me/favorites', async (req, res) => {
  try {
    const userId = getAuthUserId(req);
    if (!userId) {
      return res.status(401).json({ ok: false, error: 'AUTH_REQUIRED' });
    }

    const favs = await prisma.favorite.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        userId: true,
        outingId: true,
        createdAt: true,
        outing: {
          select: {
            id: true,
            title: true,
            locationName: true,
            dateTimeStart: true,
            // Use most recent image as "cover"
            images: {
              take: 1,
              orderBy: { createdAt: 'desc' },
              select: { imageUrl: true },
            },
          },
        },
      },
    });

    const shaped = favs.map((f) => ({
      id: f.id,
      userId: f.userId,
      outingId: f.outingId,
      createdAt: f.createdAt,
      outing: f.outing && {
        id: f.outing.id,
        title: f.outing.title,
        locationName: f.outing.locationName,
        dateTimeStart: f.outing.dateTimeStart,
        coverImageUrl: f.outing.images?.[0]?.imageUrl ?? null,
      },
    }));

    return res.json({ ok: true, data: shaped });
  } catch (err) {
    console.error('GET /api/users/me/favorites error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
});

/**
 * GET /api/users/:userId/profile
 * Public profile for a given user. Respects isProfilePublic unless it's the same user.
 * Response shape matches what ProfilePage expects (data.user, data.stats, data.recentOutings).
 */
router.get('/:userId/profile', getPublicProfile);

module.exports = router;
