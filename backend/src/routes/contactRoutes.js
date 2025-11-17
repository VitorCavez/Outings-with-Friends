// backend/src/routes/contactRoutes.js
const express = require('express');
const router = express.Router();
const { requireAuth } = require('../middleware/auth');
const ctrl = require('../controllers/contactController');

// Phone-number discovery only (no global search)
router.post('/lookup-by-phone', requireAuth, ctrl.lookupByPhone);

// Manage my contacts
router.post('/', requireAuth, ctrl.addContact);
router.get('/', requireAuth, ctrl.listContacts);
router.delete('/:userId', requireAuth, ctrl.removeContact);

module.exports = router;
