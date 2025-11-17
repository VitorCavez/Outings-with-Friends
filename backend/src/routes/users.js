// backend/src/routes/users.js
const express = require('express');
const router = express.Router();
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

/**
 * If you already have auth middleware that sets req.user from your JWT,
 * delete this and use yours. Otherwise this protects the /me/* endpoints.
 */
function requireAuth(req, res, next) {
  if (!req.user) return res.status(401).json({ error: 'UNAUTHENTICATED' });
  next();
}

/**
 * GET /api/users/:userId/profile
 * Public profile for a given user. Respects isProfilePublic unless it's the same user.
 * Shape matches what ProfilePage expects.
 */
router.get('/:userId/profile', async (req, res) => {
  const { userId } = req.params;

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      id: true,
      fullName: true,
      username: true,
      profilePhotoUrl: true,
      homeLocation: true,
      bio: true,
      badges: true,          // String[]
      outingScore: true,     // Int
      isProfilePublic: true,
    },
  });

  if (!user) return res.status(404).json({ error: 'NOT_FOUND' });

  const isMe = req.user && req.user.id === userId;
  if (!user.isProfilePublic && !isMe) {
    // You already handle PROFILE_PRIVATE in the Flutter page
    return res.status(403).json({ error: 'PROFILE_PRIVATE' });
  }

  res.json({
    data: {
      id: user.id,
      fullName: user.fullName,
      username: user.username,
      profilePhotoUrl: user.profilePhotoUrl,
      homeLocation: user.homeLocation,
      bio: user.bio,
      badges: user.badges || [],
      outingScore: user.outingScore ?? 0,
    },
  });
});

/**
 * GET /api/users/me/favorites
 * Lists the current user's favourited outings with a nested `outing` object.
 * The Flutter page expects: [{ id, outingId, createdAt, outing: { id,title,locationName,dateTimeStart,coverImageUrl } }]
 */
router.get('/me/favorites', requireAuth, async (req, res) => {
  const userId = req.user.id;

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
          // There is no coverImageUrl column on Outing, so use the most recent OutingImage
          images: {
            take: 1,
            orderBy: { createdAt: 'desc' },
            select: { imageUrl: true },
          },
        },
      },
    },
  });

  const shaped = favs.map(f => ({
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

  res.json({ data: shaped });
});

module.exports = router;
