// backend/src/routes/rsvpRoutes.js
const express = require('express');
const router = express.Router();
const prisma = require('../../prisma/client');
const { requireAuth } = require('../middleware/auth');

// Treat these as "going" equivalents
const GOING_SET = new Set(['going', 'accepted', 'yes']);

// ✅ POST /api/rsvp/:outingId/rsvp - Create or update RSVP
router.post('/:outingId/rsvp', requireAuth, async (req, res) => {
  const { outingId } = req.params;
  const userId = req.user.userId;
  const { rsvpStatus } = req.body || {};

  if (!rsvpStatus) {
    return res.status(400).json({ error: 'rsvpStatus is required.' });
  }

  try {
    // Ensure outing exists (and fetch any linked groupId)
    const outing = await prisma.outing.findUnique({
      where: { id: outingId },
      select: { id: true, groupId: true },
    });
    if (!outing) return res.status(404).json({ error: 'OUTING_NOT_FOUND' });

    // Upsert RSVP
    const existing = await prisma.outingUser.findFirst({
      where: { outingId, userId },
    });

    let rsvpRecord;
    if (existing) {
      rsvpRecord = await prisma.outingUser.update({
        where: { id: existing.id },
        data: { rsvpStatus },
      });
    } else {
      rsvpRecord = await prisma.outingUser.create({
        data: { outingId, userId, rsvpStatus },
      });
    }

    // 🔗 Auto-join the outing's linked group if RSVP is "going"
    if (outing.groupId && GOING_SET.has(String(rsvpStatus).toLowerCase())) {
      await prisma.groupMembership.upsert({
        where: { userId_groupId: { userId, groupId: outing.groupId } },
        update: {}, // idempotent
        create: { userId, groupId: outing.groupId, role: 'member' },
      });
    }

    return res.json({ ok: true, message: existing ? 'RSVP updated' : 'RSVP created', rsvp: rsvpRecord });
  } catch (error) {
    console.error('RSVP error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ✅ GET /api/rsvp/:outingId/rsvps - List RSVPs for an outing
router.get('/:outingId/rsvps', async (req, res) => {
  const { outingId } = req.params;

  try {
    const rsvps = await prisma.outingUser.findMany({
      where: { outingId },
      include: {
        user: {
          select: {
            id: true,
            fullName: true,
            email: true,
            username: true,
            profilePhotoUrl: true,
          },
        },
      },
    });

    res.json({ ok: true, data: rsvps });
  } catch (error) {
    console.error('Fetch RSVPs error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
