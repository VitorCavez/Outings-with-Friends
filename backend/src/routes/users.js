// backend/src/routes/users.js
const express = require('express');
const jwt = require('jsonwebtoken');

const router = express.Router();

/**
 * Optional JWT decode:
 * - If an Authorization: Bearer <token> header is present, we decode it.
 * - If it's missing or invalid, we just proceed without a user (public routes still work).
 */
function authOptional(req, _res, next) {
  try {
    const hdr = req.headers.authorization || '';
    const [, token] = hdr.split(' ');
    if (token) {
      const secret = process.env.JWT_SECRET || 'changeme';
      req.user = jwt.verify(token, secret);
    }
  } catch (_) {
    // ignore invalid token; route can decide to require auth if needed
  }
  next();
}

router.use(authOptional);

// Simple health for diagnostics
router.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'users', ts: Date.now() });
});

// Quick ping
router.get('/ping', (_req, res) => {
  res.type('text/plain').send('pong');
});

/**
 * Return the current user info (if JWT is present).
 * If no token or invalid token, return 401.
 */
router.get('/me', (req, res) => {
  if (!req.user) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  // Return only safe/basic fields that are commonly in your token.
  const { id, userId, email, username } = req.user;
  res.json({
    id: id || userId || null,
    email: email || null,
    username: username || null,
    tokenClaims: req.user, // helpful while stabilizing; remove later if you prefer
  });
});

module.exports = router;
