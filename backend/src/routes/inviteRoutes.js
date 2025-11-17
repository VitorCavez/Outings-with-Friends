// backend/src/routes/inviteRoutes.js
const express = require('express');
const router = express.Router();
const { requireAuth } = require('../middleware/auth');
const ctrl = require('../controllers/inviteController');

router.post('/', requireAuth, ctrl.createInvite);
router.post('/:id/accept', requireAuth, ctrl.acceptInvite);
router.post('/:id/decline', requireAuth, ctrl.declineInvite);
router.get('/', requireAuth, ctrl.listInvites);

module.exports = router;
