// backend/src/routes/favoriteRoutes.js
const express = require('express');
const router = express.Router();

const { requireAuth } = require('../middleware/auth');

const {
  favoriteOuting,
  unfavoriteOuting,
  listMyFavorites,
} = require('../controllers/favoriteController');

// Favorite an outing
router.post('/api/outings/:outingId/favorite', requireAuth, favoriteOuting);

// Unfavorite an outing
router.delete('/api/outings/:outingId/favorite', requireAuth, unfavoriteOuting);

// List current user’s favorites
router.get('/api/users/me/favorites', requireAuth, listMyFavorites);

// (Optional) keep or remove this placeholder route
router.get('/api/favorites', requireAuth, async (_req, res) => {
  res.json({ items: [] });
});

module.exports = router;
