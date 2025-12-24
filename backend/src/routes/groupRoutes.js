// backend/src/routes/groupRoutes.js
const express = require('express');
const router = express.Router({ mergeParams: true });
const { GroupRole } = require('@prisma/client');
const prisma = require('../../prisma/client');

const { requireAuth } = require('../middleware/auth'); // uses req.user.userId

// ---------- helpers ----------
async function isGroupAdminOrOwner(groupId, userId) {
  const g = await prisma.group.findUnique({
    where: { id: groupId },
    select: { createdById: true },
  });
  if (!g) return false;
  if (g.createdById === userId) return true;

  const m = await prisma.groupMembership.findFirst({
    where: { groupId, userId },
    select: { role: true, isAdmin: true },
  });

  return !!m && (m.role === 'admin' || m.isAdmin === true);
}

// ---------- CREATE ----------
/**
 * POST /api/groups
 * body: { name, description?, coverImageUrl?, visibility? }
 */
router.post('/', requireAuth, async (req, res) => {
  try {
    const me = req.user.userId;
    const { name, description, coverImageUrl, visibility } = req.body || {};
    if (!name) return res.status(400).json({ error: 'name is required' });

    const group = await prisma.group.create({
      data: {
        name,
        description: description ?? null,
        coverImageUrl: coverImageUrl ?? null,
        visibility: visibility ?? 'private',
        createdById: me,
      },
    });

    // Auto-join creator as admin (requires @@unique([userId, groupId]) in schema)
    await prisma.groupMembership.upsert({
      where: { userId_groupId: { userId: me, groupId: group.id } },
      update: { role: GroupRole.admin, isAdmin: true },
      create: { userId: me, groupId: group.id, role: GroupRole.admin, isAdmin: true },
    });

    res.status(201).json({ ok: true, data: group });
  } catch (err) {
    console.error('create group error:', err);
    res.status(500).json({ error: 'SERVER_ERROR' });
  }
});

// ---------- MY GROUPS (for Groups tab) ----------
/**
 * GET /api/groups/mine?limit=20&offset=0
 */
router.get('/mine', requireAuth, async (req, res) => {
  try {
    const me = req.user.userId;
    const limit = Math.min(parseInt(req.query.limit || '20', 10), 50);
    const offset = parseInt(req.query.offset || '0', 10);

    // Order memberships by the GROUP's createdAt (membership has no createdAt in your schema)
    let memberships;
    try {
      memberships = await prisma.groupMembership.findMany({
        where: { userId: me },
        orderBy: { group: { createdAt: 'desc' } }, // relation orderBy (Prisma supports this)
        include: {
          group: {
            select: {
              id: true,
              name: true,
              description: true,
              coverImageUrl: true,
              visibility: true,
              createdAt: true,
              createdById: true,
              _count: { select: { members: true } },
            },
          },
        },
        skip: offset,
        take: limit,
      });
    } catch {
      // Fallback if your Prisma version doesn’t like relation orderBy
      memberships = await prisma.groupMembership.findMany({
        where: { userId: me },
        orderBy: { id: 'desc' },
        include: {
          group: {
            select: {
              id: true,
              name: true,
              description: true,
              coverImageUrl: true,
              visibility: true,
              createdAt: true,
              createdById: true,
              _count: { select: { members: true } },
            },
          },
        },
        skip: offset,
        take: limit,
      });
    }

    const rows = memberships
      .map((m) =>
        m.group
          ? {
              ...m.group,
              myRole: m.role,
              myIsAdmin: !!m.isAdmin,
            }
          : null
      )
      .filter(Boolean);

    res.json({ ok: true, limit, offset, data: rows });
  } catch (err) {
    console.error('my groups error:', err);
    res.status(500).json({ error: 'SERVER_ERROR' });
  }
});

// ---------- DISCOVER ----------
/**
 * GET /api/groups/discover?q=term&visibility=public|private|invite_only&limit&offset
 */
router.get('/discover', async (req, res) => {
  try {
    const q = String(req.query.q || '').trim();
    const visibility = String(req.query.visibility || 'public').toLowerCase();
    const limit = Math.min(parseInt(req.query.limit || '20', 10), 50);
    const offset = parseInt(req.query.offset || '0', 10);

    const where = {
      visibility: ['public', 'private', 'invite_only'].includes(visibility)
        ? visibility
        : 'public',
      ...(q
        ? {
            OR: [
              { name: { contains: q, mode: 'insensitive' } },
              { description: { contains: q, mode: 'insensitive' } },
            ],
          }
        : {}),
    };

    const [total, rows] = await Promise.all([
      prisma.group.count({ where }),
      prisma.group.findMany({
        where,
        orderBy: [{ createdAt: 'desc' }],
        skip: offset,
        take: limit,
        select: {
          id: true,
          name: true,
          description: true,
          coverImageUrl: true,
          visibility: true,
          createdAt: true,
          createdById: true,
          _count: { select: { members: true } },
        },
      }),
    ]);

    res.json({ ok: true, total, limit, offset, data: rows });
  } catch (err) {
    console.error('discover groups error:', err);
    res.status(500).json({ error: 'SERVER_ERROR' });
  }
});

// ---------- UPDATE (owner/admin) ----------
/**
 * PATCH /api/groups/:groupId
 * body: { name?, description?, coverImageUrl?, visibility? }
 */
router.patch('/:groupId', requireAuth, async (req, res) => {
  try {
    const me = req.user.userId;
    const { groupId } = req.params;

    const can = await isGroupAdminOrOwner(groupId, me);
    if (!can) return res.status(403).json({ error: 'FORBIDDEN' });

    const { name, description, coverImageUrl, visibility } = req.body || {};

    const group = await prisma.group.update({
      where: { id: groupId },
      data: {
        ...(name !== undefined ? { name } : {}),
        ...(description !== undefined ? { description } : {}),
        ...(coverImageUrl !== undefined ? { coverImageUrl } : {}),
        ...(visibility !== undefined ? { visibility } : {}),
      },
    });

    res.json({ ok: true, data: group });
  } catch (err) {
    console.error('update group error:', err);
    if (String(err?.code) === 'P2025') {
      return res.status(404).json({ error: 'GROUP_NOT_FOUND' });
    }
    res.status(500).json({ error: 'SERVER_ERROR' });
  }
});

// ---------- GROUP PROFILE ----------
router.get('/:groupId/profile', async (req, res) => {
  try {
    const { groupId } = req.params;
    const g = await prisma.group.findUnique({
      where: { id: groupId },
      select: {
        id: true,
        name: true,
        description: true,
        coverImageUrl: true,
        visibility: true,
        createdAt: true,
        createdById: true,
        defaultBudgetMin: true,
        defaultBudgetMax: true,
        preferredOutingTypes: true,
        _count: { select: { members: true, outings: true } },
      },
    });
    if (!g) return res.status(404).json({ error: 'GROUP_NOT_FOUND' });
    res.json({ ok: true, data: g });
  } catch (err) {
    console.error('get group profile error:', err);
    res.status(500).json({ error: 'SERVER_ERROR' });
  }
});

router.put('/:groupId/profile', requireAuth, async (req, res) => {
  try {
    const me = req.user.userId;
    const { groupId } = req.params;
    const can = await isGroupAdminOrOwner(groupId, me);
    if (!can) return res.status(403).json({ error: 'FORBIDDEN' });

    const {
      name,
      description,
      coverImageUrl,
      visibility,
      defaultBudgetMin,
      defaultBudgetMax,
      preferredOutingTypes,
      groupImageUrl, // legacy → mapped
      groupVisibility, // legacy → mapped to visibility
    } = req.body || {};

    const updated = await prisma.group.update({
      where: { id: groupId },
      data: {
        ...(name !== undefined ? { name } : {}),
        ...(description !== undefined ? { description } : {}),
        ...(coverImageUrl !== undefined
          ? { coverImageUrl }
          : groupImageUrl !== undefined
          ? { coverImageUrl: groupImageUrl }
          : {}),
        ...(visibility !== undefined
          ? { visibility }
          : groupVisibility !== undefined
          ? { visibility: groupVisibility }
          : {}),
        ...(defaultBudgetMin !== undefined ? { defaultBudgetMin } : {}),
        ...(defaultBudgetMax !== undefined ? { defaultBudgetMax } : {}),
        ...(preferredOutingTypes !== undefined ? { preferredOutingTypes } : {}),
      },
      select: {
        id: true,
        name: true,
        description: true,
        coverImageUrl: true,
        visibility: true,
        defaultBudgetMin: true,
        defaultBudgetMax: true,
        preferredOutingTypes: true,
      },
    });

    res.json({ ok: true, data: updated });
  } catch (err) {
    console.error('update group profile error:', err);
    if (String(err?.code) === 'P2025') {
      return res.status(404).json({ error: 'GROUP_NOT_FOUND' });
    }
    res.status(500).json({ error: 'SERVER_ERROR' });
  }
});

// ---------- READ ----------
router.get('/', async (_req, res) => {
  try {
    const groups = await prisma.group.findMany({
      orderBy: [{ createdAt: 'desc' }],
    });
    res.json({ ok: true, data: groups });
  } catch (err) {
    console.error('list groups error:', err);
    res.status(500).json({ error: 'SERVER_ERROR' });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const group = await prisma.group.findUnique({
      where: { id },
      include: {
        _count: { select: { members: true, outings: true } },
      },
    });
    if (!group) return res.status(404).json({ error: 'GROUP_NOT_FOUND' });
    res.json({ ok: true, data: group });
  } catch (err) {
    console.error('get group error:', err);
    res.status(500).json({ error: 'SERVER_ERROR' });
  }
});

// ---------- MEMBERS ----------
router.get('/:groupId/members', async (req, res) => {
  try {
    const { groupId } = req.params;
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
      orderBy: [{ id: 'asc' }],
    });

    const data = members.map((m) => ({
      user: m.user,
      role: m.role,
      isAdminLegacy: m.isAdmin ?? false,
    }));

    res.json({ ok: true, data });
  } catch (err) {
    console.error('list members error:', err);
    res.status(500).json({ error: 'SERVER_ERROR' });
  }
});

router.post('/:groupId/join', requireAuth, async (req, res) => {
  try {
    const { groupId } = req.params;
    const userId = req.body?.userId || req.user.userId;

    const existing = await prisma.groupMembership.findFirst({
      where: { groupId, userId },
    });
    if (existing) {
      return res.status(409).json({ error: 'ALREADY_MEMBER' });
    }

    const mem = await prisma.groupMembership.create({
      data: {
        groupId,
        userId,
        role: GroupRole.member,
        isAdmin: false,
      },
    });

    res.status(201).json({ ok: true, data: mem });
  } catch (err) {
    console.error('join group error:', err);
    res.status(500).json({ error: 'SERVER_ERROR' });
  }
});

router.delete('/:groupId/members/:userId', requireAuth, async (req, res) => {
  try {
    const me = req.user.userId;
    const { groupId, userId } = req.params;

    const can = await isGroupAdminOrOwner(groupId, me);
    if (!can) return res.status(403).json({ error: 'FORBIDDEN' });

    await prisma.groupMembership.deleteMany({
      where: { groupId, userId },
    });

    res.json({ ok: true });
  } catch (err) {
    console.error('kick member error:', err);
    res.status(500).json({ error: 'SERVER_ERROR' });
  }
});

router.post('/:groupId/members/:userId/promote', requireAuth, async (req, res) => {
  try {
    const me = req.user.userId;
    const { groupId, userId } = req.params;

    const can = await isGroupAdminOrOwner(groupId, me);
    if (!can) return res.status(403).json({ error: 'FORBIDDEN' });

    const mem = await prisma.groupMembership.updateMany({
      where: { groupId, userId },
      data: { role: GroupRole.admin, isAdmin: true },
    });

    if (mem.count === 0) return res.status(404).json({ error: 'MEMBERSHIP_NOT_FOUND' });
    res.json({ ok: true });
  } catch (err) {
    console.error('promote error:', err);
    res.status(500).json({ error: 'SERVER_ERROR' });
  }
});

router.post('/:groupId/members/:userId/demote', requireAuth, async (req, res) => {
  try {
    const me = req.user.userId;
    const { groupId, userId } = req.params;

    const can = await isGroupAdminOrOwner(groupId, me);
    if (!can) return res.status(403).json({ error: 'FORBIDDEN' });

    const mem = await prisma.groupMembership.updateMany({
      where: { groupId, userId },
      data: { role: GroupRole.member, isAdmin: false },
    });

    if (mem.count === 0) return res.status(404).json({ error: 'MEMBERSHIP_NOT_FOUND' });
    res.json({ ok: true });
  } catch (err) {
    console.error('demote error:', err);
    res.status(500).json({ error: 'SERVER_ERROR' });
  }
});

// ---------- DELETE GROUP (owner only) ----------
router.delete('/:id', requireAuth, async (req, res) => {
  try {
    const me = req.user.userId;
    const { id } = req.params;

    const g = await prisma.group.findUnique({ where: { id }, select: { createdById: true } });
    if (!g) return res.status(404).json({ error: 'GROUP_NOT_FOUND' });
    if (g.createdById !== me) return res.status(403).json({ error: 'FORBIDDEN' });

    await prisma.groupMembership.deleteMany({ where: { groupId: id } });
    const deletedGroup = await prisma.group.delete({ where: { id } });

    res.json({ ok: true, data: deletedGroup });
  } catch (err) {
    console.error('delete group error:', err);
    res.status(500).json({ error: 'SERVER_ERROR' });
  }
});

// Leave (or effectively "delete for me") a group.
// If it was the last member, the group record is removed.
router.post('/:groupId/leave', requireAuth, async (req, res) => {
  try {
    const userId = req.user?.userId;
    const { groupId } = req.params;

    if (!userId) return res.status(401).json({ error: 'AUTH_REQUIRED' });

    const membership = await prisma.groupMembership.findFirst({
      where: { userId, groupId },
    });

    if (!membership) {
      return res.status(404).json({ error: 'NOT_A_MEMBER' });
    }

    await prisma.groupMembership.delete({ where: { id: membership.id } });

    // Optional: if group is now empty, delete it entirely
    const remaining = await prisma.groupMembership.count({ where: { groupId } });
    if (remaining === 0) {
      await prisma.group.delete({ where: { id: groupId } });
    }

    return res.json({ ok: true });
  } catch (err) {
    console.error('leave group error:', err);
    return res.status(500).json({ error: 'SERVER_ERROR' });
  }
});

module.exports = router;
