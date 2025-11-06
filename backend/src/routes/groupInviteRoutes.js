// backend/src/routes/groupInviteRoutes.js
const express = require('express');
const router = express.Router();

/**
 * Mounted in app.js as:
 *   app.use('/api/groups', groupInviteRoutes);
 *
 * So these become:
 *   GET  /api/groups/:groupId/invites
 *   POST /api/groups/:groupId/invites
 */

// List invites for a group (stub)
router.get('/:groupId/invites', async (req, res) => {
  try {
    const { groupId } = req.params;
    // TODO: Replace with real DB query
    return res.json({ groupId, invites: [] });
  } catch (err) {
    console.error('groupInviteRoutes GET error:', err);
    return res.status(500).json({ error: 'Failed to fetch invites' });
  }
});

// Create/send an invite (stub)
router.post('/:groupId/invites', async (req, res) => {
  try {
    const { groupId } = req.params;
    const { toUserId, phone, email } = req.body || {};
    // TODO: Replace with real create/send logic
    return res.status(201).json({
      ok: true,
      groupId,
      toUserId: toUserId || null,
      phone: phone || null,
      email: email || null,
    });
  } catch (err) {
    console.error('groupInviteRoutes POST error:', err);
    return res.status(500).json({ error: 'Failed to create invite' });
  }
});

module.exports = router;
