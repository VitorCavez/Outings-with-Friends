const express = require('express');
const router = express.Router();
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

/**
 * Utilities
 */
function parseLimit(q) {
  const n = Number(q?.limit ?? 20);
  if (!Number.isFinite(n) || n <= 0) return 20;
  return Math.min(n, 100);
}

function parseCursorDate(q) {
  // Accept ISO string or unix ms
  const c = q?.cursor;
  if (!c) return null;
  const n = Number(c);
  if (Number.isFinite(n)) {
    try { return new Date(n); } catch { return null; }
  }
  const d = new Date(c);
  return isNaN(d.getTime()) ? null : d;
}

/**
 * Emit helper (uses per-user rooms: user:<id>)
 */
function toUser(io, userId) {
  return io.to(`user:${userId}`);
}

/* ---------------------------------------------------
   Existing endpoints (kept for compatibility)
--------------------------------------------------- */

// ✅ POST /api/messages/group/:groupId — Send a message to a group
router.post('/group/:groupId', async (req, res) => {
  const { groupId } = req.params;
  const { senderId, text } = req.body;

  if (!senderId || !text) {
    return res.status(400).json({ error: 'senderId and text are required.' });
  }

  try {
    const message = await prisma.message.create({
      data: { groupId, senderId, text },
    });

    // Optional: emit to group room if you join sockets to group:<id>
    const io = req.app.get('io');
    if (io) {
      io.to(`group:${groupId}`).emit('receive_message', {
        id: message.id,
        text: message.text,
        senderId: message.senderId,
        groupId: message.groupId,
        recipientId: null,
        createdAt: message.createdAt,
        isRead: false,
      });
    }

    res.status(201).json(message);
  } catch (error) {
    console.error('Send group message error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ✅ GET /api/messages/group/:groupId — Fetch ALL messages (legacy)
router.get('/group/:groupId', async (req, res) => {
  const { groupId } = req.params;

  try {
    const messages = await prisma.message.findMany({
      where: { groupId },
      orderBy: { createdAt: 'asc' },
      include: {
        sender: { select: { id: true, fullName: true, profilePhotoUrl: true } },
      },
    });

    res.json(messages);
  } catch (error) {
    console.error('Fetch group messages error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ✅ POST /api/messages — Send a direct message (DM)
router.post('/', async (req, res) => {
  const { senderId, recipientId, text } = req.body;

  if (!senderId || !recipientId || !text) {
    return res
      .status(400)
      .json({ error: 'senderId, recipientId, and text are required.' });
  }

  try {
    const message = await prisma.message.create({
      data: { senderId, recipientId, text },
    });

    // Emit to both participants
    const io = req.app.get('io');
    if (io) {
      toUser(io, senderId).emit('receive_message', {
        id: message.id,
        text: message.text,
        senderId: message.senderId,
        recipientId: message.recipientId,
        groupId: null,
        createdAt: message.createdAt,
        isRead: false,
      });
      toUser(io, recipientId).emit('receive_message', {
        id: message.id,
        text: message.text,
        senderId: message.senderId,
        recipientId: message.recipientId,
        groupId: null,
        createdAt: message.createdAt,
        isRead: false,
      });
    }

    res.status(201).json({ message: 'Direct message sent', message });
  } catch (error) {
    console.error('Send DM error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/* ---------------------------------------------------
   New endpoints (pagination, typing, read receipts)
--------------------------------------------------- */

/**
 * GET /api/messages/direct
 * Query: peer=<userId>&cursor=<isoOrMs>&limit=<n>
 * Returns newest messages up to `limit`, filtered by createdAt < cursor (if provided).
 * Sorted ASC to render in chronological order.
 */
router.get('/direct', async (req, res) => {
  const { peer } = req.query;
  const currentUserId = req.query.currentUserId; // optional (for shaping UI)
  const limit = parseLimit(req.query);
  const cursorDate = parseCursorDate(req.query);

  if (!peer) return res.status(400).json({ error: 'peer is required' });

  try {
    const where = {
      OR: [
        { senderId: currentUserId, recipientId: peer },
        { senderId: peer, recipientId: currentUserId },
      ],
    };

    if (cursorDate) {
      where.createdAt = { lt: cursorDate };
    }

    const items = await prisma.message.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: limit,
    });

    const result = items.sort((a, b) => a.createdAt - b.createdAt);

    // Next cursor is oldest createdAt of this page
    const nextCursor =
      result.length > 0 ? result[0].createdAt.toISOString() : null;

    res.json({ items: result, nextCursor });
  } catch (err) {
    console.error('direct history error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * GET /api/messages/group
 * Query: groupId=<id>&cursor=<isoOrMs>&limit=<n>
 */
router.get('/group', async (req, res) => {
  const { groupId } = req.query;
  const limit = parseLimit(req.query);
  const cursorDate = parseCursorDate(req.query);

  if (!groupId) return res.status(400).json({ error: 'groupId is required' });

  try {
    const where = { groupId };
    if (cursorDate) {
      where.createdAt = { lt: cursorDate };
    }

    const items = await prisma.message.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: limit,
    });

    const result = items.sort((a, b) => a.createdAt - b.createdAt);
    const nextCursor =
      result.length > 0 ? result[0].createdAt.toISOString() : null;

    res.json({ items: result, nextCursor });
  } catch (err) {
    console.error('group history error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * POST /api/messages/typing
 * Body: { isTyping: boolean, recipientId?: string, groupId?: string, userId?: string }
 * Mirrors the socket "typing" event (useful for Postman/manual testing).
 */
router.post('/typing', async (req, res) => {
  try {
    const { isTyping, recipientId, groupId, userId } = req.body || {};
    const io = req.app.get('io');
    if (!io) return res.status(500).json({ error: 'Socket not available' });

    if (recipientId) {
      toUser(io, recipientId).emit('typing', { isTyping: !!isTyping, userId });
    } else if (groupId) {
      io.to(`group:${groupId}`).emit('typing', { isTyping: !!isTyping, userId, groupId });
    } else {
      io.emit('typing', { isTyping: !!isTyping, userId });
    }

    res.json({ ok: true });
  } catch (err) {
    console.error('typing route error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * POST /api/messages/read
 * Body: { messageId, readerId }
 * - Marks message read (simple 1:1: set isRead=true)
 * - Emits `message_read` to participants (sender + recipient),
 *   or global emit if unsure (works with your current client).
 */
router.post('/read', async (req, res) => {
  const { messageId, readerId } = req.body || {};
  if (!messageId || !readerId) {
    return res.status(400).json({ error: 'messageId and readerId are required' });
  }

  try {
    // Update read state
    let updated;
    try {
      updated = await prisma.message.update({
        where: { id: messageId },
        data: { isRead: true, readAt: new Date() },
        select: { id: true, senderId: true, recipientId: true, groupId: true },
      });
    } catch (e) {
      // Fallback if schema has no readAt
      updated = await prisma.message.update({
        where: { id: messageId },
        data: { isRead: true },
        select: { id: true, senderId: true, recipientId: true, groupId: true },
      });
    }

    // Emit to relevant users
    const io = req.app.get('io');
    if (io && updated) {
      if (updated.groupId) {
        // If you maintain group rooms: io.to(`group:${updated.groupId}`)...
        io.emit('message_read', { messageId, readerId });
      } else {
        // direct: notify sender + recipient
        if (updated.senderId) toUser(io, updated.senderId).emit('message_read', { messageId, readerId });
        if (updated.recipientId) toUser(io, updated.recipientId).emit('message_read', { messageId, readerId });
      }
    }

    res.json({ ok: true });
  } catch (err) {
    console.error('read route error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
