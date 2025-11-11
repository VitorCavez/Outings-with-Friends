// backend/src/routes/contactRoutes.js
const express = require('express');
const router = express.Router();

router.get('/', async (_req, res) => {
  try {
    res.json({ contacts: [] });
  } catch (err) {
    console.error('contactRoutes error:', err);
    res.status(500).json({ error: 'Failed to load contacts' });
  }
});

module.exports = router;
