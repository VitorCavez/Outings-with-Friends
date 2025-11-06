// backend/src/routes/favoriteRoutes.js
const express = require('express');
const router = express.Router();

router.get('/api/favorites', async (_req, res) => {
  try {
    res.json({ items: [] });
  } catch (err) {
    console.error('favoriteRoutes error:', err);
    res.status(500).json({ error: 'Failed to load favorites' });
  }
});

module.exports = router;
