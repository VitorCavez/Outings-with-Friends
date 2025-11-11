// backend/src/routes/groupSocialRoutes.js
const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/groupSocialController');

// TODO: replace stubs with your real auth middleware
// const { requireAuth } = require('../middleware/auth');
const requireAuth = (req, res, next) => next();

/**
 * Group profile
 */
router.get('/api/groups/:groupId/profile', /* requireAuth, */ ctrl.getGroupProfile);
router.put('/api/groups/:groupId/profile', requireAuth, ctrl.updateGroupProfile);

/**
 * Members & roles
 */
router.get('/api/groups/:groupId/members', /* requireAuth, */ ctrl.listMembers);
router.put('/api/groups/:groupId/roles/:userId', requireAuth, ctrl.updateMemberRole);
router.post('/api/groups/:groupId/leave', requireAuth, ctrl.leaveGroup);

/**
 * Invitations
 */
router.get('/api/groups/:groupId/invites', requireAuth, ctrl.listInvites);
router.post('/api/groups/:groupId/invite', requireAuth, ctrl.createInvite);
// Accept/decline via ID or token
router.post('/api/group-invites/:inviteId/accept', requireAuth, ctrl.acceptInvite);
router.post('/api/group-invites/:inviteId/decline', requireAuth, ctrl.declineInvite);
router.post('/api/group-invites/:inviteId/cancel', requireAuth, ctrl.cancelInvite);
router.post('/api/group-invites/token/:token/accept', requireAuth, ctrl.acceptInviteByToken);
router.post('/api/group-invites/token/:token/decline', requireAuth, ctrl.declineInviteByToken);

/**
 * Discovery (public groups)
 */
router.get('/api/groups/discover', /* requireAuth, */ ctrl.discoverGroups);

/**
 * Mounted in app.js with:
 *   app.use(groupSocialRoutes);
 *
 * This module defines its own /api/* paths to keep app.js clean.
 * Replace these stubs with real logic when ready.
 */

// Example: public feed of recent group activities
router.get('/api/groups/social/feed', async (req, res) => {
  try {
    // TODO: Replace with real DB query (recent join events, new outings, etc.)
    res.json({ items: [] });
  } catch (err) {
    console.error('groupSocialRoutes feed error:', err);
    res.status(500).json({ error: 'Failed to load social feed' });
  }
});

// Example: like a group post (stub)
router.post('/api/groups/:groupId/posts/:postId/like', async (req, res) => {
  try {
    const { groupId, postId } = req.params;
    // TODO: persist like
    res.status(201).json({ ok: true, groupId, postId, action: 'liked' });
  } catch (err) {
    console.error('groupSocialRoutes like error:', err);
    res.status(500).json({ error: 'Failed to like post' });
  }
});

module.exports = router;
