// backend/src/routes/devRoutes.js
const express = require('express');
const router = express.Router();

router.get('/ping', (_req, res) => res.json({ pong: true }));
module.exports = router;
