// backend/src/routes/profileRoutes.js
const express = require('express');
const router = express.Router();

router.get('/api/profile/me', async (req, res) => {
  try {
    res.json({ id: null, name: null, avatarUrl: null });
  } catch (err) {
    console.error('profileRoutes error:', err);
    res.status(500).json({ error: 'Failed to load profile' });
  }
});

router.patch('/api/profile/me', async (req, res) => {
  try {
    res.json({ ok: true, updated: req.body || {} });
  } catch (err) {
    console.error('profileRoutes update error:', err);
    res.status(500).json({ error: 'Failed to update profile' });
  }
});

module.exports = router;
