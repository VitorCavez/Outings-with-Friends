// backend/src/routes/geoRoutes.js
const express = require('express');
const router = express.Router();

router.get('/api/geo/reverse', async (req, res) => {
  try {
    const { lat, lng } = req.query;
    res.json({ lat, lng, label: null });
  } catch (err) {
    console.error('geoRoutes error:', err);
    res.status(500).json({ error: 'Failed to reverse geocode' });
  }
});

module.exports = router;
