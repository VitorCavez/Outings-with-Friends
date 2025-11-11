// backend/src/routes/groupInviteRoutes.js
const express = require('express');
const router = express.Router({ mergeParams: true });

const {
  createInvite,
  listInvitesForGroup,
  listMyInvites,
  acceptInvite,
  declineInvite,
  cancelInvite,
} = require('../controllers/groupInviteController');

const {
  requireAuth,
  requireGroupAdminOrOwner,
} = require('../middleware/auth');

// NOTE: Mount at /api/groups in index.js:
//   const groupInviteRoutes = require('./routes/groupInviteRoutes');
//   app.use('/api/groups', groupInviteRoutes);

// Create an invite (admin/creator only)
router.post('/:groupId/invites', requireAuth, requireGroupAdminOrOwner, createInvite);

// List invites for a group (admin/creator only)
router.get('/:groupId/invites', requireAuth, requireGroupAdminOrOwner, listInvitesForGroup);

// Current user's pending invites (addressed to them)
router.get('/me/invites', requireAuth, listMyInvites);

// Respond to invites (invitee)
router.post('/invites/:inviteId/accept', requireAuth, acceptInvite);
router.post('/invites/:inviteId/decline', requireAuth, declineInvite);

// Cancel a pending invite (inviter or group admin)
router.post('/invites/:inviteId/cancel', requireAuth, cancelInvite);
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
