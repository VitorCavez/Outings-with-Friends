// backend/src/routes/pushRoutes.js
const express = require('express');
const router = express.Router();
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

/**
 * POST /api/push/register
 * Body: { userId, fcmToken }
 * Saves/updates the user's current FCM token.
 */
router.post('/register', async (req, res) => {
  try {
    let { userId, fcmToken } = req.body || {};
    if (typeof userId !== 'string' || typeof fcmToken !== 'string') {
      return res.status(400).json({ error: 'userId and fcmToken must be strings' });
    }
    userId = userId.trim();
    fcmToken = fcmToken.trim();
    if (!userId || !fcmToken) {
      return res.status(400).json({ error: 'userId and fcmToken are required' });
    }

    // Update only if changed (keeps writes minimal)
    const existing = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, fcmToken: true },
    });
    if (!existing) {
      return res.status(404).json({ error: 'User not found' });
    }

    if (existing.fcmToken === fcmToken) {
      return res.json({ ok: true, updated: false });
    }

    await prisma.user.update({
      where: { id: userId },
      data: { fcmToken },
    });

    return res.json({ ok: true, updated: true });
  } catch (e) {
    console.error('register token error', e);
    return res.status(500).json({ error: 'failed to register token' });
  }
});

/**
 * POST /api/push/unregister
 * Body: { userId }
 * Clears the user's FCM token (e.g., on logout).
 */
router.post('/unregister', async (req, res) => {
  try {
    let { userId } = req.body || {};
    if (typeof userId !== 'string') {
      return res.status(400).json({ error: 'userId must be a string' });
    }
    userId = userId.trim();
    if (!userId) {
      return res.status(400).json({ error: 'userId is required' });
    }

    // If user not found, respond idempotently
    const existing = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true },
    });
    if (!existing) {
      return res.json({ ok: true, updated: false });
    }

    await prisma.user.update({
      where: { id: userId },
      data: { fcmToken: null },
    });

    return res.json({ ok: true, updated: true });
  } catch (e) {
    console.error('unregister token error', e);
    return res.status(500).json({ error: 'failed to unregister token' });
  }
});

/**
 * GET /api/push/status/:userId
 * Quick debug route to see if a user currently has a token.
 */
router.get('/status/:userId', async (req, res) => {
  try {
    const userId = String(req.params.userId || '').trim();
    if (!userId) return res.status(400).json({ error: 'userId is required' });

    const u = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, fcmToken: true },
    });
    if (!u) return res.status(404).json({ error: 'User not found' });

    return res.json({ hasToken: !!u.fcmToken, fcmToken: u.fcmToken || null });
  } catch (e) {
    console.error('status error', e);
    return res.status(500).json({ error: 'failed to get status' });
  }
});

module.exports = router;
