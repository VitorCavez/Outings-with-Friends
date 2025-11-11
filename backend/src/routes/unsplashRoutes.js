// backend/src/routes/unsplashRoutes.js
const express = require('express');
const router = express.Router();
const { searchUnsplash } = require('../controllers/unsplashController');

// If you want to require auth for this proxy, uncomment:
// const { requireAuth } = require('../middleware/auth');

router.get('/api/unsplash/search', /* requireAuth, */ searchUnsplash);

module.exports = router;
