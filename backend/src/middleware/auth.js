// backend/src/middleware/auth.js
const { PrismaClient } = require('@prisma/client');
const jwt = require('jsonwebtoken');
const prisma = new PrismaClient();

/**
 * Require a valid JWT. Equivalent to your authenticateToken.
 * Sets req.user = { userId, email }.
 */
function requireAuth(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) return res.status(401).json({ ok: false, error: 'AUTH_REQUIRED' });

  jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
    if (err) return res.status(403).json({ ok: false, error: 'INVALID_TOKEN' });
    req.user = user; // { userId, email }
    next();
  });
}

/**
 * Require group admin or group owner.
 */
async function requireGroupAdminOrOwner(req, res, next) {
  try {
    const { groupId } = req.params;
    if (!groupId) return res.status(400).json({ ok: false, error: 'GROUP_ID_REQUIRED' });
    if (!req.user?.userId) return res.status(401).json({ ok: false, error: 'AUTH_REQUIRED' });

    const group = await prisma.group.findUnique({
      where: { id: groupId },
      select: { id: true, createdById: true },
    });
    if (!group) return res.status(404).json({ ok: false, error: 'GROUP_NOT_FOUND' });

    if (group.createdById === req.user.userId) return next();

    const membership = await prisma.groupMembership.findFirst({
      where: { groupId, userId: req.user.userId },
      select: { role: true, isAdmin: true },
    });

    const isAdmin = membership?.role === 'admin' || membership?.isAdmin === true;
    if (!isAdmin) return res.status(403).json({ ok: false, error: 'FORBIDDEN' });

    return next();
  } catch (err) {
    console.error('requireGroupAdminOrOwner error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
}

module.exports = {
  requireAuth,
  requireGroupAdminOrOwner,
};
