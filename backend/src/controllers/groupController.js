const prisma = require('../../prisma/client');

// Create new group
exports.createGroup = async (req, res) => {
  try {
    const { name, description, createdById } = req.body;

    if (!name || !createdById) {
      return res.status(400).json({ error: 'Missing required fields.' });
    }

    const group = await prisma.group.create({
      data: {
        name,
        description,
        createdById,
      },
    });

    res.status(201).json(group);
  } catch (err) {
    console.error('Create Group Error:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

// Get all groups
exports.getAllGroups = async (req, res) => {
  try {
    const groups = await prisma.group.findMany({
      include: { createdBy: true },
    });
    res.status(200).json(groups);
  } catch (err) {
    console.error('Get Groups Error:', err);
    res.status(500).json({ error: 'Server error' });
  }
};
