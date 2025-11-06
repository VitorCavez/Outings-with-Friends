// backend/src/routes/imageRoutes.js
const express = require('express');
const router = express.Router();

/** Defines its own /api/* paths */
router.get('/api/images/:id', async (req, res) => {
  try {
    const { id } = req.params;
    res.json({ id, url: null, caption: null });
  } catch (err) {
    console.error('imageRoutes error:', err);
    res.status(500).json({ error: 'Failed to load image' });
  }
});

module.exports = router;
