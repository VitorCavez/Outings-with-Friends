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

module.exports = router;
