// backend/src/routes/unsplashRoutes.js
const express = require('express');
const router = express.Router();

router.get('/api/unsplash/search', async (req, res) => {
  try {
    const { q = '' } = req.query;
    res.json({ query: q, results: [] });
  } catch (err) {
    console.error('unsplashRoutes error:', err);
    res.status(500).json({ error: 'Failed to search images' });
  }
});

module.exports = router;
