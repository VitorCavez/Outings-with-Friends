// backend/src/routes/itineraryRoutes.js
const express = require('express');
const router = express.Router();

router.get('/api/itinerary/:outingId', async (req, res) => {
  try {
    const { outingId } = req.params;
    res.json({ outingId, items: [] });
  } catch (err) {
    console.error('itineraryRoutes error:', err);
    res.status(500).json({ error: 'Failed to load itinerary' });
  }
});

module.exports = router;
