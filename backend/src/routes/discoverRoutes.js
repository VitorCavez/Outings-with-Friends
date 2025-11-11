// backend/src/routes/discoverRoutes.js
const express = require('express');
const router = express.Router();

/** Mounted in app.js as: app.use('/api', discoverRoutes)
 *  → final path = /api/discover
 */
router.get('/discover', async (req, res) => {
  try {
    res.json({ featured: [], suggested: [] });
  } catch (err) {
    console.error('discoverRoutes error:', err);
    res.status(500).json({ error: 'Failed to load discover data' });
  }
});

module.exports = router;
