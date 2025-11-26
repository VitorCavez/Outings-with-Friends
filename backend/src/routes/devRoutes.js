// backend/src/routes/devRoutes.js
const express = require('express');
const router = express.Router();
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
const jwt = require('jsonwebtoken');
const path = require('path');
const bcrypt = require('bcryptjs');

// Reuse the seeder
const { runSeed } = require(path.join(__dirname, '..', '..', 'prisma', 'seed.js'));

/**
 * Gate all dev routes:
 * - In production: require ENABLE_DEV_ROUTES === 'true'
 * - In non-production: always allow
 */
function ensureDevEnabled(req, res, next) {
  const enabled =
    process.env.NODE_ENV !== 'production' ||
    process.env.ENABLE_DEV_ROUTES === 'true';
  if (!enabled) {
    return res.status(403).json({ ok: false, error: 'DISABLED_IN_PRODUCTION' });
  }
  next();
}
router.use(ensureDevEnabled);

// Ensure JSON parsing (in case parent app didn't attach body parser here)
router.use(express.json());

/**
 * POST /dev/set-password
 * Body: { email, password }
 * - Updates passwordHash if user exists
 * - Creates user with the password if not found
 */
router.post('/set-password', async (req, res) => {
  const { email, password } = req.body || {};
  if (!email || !password) {
    return res.status(400).json({ error: 'email and password required' });
  }

  try {
    const normalized = String(email).toLowerCase();
    const hash = await bcrypt.hash(password, 10);
    await prisma.user.update({
      where: { email: normalized },
      data: { passwordHash: hash },
    });
    return res.json({ ok: true, updated: true });
  } catch (e) {
    // User not found -> create it
    if (e.code === 'P2025') {
      const normalized = String(email).toLowerCase();
      const hash = await bcrypt.hash(password, 10);
      await prisma.user.create({
        data: { email: normalized, passwordHash: hash },
      });
      return res.json({ ok: true, created: true });
    }
    console.error('set-password error:', e);
    return res.status(500).json({ error: 'SET_PASSWORD_FAILED' });
  }
});

/**
 * POST /dev/reset
 * Body: { seed?: boolean }  (default true)
 * Wipes data and optionally re-seeds.
 */
router.post('/reset', async (req, res) => {
  const seed = req.body?.seed !== false; // default true
  try {
    await prisma.$transaction([
      prisma.outingParticipant.deleteMany(),
      prisma.outingInvite.deleteMany(),
      prisma.outingImage.deleteMany(),
      prisma.outingContribution.deleteMany(),
      prisma.expense.deleteMany(),
      prisma.outingUser.deleteMany(),
      prisma.itineraryItem.deleteMany(),
      prisma.favorite.deleteMany(),
      prisma.calendarEntry.deleteMany(),
      prisma.message.deleteMany(),
      prisma.groupInvitation.deleteMany(),
      prisma.groupMembership.deleteMany(),
      prisma.outing.deleteMany(),
      prisma.group.deleteMany(),
      prisma.contact.deleteMany(),
      prisma.inviteRequest.deleteMany(),
      prisma.availabilitySlot.deleteMany(),
      prisma.user.deleteMany(),
    ]);

    let seeded = null;
    if (seed) {
      seeded = await runSeed();
    }

    return res.json({
      ok: true,
      seeded: !!seed,
      details: seeded
        ? {
            users: ['alice@example.com', 'bob@example.com', 'cara@example.com'],
            brunchId: seeded.brunch.id,
            trailId: seeded.trail.id,
          }
        : undefined,
    });
  } catch (e) {
    console.error('dev/reset error:', e);
    return res.status(500).json({ ok: false, error: e.message });
  }
});

/**
 * POST /dev/seed
 * Runs the seed script without wiping.
 */
router.post('/seed', async (_req, res) => {
  try {
    const out = await runSeed();
    return res.json({
      ok: true,
      details: { brunchId: out.brunch.id, trailId: out.trail.id },
    });
  } catch (e) {
    console.error('dev/seed error:', e);
    return res.status(500).json({ ok: false, error: e.message });
  }
});

/**
 * GET /dev/jwt?email=...  OR  /dev/jwt?userId=...
 * Issues a short-lived JWT for quick testing.
 */
router.get('/jwt', async (req, res) => {
  try {
    const { email, userId } = req.query;
    if (!email && !userId) {
      return res.status(400).json({ ok: false, error: 'email or userId required' });
    }

    const user = email
      ? await prisma.user.findUnique({ where: { email: String(email).toLowerCase() } })
      : await prisma.user.findUnique({ where: { id: String(userId) } });

    if (!user) return res.status(404).json({ ok: false, error: 'USER_NOT_FOUND' });

    const token = jwt.sign(
      { userId: user.id, email: user.email },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );

    return res.json({
      ok: true,
      token,
      user: { id: user.id, email: user.email, fullName: user.fullName },
    });
  } catch (e) {
    console.error('dev/jwt error:', e);
    return res.status(500).json({ ok: false, error: e.message });
  }
});

module.exports = router;
