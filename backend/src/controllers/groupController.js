// backend/src/controllers/groupController.js
const prisma = require('../../prisma/client');
const { GroupRole } = require('@prisma/client');

// Create new group (creator from auth)
exports.createGroup = async (req, res) => {
  try {
    const me = req.user?.userId;
    if (!me) return res.status(401).json({ error: 'unauthorized' });

    const { name, description } = req.body || {};
    if (!name) return res.status(400).json({ error: 'name_required' });

    const group = await prisma.group.create({
      data: { name, description: description ?? null, createdById: me, visibility: 'private' },
    });

    // Auto-join creator as admin
    await prisma.groupMembership.create({
      data: { groupId: group.id, userId: me, role: GroupRole.admin, isAdmin: true },
    });

    return res.status(201).json(group);
  } catch (err) {
    console.error('Create Group Error:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

// Get all groups (admin/debug; UI should use /api/groups/me)
exports.getAllGroups = async (_req, res) => {
  try {
    const groups = await prisma.group.findMany({ include: { createdBy: true } });
    res.status(200).json(groups);
  } catch (err) {
    console.error('Get Groups Error:', err);
    res.status(500).json({ error: 'Server error' });
  }
};
