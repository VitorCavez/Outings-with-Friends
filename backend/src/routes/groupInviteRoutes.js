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

const { requireAuth, requireGroupAdminOrOwner } = require('../middleware/auth');

// Mount this file under /api/groups in app.js
// app.use('/api/groups', groupInviteRoutes);

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

module.exports = router;
