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

const { authenticateToken } = require('./auth_middleware');

// Version marker so you can see in logs which file is deployed
console.log('[routes] itineraryRoutes v3 loaded');

//
// Suggested itinerary – requires auth (optional, but consistent)
//
// GET /api/outings/:outingId/itinerary/suggested
router.get(
  '/api/outings/:outingId/itinerary/suggested',
  authenticateToken,
  getSuggestedItinerary
);

//
// List itinerary items – can be public if you want
//
// GET /api/outings/:outingId/itinerary
router.get(
  '/api/outings/:outingId/itinerary',
  listItineraryItems
);

//
// Create itinerary item – MUST be authenticated
//
// POST /api/outings/:outingId/itinerary
router.post(
  '/api/outings/:outingId/itinerary',
  authenticateToken,
  createItineraryItem
);

//
// Update itinerary item – MUST be authenticated
//
// PUT /api/outings/:outingId/itinerary/:itemId
router.put(
  '/api/outings/:outingId/itinerary/:itemId',
  authenticateToken,
  updateItineraryItem
);

//
// Delete itinerary item – MUST be authenticated
//
// DELETE /api/outings/:outingId/itinerary/:itemId
router.delete(
  '/api/outings/:outingId/itinerary/:itemId',
  authenticateToken,
  deleteItineraryItem
);

// Legacy / fallback route
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
