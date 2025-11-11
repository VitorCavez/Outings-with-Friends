// backend/src/routes/itineraryRoutes.js
const express = require('express');
const router = express.Router();
const {
  getSuggestedItinerary,
  listItineraryItems,
  createItineraryItem,
  updateItineraryItem,
  deleteItineraryItem,
} = require('../controllers/itineraryController');

// const { requireAuth } = require('../middleware/auth');

router.get('/api/outings/:outingId/itinerary/suggested', /* requireAuth, */ getSuggestedItinerary);
router.get('/api/outings/:outingId/itinerary', /* requireAuth, */ listItineraryItems);
router.post('/api/outings/:outingId/itinerary', /* requireAuth, */ createItineraryItem);
router.put('/api/outings/:outingId/itinerary/:itemId', /* requireAuth, */ updateItineraryItem);
router.delete('/api/outings/:outingId/itinerary/:itemId', /* requireAuth, */ deleteItineraryItem);

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
