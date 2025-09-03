const express = require('express');
const router = express.Router();
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

// POST /api/calendar - Create a calendar entry
router.post('/', async (req, res) => {
  const {
    title,
    description,
    dateTimeStart,
    dateTimeEnd,
    isAllDay = false,
    isReminder = false,
    createdByUserId,
    linkedOutingId,
    groupId,
  } = req.body;

  if (!title || !dateTimeStart || !dateTimeEnd || !createdByUserId) {
    return res.status(400).json({ error: 'Missing required fields.' });
  }

  try {
    const entry = await prisma.calendarEntry.create({
      data: {
        title,
        description,
        dateTimeStart: new Date(dateTimeStart),
        dateTimeEnd: new Date(dateTimeEnd),
        isAllDay,
        isReminder,
        createdByUserId,
        linkedOutingId,
        groupId,
      },
    });

    res.status(201).json(entry);
  } catch (error) {
    console.error('Create calendar entry error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/calendar/user/:userId - Get calendar entries for a user
router.get('/user/:userId', async (req, res) => {
  const { userId } = req.params;

  try {
    const entries = await prisma.calendarEntry.findMany({
      where: { createdByUserId: userId },
      orderBy: { dateTimeStart: 'asc' },
    });

    res.json(entries);
  } catch (error) {
    console.error('Fetch calendar entries error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/calendar/group/:groupId - Get calendar entries for a group
router.get('/group/:groupId', async (req, res) => {
  const { groupId } = req.params;

  try {
    const entries = await prisma.calendarEntry.findMany({
      where: { groupId },
      orderBy: { dateTimeStart: 'asc' },
    });

    res.json(entries);
  } catch (error) {
    console.error('Fetch group calendar entries error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
