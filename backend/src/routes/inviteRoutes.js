// backend/src/routes/inviteRoutes.js
const express = require('express');
const router = express.Router();

router.post('/', async (req, res) => {
  try {
    const { toUserId, groupId } = req.body || {};
    res.status(201).json({ ok: true, toUserId, groupId });
  } catch (err) {
    console.error('inviteRoutes error:', err);
    res.status(500).json({ error: 'Failed to create invite' });
  }
});

module.exports = router;
