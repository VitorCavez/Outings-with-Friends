// backend/src/routes/messageRoutes.js
const express = require('express');
const router = express.Router();

// ✅ use the shared Prisma client
const prisma = require('../../prisma/client');
const { requireAuth } = require('../middleware/auth');

/** ---------------- Utilities ---------------- */
function parseLimit(q) {
  const n = Number(q?.limit ?? 20);
  if (!Number.isFinite(n) || n <= 0) return 20;
  return Math.min(n, 100);
}

function parseCursorDate(q) {
  const c = q?.cursor;
  if (!c) return null;
  const n = Number(c);
  if (Number.isFinite(n)) {
    const d = new Date(n);
    return isNaN(d.getTime()) ? null : d;
  }
  const d = new Date(c);
  return isNaN(d.getTime()) ? null : d;
}

/** Per-user Socket.IO room helper */
function toUser(io, userId) {
  return io.to(`user:${userId}`);
}

/* -------------------------------------------------------------------------- */
/*  RECENT THREADS (DMs + Group chats)                                        */
/*  GET /api/messages/recent?limit=30                                         */
/*  Auth: required. Uses req.user.userId.                                     */
/* -------------------------------------------------------------------------- */
router.get('/recent', requireAuth, async (req, res) => {
  try {
    const me = req.user.userId;
    const limit = parseLimit(req.query);

    // ---- Groups I belong to
    const memberships = await prisma.groupMembership.findMany({
      where: { userId: me },
      select: {
        groupId: true,
        group: { select: { id: true, name: true, coverImageUrl: true } },
      },
    });
    const groupIds = memberships.map(m => m.groupId);

    // Latest messages across those groups (sorted desc)
    const groupMsgs = groupIds.length
      ? await prisma.message.findMany({
          where: { groupId: { in: groupIds } },
          orderBy: { createdAt: 'desc' },
          take: Math.max(limit * 3, 60),
          include: {
            group: { select: { id: true, name: true, coverImageUrl: true } },
          },
        })
      : [];

    // Keep only newest per groupId
    const seenGroup = new Set();
    const groupThreads = [];
    for (const m of groupMsgs) {
      if (!m.groupId || seenGroup.has(m.groupId)) continue;
      seenGroup.add(m.groupId);
      groupThreads.push({
        kind: 'group',
        groupId: m.groupId,
        title: m.group?.name ?? m.groupId,
        avatarUrl: m.group?.coverImageUrl ?? null,
        lastText: m.text,
        lastAt: m.createdAt,
      });
      if (groupThreads.length >= limit) break;
    }

    // ---- Direct messages involving me (groupId null)
    const dmMsgs = await prisma.message.findMany({
      where: {
        groupId: null,
        OR: [{ senderId: me }, { recipientId: me }],
      },
      orderBy: { createdAt: 'desc' },
      take: Math.max(limit * 6, 120),
      include: {
        sender: { select: { id: true, fullName: true, profilePhotoUrl: true } },
        recipient: {
          select: { id: true, fullName: true, profilePhotoUrl: true },
        },
      },
    });

    // Keep only newest per peer
    const seenPeer = new Set();
    const dmThreads = [];
    for (const m of dmMsgs) {
      const peerId = m.senderId === me ? m.recipientId : m.senderId;
      if (!peerId || seenPeer.has(peerId)) continue;
      seenPeer.add(peerId);

      const peer =
        m.senderId === me ? m.recipient : m.sender; // the "other" user
      dmThreads.push({
        kind: 'dm',
        peerId,
        title: peer?.fullName || peerId,
        avatarUrl: peer?.profilePhotoUrl ?? null,
        lastText: m.text,
        lastAt: m.createdAt,
      });
      if (dmThreads.length >= limit) break;
    }

    // Merge and sort newest first
    const merged = [...groupThreads, ...dmThreads].sort(
      (a, b) => b.lastAt.getTime() - a.lastAt.getTime()
    );

    res.json({ ok: true, data: merged.slice(0, limit) });
  } catch (err) {
    console.error('recent threads error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/* ---------------- Existing endpoints (compat) ---------------- */

// POST /api/messages/group/:groupId — send to group
router.post('/group/:groupId', async (req, res) => {
  const { groupId } = req.params;
  const { senderId, text } = req.body;

  if (!senderId || !text) {
    return res.status(400).json({ error: 'senderId and text are required.' });
  }

  try {
    const message = await prisma.message.create({
      data: {
        groupId,
        senderId,
        text,
        messageType: 'text',  // default
      },
      select: {
        id: true, text: true, senderId: true, recipientId: true, groupId: true,
        createdAt: true, isRead: true,
        messageType: true, mediaUrl: true, fileName: true, fileSize: true, readAt: true,
      }
    });

    if (io) {
      io.to(`group:${groupId}`).emit('receive_message', {
        id: message.id,
        text: message.text,
        senderId: message.senderId,
        groupId: message.groupId,
        recipientId: null,
        createdAt: message.createdAt,
        isRead: message.isRead ?? false,
        messageType: message.messageType || 'text',
        mediaUrl: message.mediaUrl || null,
        fileName: message.fileName || null,
        fileSize: message.fileSize || null,
        readAt: message.readAt || null,
      });
    }

    res.status(201).json(message);
  } catch (error) {
    console.error('Send group message error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/messages/group/:groupId — legacy full list
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

// POST /api/messages — send direct message (DM)
router.post('/', async (req, res) => {
  const { senderId, recipientId, text } = req.body;

  if (!senderId || !recipientId || !text) {
    return res
      .status(400)
      .json({ error: 'senderId, recipientId, and text are required.' });
  }

  try {
    const message = await prisma.message.create({
      data: {
        senderId, recipientId, text,
        messageType: 'text',
      },
      select: {
        id: true, text: true, senderId: true, recipientId: true, groupId: true,
        createdAt: true, isRead: true,
        messageType: true, mediaUrl: true, fileName: true, fileSize: true, readAt: true,
      }
    });

    const payload = {
      id: message.id,
      text: message.text,
      senderId: message.senderId,
      recipientId: message.recipientId,
      groupId: null,
      createdAt: message.createdAt,
      isRead: message.isRead ?? false,
      messageType: message.messageType || 'text',
      mediaUrl: message.mediaUrl || null,
      fileName: message.fileName || null,
      fileSize: message.fileSize || null,
      readAt: message.readAt || null,
    };
    toUser(io, senderId).emit('receive_message', payload);
    toUser(io, recipientId).emit('receive_message', payload);

    res.status(201).json({ ok: true, message });
  } catch (error) {
    console.error('Send DM error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/* ---------------- New endpoints (pagination, typing, read) ---------------- */

// GET /api/messages/direct?peer=&currentUserId=&cursor=&limit=
router.get('/direct', async (req, res) => {
  const { peer } = req.query;
  const currentUserId = req.query.currentUserId;
  const limit = parseLimit(req.query);
  const cursorDate = parseCursorDate(req.query);

  if (!peer) return res.status(400).json({ error: 'peer is required' });
  if (!currentUserId)
    return res.status(400).json({ error: 'currentUserId is required' });

  try {
    const where = {
      OR: [
        { senderId: currentUserId, recipientId: peer },
        { senderId: peer, recipientId: currentUserId },
      ],
      ...(cursorDate ? { createdAt: { lt: cursorDate } } : {}),
    };

    const itemsDesc = await prisma.message.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: limit,
    });

    const items = itemsDesc.sort(
      (a, b) => a.createdAt.getTime() - b.createdAt.getTime()
    );
    const nextCursor = items.length ? items[0].createdAt.toISOString() : null;

    res.json({ items, nextCursor });
  } catch (err) {
    console.error('direct history error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/messages/group?groupId=&cursor=&limit=
router.get('/group', async (req, res) => {
  const { groupId } = req.query;
  const limit = parseLimit(req.query);
  const cursorDate = parseCursorDate(req.query);

  if (!groupId) return res.status(400).json({ error: 'groupId is required' });

  try {
    const where = {
      groupId,
      ...(cursorDate ? { createdAt: { lt: cursorDate } } : {}),
    };

    const itemsDesc = await prisma.message.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: limit,
    });

    const items = itemsDesc.sort(
      (a, b) => a.createdAt.getTime() - b.createdAt.getTime()
    );
    const nextCursor = items.length ? items[0].createdAt.toISOString() : null;

    res.json({ items, nextCursor });
  } catch (err) {
    console.error('group history error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /api/messages/typing
router.post('/typing', async (req, res) => {
  try {
    const { isTyping, recipientId, groupId, userId } = req.body || {};
    const io = req.app.get('io');
    if (!io) return res.status(500).json({ error: 'Socket not available' });

    if (recipientId) {
      toUser(io, recipientId).emit('typing', { isTyping: !!isTyping, userId });
    } else if (groupId) {
      io.to(`group:${groupId}`).emit('typing', {
        isTyping: !!isTyping,
        userId,
        groupId,
      });
    } else {
      io.emit('typing', { isTyping: !!isTyping, userId });
    }

    res.json({ ok: true });
  } catch (err) {
    console.error('typing route error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /api/messages/read
router.post('/read', async (req, res) => {
  const { messageId, readerId } = req.body || {};
  if (!messageId || !readerId) {
    return res
      .status(400)
      .json({ error: 'messageId and readerId are required' });
  }

  try {
    let updated;
    try {
      updated = await prisma.message.update({
        where: { id: messageId },
        data: { isRead: true, readAt: new Date() },
        select: { id: true, senderId: true, recipientId: true, groupId: true },
      });
    } catch {
      updated = await prisma.message.update({
        where: { id: messageId },
        data: { isRead: true },
        select: { id: true, senderId: true, recipientId: true, groupId: true },
      });
    }

    const io = req.app.get('io');
    if (io && updated) {
      if (updated.groupId) {
        io.emit('message_read', { messageId, readerId });
      } else {
        if (updated.senderId)
          toUser(io, updated.senderId).emit('message_read', {
            messageId,
            readerId,
          });
        if (updated.recipientId)
          toUser(io, updated.recipientId).emit('message_read', {
            messageId,
            readerId,
          });
      }
    }

    res.json({ ok: true });
  } catch (err) {
    console.error('read route error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
