// backend/src/controllers/groupSocialController.js
const { PrismaClient, GroupRole, InviteStatus } = require('@prisma/client');
const prisma = new PrismaClient();

// Replace with your real auth extraction
function getAuthUserId(req) {
  return req.user?.id || req.headers['x-user-id'] || null;
}

// ---------- Helpers ----------
async function ensureGroupAdmin(groupId, userId) {
  const gm = await prisma.groupMembership.findFirst({
    where: { groupId, userId },
    select: { role: true },
  });
  if (!gm || gm.role !== 'admin') {
    const err = new Error('FORBIDDEN');
    err.status = 403;
    throw err;
  }
}

async function ensureMember(groupId, userId) {
  const gm = await prisma.groupMembership.findFirst({
    where: { groupId, userId },
    select: { id: true },
  });
  if (!gm) {
    const err = new Error('FORBIDDEN');
    err.status = 403;
    throw err;
  }
}

function ok(res, data) {
  return res.json({ ok: true, data });
}
function fail(res, code = 500, message = 'SERVER_ERROR') {
  return res.status(code).json({ ok: false, error: message });
}

// ---------- Profile ----------
exports.getGroupProfile = async (req, res) => {
  try {
    const { groupId } = req.params;
    const g = await prisma.group.findUnique({
      where: { id: groupId },
      select: {
        id: true,
        name: true,
        description: true,
        groupImageUrl: true,
        groupVisibility: true,
        createdAt: true,
      },
    });
    if (!g) return fail(res, 404, 'GROUP_NOT_FOUND');
    return ok(res, g);
  } catch (err) {
    console.error('getGroupProfile error:', err);
    return fail(res);
  }
};

exports.updateGroupProfile = async (req, res) => {
  try {
    const { groupId } = req.params;
    const me = getAuthUserId(req);
    if (!me) return fail(res, 401, 'AUTH_REQUIRED');

    await ensureGroupAdmin(groupId, me);

    const { name, description, groupImageUrl, groupVisibility } = req.body || {};
    const data = {};
    if (name != null) data.name = String(name);
    if (description != null) data.description = String(description);
    if (groupImageUrl != null) data.groupImageUrl = String(groupImageUrl);
    if (groupVisibility != null) data.groupVisibility = String(groupVisibility); // "public" | "private"

    const updated = await prisma.group.update({
      where: { id: groupId },
      data,
      select: {
        id: true, name: true, description: true, groupImageUrl: true, groupVisibility: true, createdAt: true,
      },
    });
    return ok(res, updated);
  } catch (err) {
    console.error('updateGroupProfile error:', err);
    return fail(res, err.status || 500, err.message || 'SERVER_ERROR');
  }
};

// ---------- Members & Roles ----------
exports.listMembers = async (req, res) => {
  try {
    const { groupId } = req.params;
    const members = await prisma.groupMembership.findMany({
      where: { groupId },
      select: {
        userId: true,
        role: true,
        joinedAt: true,
        user: { select: { id: true, fullName: true, username: true, profilePhotoUrl: true } },
      },
      orderBy: [{ role: 'desc' }, { joinedAt: 'asc' }], // admins first
    });
    return ok(res, members);
  } catch (err) {
    console.error('listMembers error:', err);
    return fail(res);
  }
};

exports.updateMemberRole = async (req, res) => {
  try {
    const { groupId, userId } = req.params;
    const me = getAuthUserId(req);
    if (!me) return fail(res, 401, 'AUTH_REQUIRED');

    await ensureGroupAdmin(groupId, me);

    const { role } = req.body || {};
    if (!role || !['member', 'admin'].includes(role)) {
      return fail(res, 400, 'INVALID_ROLE');
    }

    const updated = await prisma.groupMembership.updateMany({
      where: { groupId, userId },
      data: { role },
    });
    if (updated.count === 0) return fail(res, 404, 'MEMBERSHIP_NOT_FOUND');

    return ok(res, { groupId, userId, role });
  } catch (err) {
    console.error('updateMemberRole error:', err);
    return fail(res, err.status || 500, err.message || 'SERVER_ERROR');
  }
};

exports.leaveGroup = async (req, res) => {
  try {
    const { groupId } = req.params;
    const me = getAuthUserId(req);
    if (!me) return fail(res, 401, 'AUTH_REQUIRED');

    const gm = await prisma.groupMembership.findFirst({ where: { groupId, userId: me } });
    if (!gm) return fail(res, 404, 'NOT_A_MEMBER');

    // Optional: prevent last admin from leaving if members remain
    if (gm.role === 'admin') {
      const admins = await prisma.groupMembership.count({ where: { groupId, role: 'admin' } });
      const members = await prisma.groupMembership.count({ where: { groupId } });
      if (admins <= 1 && members > 1) {
        return fail(res, 400, 'LAST_ADMIN_CANNOT_LEAVE');
      }
    }

    await prisma.groupMembership.delete({ where: { id: gm.id } });
    return ok(res, { left: true });
  } catch (err) {
    console.error('leaveGroup error:', err);
    return fail(res);
  }
};

// ---------- Invitations ----------
exports.listInvites = async (req, res) => {
  try {
    const { groupId } = req.params;
    const me = getAuthUserId(req);
    if (!me) return fail(res, 401, 'AUTH_REQUIRED');

    await ensureGroupAdmin(groupId, me);

    const invites = await prisma.groupInvite.findMany({
      where: { groupId },
      orderBy: [{ createdAt: 'desc' }],
      select: {
        id: true, token: true, status: true, inviteeEmail: true, inviteeUserId: true,
        createdAt: true, expiresAt: true, acceptedAt: true, declinedAt: true, canceledAt: true,
        invitedBy: { select: { id: true, fullName: true, username: true } },
        invitee: { select: { id: true, fullName: true, username: true, profilePhotoUrl: true } },
      },
    });
    return ok(res, invites);
  } catch (err) {
    console.error('listInvites error:', err);
    return fail(res);
  }
};

exports.createInvite = async (req, res) => {
  try {
    const { groupId } = req.params;
    const me = getAuthUserId(req);
    if (!me) return fail(res, 401, 'AUTH_REQUIRED');

    await ensureGroupAdmin(groupId, me);

    const { inviteeUserId, inviteeEmail, message, expiresInHours = 168 } = req.body || {};
    if (!inviteeUserId && !inviteeEmail) return fail(res, 400, 'INVITEE_REQUIRED');

    const token = cryptoRandom();
    const expiresAt = new Date(Date.now() + Number(expiresInHours) * 3600 * 1000);

    const inv = await prisma.groupInvite.create({
      data: {
        groupId,
        invitedById: me,
        inviteeUserId: inviteeUserId || null,
        inviteeEmail: inviteeEmail || null,
        token,
        message: message || null,
        expiresAt,
      },
      select: {
        id: true, token: true, status: true, inviteeEmail: true, inviteeUserId: true, expiresAt: true, createdAt: true,
      },
    });

    // TODO: optional email/notification dispatch here

    return res.status(201).json({ ok: true, data: inv });
  } catch (err) {
    console.error('createInvite error:', err);
    return fail(res);
  }
};

exports.acceptInvite = async (req, res) => {
  try {
    const { inviteId } = req.params;
    const me = getAuthUserId(req);
    if (!me) return fail(res, 401, 'AUTH_REQUIRED');

    const inv = await prisma.groupInvite.findUnique({ where: { id: inviteId } });
    if (!inv) return fail(res, 404, 'INVITE_NOT_FOUND');

    return acceptInviteCore(inv, me, res);
  } catch (err) {
    console.error('acceptInvite error:', err);
    return fail(res);
  }
};

exports.declineInvite = async (req, res) => {
  try {
    const { inviteId } = req.params;
    const me = getAuthUserId(req);
    if (!me) return fail(res, 401, 'AUTH_REQUIRED');

    const inv = await prisma.groupInvite.findUnique({ where: { id: inviteId } });
    if (!inv) return fail(res, 404, 'INVITE_NOT_FOUND');

    return declineInviteCore(inv, me, res);
  } catch (err) {
    console.error('declineInvite error:', err);
    return fail(res);
  }
};

exports.cancelInvite = async (req, res) => {
  try {
    const { inviteId } = req.params;
    const me = getAuthUserId(req);
    if (!me) return fail(res, 401, 'AUTH_REQUIRED');

    const inv = await prisma.groupInvite.findUnique({ where: { id: inviteId } });
    if (!inv) return fail(res, 404, 'INVITE_NOT_FOUND');

    await ensureGroupAdmin(inv.groupId, me);

    if (inv.status !== 'pending') return fail(res, 400, 'INVITE_NOT_PENDING');

    const updated = await prisma.groupInvite.update({
      where: { id: inv.id },
      data: { status: 'canceled', canceledAt: new Date() },
    });

    return ok(res, updated);
  } catch (err) {
    console.error('cancelInvite error:', err);
    return fail(res);
  }
};

exports.acceptInviteByToken = async (req, res) => {
  try {
    const { token } = req.params;
    const me = getAuthUserId(req);
    if (!me) return fail(res, 401, 'AUTH_REQUIRED');

    const inv = await prisma.groupInvite.findUnique({ where: { token } });
    if (!inv) return fail(res, 404, 'INVITE_NOT_FOUND');

    return acceptInviteCore(inv, me, res);
  } catch (err) {
    console.error('acceptInviteByToken error:', err);
    return fail(res);
  }
};

exports.declineInviteByToken = async (req, res) => {
  try {
    const { token } = req.params;
    const me = getAuthUserId(req);
    if (!me) return fail(res, 401, 'AUTH_REQUIRED');

    const inv = await prisma.groupInvite.findUnique({ where: { token } });
    if (!inv) return fail(res, 404, 'INVITE_NOT_FOUND');

    return declineInviteCore(inv, me, res);
  } catch (err) {
    console.error('declineInviteByToken error:', err);
    return fail(res);
  }
};

// ---------- Discovery ----------
exports.discoverGroups = async (req, res) => {
  try {
    const { q, limit = 25, offset = 0 } = req.query;
    const rows = await prisma.group.findMany({
      where: {
        groupVisibility: 'public',
        ...(q ? { OR: [
          { name: { contains: String(q), mode: 'insensitive' } },
          { description: { contains: String(q), mode: 'insensitive' } },
        ] } : {}),
      },
      orderBy: [{ createdAt: 'desc' }],
      skip: Number(offset) || 0,
      take: Math.min(Number(limit) || 25, 100),
      select: { id: true, name: true, description: true, groupImageUrl: true, createdAt: true },
    });
    return ok(res, rows);
  } catch (err) {
    console.error('discoverGroups error:', err);
    return fail(res);
  }
};

// ---------- Internals ----------
function cryptoRandom() {
  // small, URL-friendly token
  return require('crypto').randomBytes(16).toString('hex');
}

async function acceptInviteCore(inv, me, res) {
  if (inv.status !== 'pending') return fail(res, 400, 'INVITE_NOT_PENDING');
  if (inv.expiresAt && inv.expiresAt < new Date()) return fail(res, 400, 'INVITE_EXPIRED');

  // If invite was targeted to a specific user/email, enforce it
  if (inv.inviteeUserId && inv.inviteeUserId !== me) return fail(res, 403, 'INVITE_NOT_FOR_YOU');

  // Join group (idempotent)
  await prisma.groupMembership.upsert({
    where: {
      // emulate compound (groupId,userId) uniqueness:
      // create a @@unique([groupId, userId]) if you want strict DB-level guarantee
      id: (await (async () => {
        const existing = await prisma.groupMembership.findFirst({ where: { groupId: inv.groupId, userId: me } });
        return existing?.id || '00000000-0000-0000-0000-000000000000';
      })())
    },
    update: {},
    create: { groupId: inv.groupId, userId: me, role: GroupRole.member },
  }).catch(async () => {
    // if upsert fails due to our fake id trick, try a safe create ignoring duplicates
    const exists = await prisma.groupMembership.findFirst({ where: { groupId: inv.groupId, userId: me } });
    if (!exists) await prisma.groupMembership.create({ data: { groupId: inv.groupId, userId: me, role: GroupRole.member } });
  });

  const updated = await prisma.groupInvite.update({
    where: { id: inv.id },
    data: { status: 'accepted', acceptedAt: new Date() },
  });

  return ok(res, { invite: updated, joined: true });
}

async function declineInviteCore(inv, me, res) {
  if (inv.status !== 'pending') return fail(res, 400, 'INVITE_NOT_PENDING');

  // If invite was targeted to a specific user/email, optionally enforce
  if (inv.inviteeUserId && inv.inviteeUserId !== me) return fail(res, 403, 'INVITE_NOT_FOR_YOU');

  const updated = await prisma.groupInvite.update({
    where: { id: inv.id },
    data: { status: 'declined', declinedAt: new Date() },
  });

  return ok(res, updated);
}
