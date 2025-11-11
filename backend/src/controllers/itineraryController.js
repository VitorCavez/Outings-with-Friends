// backend/src/controllers/itineraryController.js
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

function getAuthUserId(req) {
  return req.user?.id || req.headers['x-user-id'] || null;
}

/**
 * GET /api/outings/:outingId/itinerary/suggested
 * Simple heuristic suggestion based on outing times/type
 */
async function getSuggestedItinerary(req, res) {
  try {
    const { outingId } = req.params;
    const outing = await prisma.outing.findUnique({ where: { id: outingId } });
    if (!outing) return res.status(404).json({ ok: false, error: 'OUTING_NOT_FOUND' });

    const start = outing.dateTimeStart;
    const end = outing.dateTimeEnd;
    const midpoint = new Date((start.getTime() + end.getTime()) / 2);

    const items = [
      {
        title: 'Meet & Greet',
        notes: `Arrive at ${outing.locationName}`,
        startTime: start,
        endTime: new Date(start.getTime() + 30 * 60 * 1000),
        orderIndex: 0,
      },
      {
        title: 'Main Activity',
        notes: `Enjoy the ${outing.outingType}`,
        startTime: new Date(start.getTime() + 30 * 60 * 1000),
        endTime: new Date(midpoint.getTime() + 30 * 60 * 1000),
        orderIndex: 1,
      },
      {
        title: 'Food & Chat',
        notes: 'Grab a bite nearby and share highlights',
        startTime: new Date(midpoint.getTime() + 30 * 60 * 1000),
        endTime: end,
        orderIndex: 2,
      },
    ];

    return res.json({ ok: true, data: items });
  } catch (err) {
    console.error('getSuggestedItinerary error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
}

/**
 * GET /api/outings/:outingId/itinerary
 */
async function listItineraryItems(req, res) {
  try {
    const { outingId } = req.params;
    const items = await prisma.itineraryItem.findMany({
      where: { outingId },
      orderBy: [{ orderIndex: 'asc' }, { startTime: 'asc' }],
    });
    return res.json({ ok: true, data: items });
  } catch (err) {
    console.error('listItineraryItems error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
}

/**
 * POST /api/outings/:outingId/itinerary
 */
async function createItineraryItem(req, res) {
  try {
    const { outingId } = req.params;
    const me = getAuthUserId(req);
    if (!me) return res.status(401).json({ ok: false, error: 'AUTH_REQUIRED' });

    const outing = await prisma.outing.findUnique({ where: { id: outingId } });
    if (!outing) return res.status(404).json({ ok: false, error: 'OUTING_NOT_FOUND' });

    const { title, notes, locationName, latitude, longitude, startTime, endTime, orderIndex } = req.body || {};
    if (!title) return res.status(400).json({ ok: false, error: 'TITLE_REQUIRED' });

    const created = await prisma.itineraryItem.create({
      data: {
        outingId,
        title,
        notes: notes || null,
        locationName: locationName || null,
        latitude: latitude ?? null,
        longitude: longitude ?? null,
        startTime: startTime ? new Date(startTime) : null,
        endTime: endTime ? new Date(endTime) : null,
        orderIndex: Number.isFinite(Number(orderIndex)) ? Number(orderIndex) : 0,
      },
    });

    return res.status(201).json({ ok: true, data: created });
  } catch (err) {
    console.error('createItineraryItem error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
}

/**
 * PUT /api/outings/:outingId/itinerary/:itemId
 */
async function updateItineraryItem(req, res) {
  try {
    const { outingId, itemId } = req.params;
    const me = getAuthUserId(req);
    if (!me) return res.status(401).json({ ok: false, error: 'AUTH_REQUIRED' });

    const existing = await prisma.itineraryItem.findUnique({ where: { id: itemId } });
    if (!existing || existing.outingId !== outingId) {
      return res.status(404).json({ ok: false, error: 'ITEM_NOT_FOUND' });
    }

    const { title, notes, locationName, latitude, longitude, startTime, endTime, orderIndex } = req.body || {};

    const updated = await prisma.itineraryItem.update({
      where: { id: itemId },
      data: {
        ...(title !== undefined ? { title } : {}),
        ...(notes !== undefined ? { notes } : {}),
        ...(locationName !== undefined ? { locationName } : {}),
        ...(latitude !== undefined ? { latitude } : {}),
        ...(longitude !== undefined ? { longitude } : {}),
        ...(startTime !== undefined ? { startTime: startTime ? new Date(startTime) : null } : {}),
        ...(endTime !== undefined ? { endTime: endTime ? new Date(endTime) : null } : {}),
        ...(orderIndex !== undefined ? { orderIndex: Number(orderIndex) } : {}),
      },
    });

    return res.json({ ok: true, data: updated });
  } catch (err) {
    console.error('updateItineraryItem error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
}

/**
 * DELETE /api/outings/:outingId/itinerary/:itemId
 */
async function deleteItineraryItem(req, res) {
  try {
    const { outingId, itemId } = req.params;
    const me = getAuthUserId(req);
    if (!me) return res.status(401).json({ ok: false, error: 'AUTH_REQUIRED' });

    const existing = await prisma.itineraryItem.findUnique({ where: { id: itemId } });
    if (!existing || existing.outingId !== outingId) {
      return res.status(404).json({ ok: false, error: 'ITEM_NOT_FOUND' });
    }

    await prisma.itineraryItem.delete({ where: { id: itemId } });
    return res.json({ ok: true });
  } catch (err) {
    console.error('deleteItineraryItem error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
}

module.exports = {
  getSuggestedItinerary,
  listItineraryItems,
  createItineraryItem,
  updateItineraryItem,
  deleteItineraryItem,
};
