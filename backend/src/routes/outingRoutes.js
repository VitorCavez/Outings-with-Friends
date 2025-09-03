const express = require('express');
const router = express.Router();
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
const { requireFields } = require('../utils/validators');

// ✅ POST /api/outings - Create a new outing
router.post('/', async (req, res) => {
  const {
    title,
    outingType,
    createdById,
    groupId,
    locationName,
    latitude,
    longitude,
    address,
    dateTimeStart,
    dateTimeEnd,
    description,
    budgetMin,
    budgetMax,
    piggyBankEnabled = false,
    piggyBankTarget,
    checklist = [],
    suggestedItinerary,
    liveLocationEnabled = false,
    isPublic = false
  } = req.body;

  // ✅ Validation
  if (
    !title || !outingType || !createdById ||
    !locationName || latitude === undefined || longitude === undefined ||
    !dateTimeStart || !dateTimeEnd
  ) {
    return res.status(400).json({ error: 'Missing required fields.' });
  }

  try {
    const outing = await prisma.outing.create({
      data: {
        title,
        outingType,
        createdById,
        groupId,
        locationName,
        latitude,
        longitude,
        address,
        dateTimeStart: new Date(dateTimeStart),
        dateTimeEnd: new Date(dateTimeEnd),
        description,
        budgetMin,
        budgetMax,
        piggyBankEnabled,
        piggyBankTarget,
        checklist,
        suggestedItinerary,
        liveLocationEnabled,
        isPublic
      }
    });

    res.status(201).json({ message: 'Outing created successfully.', outing });
  } catch (error) {
    console.error('Create outing error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});


// ✅ GET /api/outings - List all outings
router.get('/', async (req, res) => {
  try {
    const outings = await prisma.outing.findMany();
    res.json(outings);
  } catch (error) {
    console.error('Fetch all outings error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ✅ GET /api/outings/:id - Get outing by ID
router.get('/:id', async (req, res) => {
  const { id } = req.params;

  try {
    const outing = await prisma.outing.findUnique({
      where: { id },
    });

    if (!outing) {
      return res.status(404).json({ error: 'Outing not found' });
    }

    res.json(outing);
  } catch (error) {
    console.error('Fetch outing by ID error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});
// ✅ PUT /api/outings/:id - Update an outing
router.put('/:id', async (req, res) => {
  const { id } = req.params;
  const updateData = req.body;

  try {
    const outing = await prisma.outing.update({
      where: { id },
      data: updateData,
    });

    res.json({ message: 'Outing updated successfully', outing });
  } catch (error) {
    console.error('Update outing error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});
// ✅ DELETE /api/outings/:id - Delete an outing
router.delete('/:id', async (req, res) => {
  const { id } = req.params;

  try {
    await prisma.outingUser.deleteMany({ where: { outingId: id } }); // remove RSVPs
    await prisma.outingContribution.deleteMany({ where: { outingId: id } }); // remove contributions
    await prisma.outingImage.deleteMany({ where: { outingId: id } }); // remove images
    await prisma.calendarEntry.deleteMany({ where: { linkedOutingId: id } }); // remove calendar links

    const deleted = await prisma.outing.delete({ where: { id } });

    res.json({ message: 'Outing deleted successfully', deleted });
  } catch (error) {
    console.error('Delete outing error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});
// ✅ POST /api/outings/:outingId/rsvp - RSVP to an outing
router.post('/:outingId/rsvp', async (req, res) => {
  const { outingId } = req.params;
  const { userId, rsvpStatus } = req.body;

  if (!userId || !rsvpStatus) {
    return res.status(400).json({ error: 'userId and rsvpStatus are required.' });
  }

  try {
    // Check if RSVP already exists
    const existing = await prisma.outingUser.findFirst({
      where: { outingId, userId },
    });

    if (existing) {
      // Update existing RSVP
      const updated = await prisma.outingUser.update({
        where: { id: existing.id },
        data: { rsvpStatus },
      });
      return res.json({ message: 'RSVP updated', rsvp: updated });
    }

    // Create new RSVP
    const rsvp = await prisma.outingUser.create({
      data: { outingId, userId, rsvpStatus },
    });

    res.status(201).json({ message: 'RSVP created', rsvp });
  } catch (error) {
    console.error('RSVP error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
