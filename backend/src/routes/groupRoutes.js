const express = require('express');
const router = express.Router();
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

// ✅ POST /api/groups - Create a group
const { requireFields } = require('../utils/validators');

router.post('/:groupId/join', async (req, res) => {
  const { groupId } = req.params;
  const { userId, isAdmin = false } = req.body;

  if (!groupId || !userId) {
    return res.status(400).json({ error: 'Both groupId and userId are required.' });
  }

  try {
    const existing = await prisma.groupMembership.findFirst({
      where: { groupId, userId },
    });

    if (existing) {
      return res.status(409).json({ error: 'User already in group.' });
    }

    const membership = await prisma.groupMembership.create({
      data: { groupId, userId, isAdmin },
    });

    res.status(201).json({ message: 'User joined group.', membership });
  } catch (error) {
    console.error('Join group error:', error);
    res.status(500).json({ error: 'Internal server error.' });
  }
});


// ✅ GET /api/groups - List all groups
router.get('/', async (req, res) => {
  try {
    const groups = await prisma.group.findMany();
    res.json(groups);
  } catch (error) {
    console.error('Fetch all groups error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ✅ POST /api/groups/:groupId/join - Join a group
router.post('/:groupId/join', async (req, res) => {
  const { groupId } = req.params;
  const { userId, isAdmin = false } = req.body;

  if (!userId) {
    return res.status(400).json({ error: 'User ID is required.' });
  }

  try {
    const existing = await prisma.groupMembership.findFirst({
      where: { groupId, userId },
    });

    if (existing) {
      return res.status(409).json({ error: 'User already in group.' });
    }

    const membership = await prisma.groupMembership.create({
      data: { groupId, userId, isAdmin },
    });

    res.status(201).json({ message: 'User joined group.', membership });
  } catch (error) {
    console.error('Join group error:', error);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

// ✅ GET /api/groups/:groupId/members - List group members
router.get('/:groupId/members', async (req, res) => {
  const { groupId } = req.params;

  try {
    const members = await prisma.groupMembership.findMany({
      where: { groupId },
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

    res.json(members.map(m => m.user));
  } catch (error) {
    console.error('Fetch group members error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ✅ GET /api/groups/:id - Get group by ID
router.get('/:id', async (req, res) => {
  const { id } = req.params;
  try {
    const group = await prisma.group.findUnique({
      where: { id },
    });

    if (!group) {
      return res.status(404).json({ error: 'Group not found' });
    }

    res.json(group);
  } catch (error) {
    console.error('Fetch group by ID error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ✅ DELETE /api/groups/:id - Delete a group by ID
router.delete('/:id', async (req, res) => {
  const { id } = req.params;

  try {
    // Optional: delete related memberships first
    await prisma.groupMembership.deleteMany({ where: { groupId: id } });

    // Delete the group itself
    const deletedGroup = await prisma.group.delete({
      where: { id },
    });

    res.json({ message: 'Group deleted successfully', deletedGroup });
  } catch (error) {
    console.error('Delete group error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
