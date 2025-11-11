// backend/src/routes/favoriteRoutes.js
const express = require('express');
const router = express.Router();
const {
  favoriteOuting,
  unfavoriteOuting,
  listMyFavorites,
} = require('../controllers/favoriteController');

// Uncomment requireAuth once middleware is wired
// const { requireAuth } = require('../middleware/auth');

// Favorite an outing
router.post('/api/outings/:outingId/favorite', /* requireAuth, */ favoriteOuting);

// Unfavorite an outing
router.delete('/api/outings/:outingId/favorite', /* requireAuth, */ unfavoriteOuting);

// List current user’s favorites
router.get('/api/users/me/favorites', /* requireAuth, */ listMyFavorites);

router.get('/api/favorites', async (_req, res) => {
  try {
    res.json({ items: [] });
  } catch (err) {
    console.error('favoriteRoutes error:', err);
    res.status(500).json({ error: 'Failed to load favorites' });
  }
});

module.exports = router;
