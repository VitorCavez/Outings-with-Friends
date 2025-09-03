const express = require('express');
const router = express.Router();
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

// ✅ POST /api/dm - Send a direct message
router.post('/', async (req, res) => {
  const { senderId, recipientId, text } = req.body;

  if (!senderId || !recipientId || !text) {
    return res.status(400).json({ error: 'senderId, recipientId, and text are required.' });
  }

  try {
    const message = await prisma.message.create({
      data: {
        senderId,
        recipientId,
        text,
      },
    });

    res.status(201).json({ message: 'Message sent', message });
  } catch (error) {
    console.error('Send DM error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ✅ GET /api/dm/:user1Id/:user2Id - Get all DMs between two users
router.get('/:user1Id/:user2Id', async (req, res) => {
  const { user1Id, user2Id } = req.params;

  try {
    const messages = await prisma.message.findMany({
      where: {
        OR: [
          { senderId: user1Id, recipientId: user2Id },
          { senderId: user2Id, recipientId: user1Id },
        ],
      },
      orderBy: { createdAt: 'asc' },
      include: {
        sender: {
          select: { id: true, fullName: true, profilePhotoUrl: true }
        }
      }
    });

    res.json(messages);
  } catch (error) {
    console.error('Fetch DMs error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
