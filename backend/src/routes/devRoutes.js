// backend/src/routes/devRoutes.js
const express = require('express');
const router = express.Router();
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
const jwt = require('jsonwebtoken');
const path = require('path');

// reuse the seeder
const { runSeed } = require(path.join(__dirname, '..', '..', 'prisma', 'seed.js'));

// below other requires
const bcrypt = require('bcryptjs');

// add this inside the dev router file
router.post('/set-password', async (req, res) => {
  // safety: only allow when explicitly enabled
  if (process.env.ENABLE_DEV_ROUTES !== 'true') {
    return res.status(403).json({ error: 'DEV_ROUTES_DISABLED' });
  }
  const { email, password } = req.body || {};
  if (!email || !password) return res.status(400).json({ error: 'email and password required' });

  try {
    const hash = await bcrypt.hash(password, 10);
    await prisma.user.update({ where: { email }, data: { passwordHash: hash } });
    res.json({ ok: true });
  } catch (e) {
    // if user not found, create it:
    if (e.code === 'P2025') {
      const hash = await bcrypt.hash(password, 10);
      await prisma.user.create({ data: { email, passwordHash: hash } });
      return res.json({ ok: true, created: true });
    }
    console.error(e);
    res.status(500).json({ error: 'SET_PASSWORD_FAILED' });
  }
});

function ensureDevEnabled(req, res, next) {
  const enabled = process.env.NODE_ENV !== 'production' || process.env.ENABLE_DEV_ROUTES === 'true';
  if (!enabled) {
    return res.status(403).json({ ok: false, error: 'DISABLED' });
  }
  next();
}

router.use(ensureDevEnabled);

// POST /dev/reset  { seed?: boolean }
// Wipes data (via deleteMany) and optionally re-seeds with the seed script.
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
    res.json({ ok: true, seeded: !!seed, details: seeded ? {
      users: ['alice@example.com','bob@example.com','cara@example.com'],
      brunchId: seeded.brunch.id,
      trailId: seeded.trail.id,
    } : undefined });
  } catch (e) {
    console.error('dev/reset error:', e);
    res.status(500).json({ ok: false, error: e.message });
  }
});

// POST /dev/seed
router.post('/seed', async (_req, res) => {
  try {
    const out = await runSeed();
    res.json({ ok: true, details: { brunchId: out.brunch.id, trailId: out.trail.id } });
  } catch (e) {
    console.error('dev/seed error:', e);
    res.status(500).json({ ok: false, error: e.message });
  }
});

// GET /dev/jwt?email=...  OR  /dev/jwt?userId=...
router.get('/jwt', async (req, res) => {
  try {
    const { email, userId } = req.query;
    if (!email && !userId) return res.status(400).json({ ok: false, error: 'email or userId required' });

    const user = email
      ? await prisma.user.findUnique({ where: { email: String(email).toLowerCase() } })
      : await prisma.user.findUnique({ where: { id: String(userId) } });

    if (!user) return res.status(404).json({ ok: false, error: 'USER_NOT_FOUND' });

    const token = jwt.sign(
      { userId: user.id, email: user.email },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );
    res.json({ ok: true, token, user: { id: user.id, email: user.email, fullName: user.fullName } });
  } catch (e) {
    console.error('dev/jwt error:', e);
    res.status(500).json({ ok: false, error: e.message });
  }
});

module.exports = router;
