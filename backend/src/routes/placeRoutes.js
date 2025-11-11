// backend/src/routes/placeRoutes.js
const express = require('express');
const router = express.Router();

router.get('/api/places/search', async (req, res) => {
  try {
    const { q = '' } = req.query;
    res.json({ query: q, results: [] });
  } catch (err) {
    console.error('placeRoutes error:', err);
    res.status(500).json({ error: 'Failed to search places' });
  }
});

module.exports = router;
