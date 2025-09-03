const express = require('express');
const router = express.Router();
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

// POST /api/availability - Create slot
router.post('/', async (req, res) => {
  const {
    userId,
    activityType,
    dateTimeStart,
    dateTimeEnd,
    repeatPattern,
    notes,
  } = req.body;

  if (!userId || !dateTimeStart || !dateTimeEnd) {
    return res.status(400).json({ error: 'userId, dateTimeStart, and dateTimeEnd are required.' });
  }

  try {
    const slot = await prisma.availabilitySlot.create({
      data: {
        userId,
        activityType,
        dateTimeStart: new Date(dateTimeStart),
        dateTimeEnd: new Date(dateTimeEnd),
        repeatPattern,
        notes,
      },
    });

    res.status(201).json(slot);
  } catch (error) {
    console.error('Create slot error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/availability/:userId - List availability for a user
router.get('/user/:userId', async (req, res) => {
  const { userId } = req.params;

  try {
    const slots = await prisma.availabilitySlot.findMany({
      where: { userId },
      orderBy: { dateTimeStart: 'asc' },
    });

    res.json(slots);
  } catch (error) {
    console.error('Fetch availability error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
