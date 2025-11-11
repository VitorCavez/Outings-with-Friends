// backend/src/routes/profileRoutes.js

const express = require('express');
const router = express.Router();

const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

/**
 * GET /api/users/:userId/history
 * Past outings the user hosted or RSVP'd to (dateTimeEnd < now).
 * Query params:
 *  - role=host|guest|all (default: all)
 *  - limit (default 25), offset (default 0)
 */
router.get('/api/users/:userId/history', async (req, res) => {
  try {
    const { userId } = req.params;
    const role = String(req.query.role || 'all').toLowerCase();
    const limit = Math.min(parseInt(req.query.limit || '25', 10), 100);
    const offset = parseInt(req.query.offset || '0', 10);
    const now = new Date();

    // host: outings created by user
    // guest: outings where OutingUser exists for user
    // all: union of both
    const hostWhere = {
      createdById: userId,
      dateTimeEnd: { lt: now },
    };

    const guestOutingIds = await prisma.outingUser.findMany({
      where: { userId },
      select: { outingId: true },
    });
    const guestIds = [...new Set(guestOutingIds.map((r) => r.outingId))];

    let where;
    if (role === 'host') {
      where = hostWhere;
    } else if (role === 'guest') {
      where = { id: { in: guestIds }, dateTimeEnd: { lt: now } };
    } else {
      // all
      where = {
        OR: [
          hostWhere,
          { id: { in: guestIds }, dateTimeEnd: { lt: now } },
        ],
      };
    }

    const [total, rows] = await Promise.all([
      prisma.outing.count({ where }),
      prisma.outing.findMany({
        where,
        orderBy: [{ dateTimeEnd: 'desc' }],
        skip: offset,
        take: limit,
        select: {
          id: true,
          title: true,
          description: true,
          outingType: true,
          locationName: true,
          latitude: true,
          longitude: true,
          address: true,
          dateTimeStart: true,
          dateTimeEnd: true,
          createdById: true,
          groupId: true,
        },
      }),
    ]);

    // annotate role + rsvp for clarity
    const rsvpMap = new Map();
    if (guestIds.length) {
      const rsvps = await prisma.outingUser.findMany({
        where: { userId, outingId: { in: rows.map((r) => r.id) } },
        select: { outingId: true, rsvpStatus: true },
      });
      rsvps.forEach((r) => rsvpMap.set(r.outingId, r.rsvpStatus));
    }

    const data = rows.map((o) => ({
      ...o,
      role:
        o.createdById === userId
          ? 'host'
          : guestIds.includes(o.id)
          ? 'guest'
          : 'unknown',
      rsvpStatus: rsvpMap.get(o.id) || null,
    }));

    res.json({ ok: true, total, limit, offset, data });
  } catch (err) {
    console.error('history error:', err);
    res.status(500).json({ ok: false, error: 'Failed to load user history' });
  }
});

/**
 * GET /api/users/:userId/timeline
 * Returns the user's calendar entries (descending by start time).
 * Query params:
 *  - from, to (ISO date strings, optional): filters by start time window
 *  - limit (default 50), offset (default 0)
 */
router.get('/api/users/:userId/timeline', async (req, res) => {
  try {
    const { userId } = req.params;
    const limit = Math.min(parseInt(req.query.limit || '50', 10), 200);
    const offset = parseInt(req.query.offset || '0', 10);

    const from = req.query.from ? new Date(String(req.query.from)) : null;
    const to = req.query.to ? new Date(String(req.query.to)) : null;

    const where = {
      createdByUserId: userId,
      ...(from ? { dateTimeStart: { gte: from } } : {}),
      ...(to ? { dateTimeStart: { lte: to } } : {}),
    };

    const [total, entries] = await Promise.all([
      prisma.calendarEntry.count({ where }),
      prisma.calendarEntry.findMany({
        where,
        orderBy: [{ dateTimeStart: 'desc' }],
        skip: offset,
        take: limit,
        select: {
          id: true,
          title: true,
          description: true,
          dateTimeStart: true,
          dateTimeEnd: true,
          isAllDay: true,
          isReminder: true,
          linkedOutingId: true,
          groupId: true,
          createdAt: true,
        },
      }),
    ]);

    // hydrate linked outing basics (if any)
    const linkedIds = [
      ...new Set(entries.map((e) => e.linkedOutingId).filter(Boolean)),
    ];

    const outingsById =
      linkedIds.length > 0
        ? new Map(
            (
              await prisma.outing.findMany({
                where: { id: { in: linkedIds } },
                select: {
                  id: true,
                  title: true,
                  outingType: true,
                  locationName: true,
                  address: true,
                  dateTimeStart: true,
                  dateTimeEnd: true,
                },
              })
            ).map((o) => [o.id, o])
          )
        : new Map();

    const data = entries.map((e) => ({
      ...e,
      linkedOuting: e.linkedOutingId ? outingsById.get(e.linkedOutingId) || null : null,
    }));

    res.json({ ok: true, total, limit, offset, data });
  } catch (err) {
    console.error('timeline error:', err);
    res.status(500).json({ ok: false, error: 'Failed to load user timeline' });
  }
});

/**
 * GET /api/users/:userId/favorites
 * Placeholder — returns 501 until a small favorites table is added.
 *
 * Proposed model (Prisma):
 * model Favorite {
 *   id        String   @id @default(uuid())
 *   userId    String
 *   outingId  String
 *   createdAt DateTime @default(now())
 *   user   User   @relation(fields: [userId], references: [id], onDelete: Cascade)
 *   outing Outing @relation(fields: [outingId], references: [id], onDelete: Cascade)
 *   @@unique([userId, outingId])
 *   @@index([outingId])
 * }
 */
router.get('/api/users/:userId/favorites', async (req, res) => {
  res.status(501).json({
    ok: false,
    error: 'Favorites not implemented',
    nextStep:
      'Add a Favorite model to Prisma (see suggested schema in code comment), run migration, then implement this route.',
  });
});

const express = require('express');
const router = express.Router();

router.get('/api/profile/me', async (req, res) => {
  try {
    res.json({ id: null, name: null, avatarUrl: null });
  } catch (err) {
    console.error('profileRoutes error:', err);
    res.status(500).json({ error: 'Failed to load profile' });
  }
});

router.patch('/api/profile/me', async (req, res) => {
  try {
    res.json({ ok: true, updated: req.body || {} });
  } catch (err) {
    console.error('profileRoutes update error:', err);
    res.status(500).json({ error: 'Failed to update profile' });
  }
});

module.exports = router;
