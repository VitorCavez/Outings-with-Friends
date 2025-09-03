const express = require('express');
const router = express.Router();
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

// ✅ POST /api/rsvp/:outingId/rsvp - Create or update RSVP
router.post('/:outingId/rsvp', async (req, res) => {
  const { outingId } = req.params;
  const { userId, rsvpStatus } = req.body;

  if (!userId || !rsvpStatus) {
    return res.status(400).json({ error: 'userId and rsvpStatus are required.' });
  }

  try {
    const existing = await prisma.outingUser.findFirst({
      where: { outingId, userId },
    });

    if (existing) {
      const updated = await prisma.outingUser.update({
        where: { id: existing.id },
        data: { rsvpStatus },
      });
      return res.json({ message: 'RSVP updated', rsvp: updated });
    }

    const rsvp = await prisma.outingUser.create({
      data: { outingId, userId, rsvpStatus },
    });

    res.status(201).json({ message: 'RSVP created', rsvp });
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
          }
        }
      }
    });

    res.json(rsvps);
  } catch (error) {
    console.error('Fetch RSVPs error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
