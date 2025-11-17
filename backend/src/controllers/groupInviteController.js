// backend/src/controllers/groupInviteController.js
const prisma = require('../../prisma/client');

function getAuthUserId(req) {
  return req.user?.userId || null;
}

async function isGroupAdmin(userId, groupId) {
  if (!userId || !groupId) return false;

  // Creator or membership role admin / legacy isAdmin
  const grp = await prisma.group.findUnique({
    where: { id: groupId },
    select: { createdById: true },
  });
  if (grp?.createdById === userId) return true;

  const member = await prisma.groupMembership.findFirst({
    where: { userId, groupId },
    select: { role: true, isAdmin: true },
  });
  return !!member && (member.isAdmin === true || member.role === 'admin');
}

function cryptoRandom() {
  try {
    return require('crypto').randomUUID();
  } catch {
    return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  }
}

/**
 * POST /api/groups/:groupId/invites
 * Body: { inviteeUserId?, inviteeEmail?, message?, expiresAt? }
 */
exports.createInvite = async (req, res) => {
  try {
    const inviterId = getAuthUserId(req);
    if (!inviterId) return res.status(401).json({ ok: false, error: 'AUTH_REQUIRED' });

    const { groupId } = req.params;
    const { inviteeUserId, inviteeEmail, message, expiresAt } = req.body || {};

    if (!groupId) return res.status(400).json({ ok: false, error: 'GROUP_ID_REQUIRED' });
    if (!inviteeUserId && !inviteeEmail) {
      return res.status(400).json({ ok: false, error: 'INVITEE_REQUIRED' });
    }

    if (!(await isGroupAdmin(inviterId, groupId))) {
      return res.status(403).json({ ok: false, error: 'FORBIDDEN' });
    }

    // Avoid duplicate pending invite to same target
    const existing = await prisma.groupInvite.findFirst({
      where: {
        groupId,
        status: 'pending',
        OR: [
          inviteeUserId ? { inviteeUserId } : { id: '_no_user_' },
          inviteeEmail ? { inviteeEmail } : { id: '_no_email_' },
        ],
      },
    });
    if (existing) {
      return res.status(409).json({ ok: false, error: 'INVITE_ALREADY_PENDING', data: existing });
    }

    const invite = await prisma.groupInvite.create({
      data: {
        groupId,
        invitedById: inviterId,
        inviteeUserId: inviteeUserId || null,
        inviteeEmail: inviteeEmail || null,
        message: message || null,
        status: 'pending',
        token: cryptoRandom(),
        expiresAt: expiresAt ? new Date(expiresAt) : null,
      },
    });

    return res.status(201).json({ ok: true, data: invite });
  } catch (err) {
    console.error('createInvite error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
};

/**
 * GET /api/groups/:groupId/invites
 * Admin-only list (pending by default; use ?status=all to include all)
 */
exports.listInvitesForGroup = async (req, res) => {
  try {
    const me = getAuthUserId(req);
    if (!me) return res.status(401).json({ ok: false, error: 'AUTH_REQUIRED' });

    const { groupId } = req.params;
    const status = String(req.query.status || 'pending').toLowerCase();

    if (!(await isGroupAdmin(me, groupId))) {
      return res.status(403).json({ ok: false, error: 'FORBIDDEN' });
    }

    const where = { groupId, ...(status === 'all' ? {} : { status: 'pending' }) };

    const invites = await prisma.groupInvite.findMany({
      where,
      orderBy: [{ createdAt: 'desc' }],
      include: {
        invitee: { select: { id: true, fullName: true, email: true, username: true, profilePhotoUrl: true } },
        group: { select: { id: true, name: true } },
      },
    });

    return res.json({ ok: true, data: invites });
  } catch (err) {
    console.error('listInvitesForGroup error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
};

/**
 * GET /api/groups/me/invites
 * Invites addressed to the current user (by userId)
 */
exports.listMyInvites = async (req, res) => {
  try {
    const me = getAuthUserId(req);
    if (!me) return res.status(401).json({ ok: false, error: 'AUTH_REQUIRED' });

    const invites = await prisma.groupInvite.findMany({
      where: { inviteeUserId: me, status: 'pending' },
      orderBy: [{ createdAt: 'desc' }],
      include: { group: { select: { id: true, name: true } } },
    });

    return res.json({ ok: true, data: invites });
  } catch (err) {
    console.error('listMyInvites error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
};

/**
 * POST /api/groups/invites/:inviteId/accept
 * If valid → adds membership (role: member) and marks invite accepted.
 */
exports.acceptInvite = async (req, res) => {
  try {
    const me = getAuthUserId(req);
    if (!me) return res.status(401).json({ ok: false, error: 'AUTH_REQUIRED' });

    const { inviteId } = req.params;
    const invite = await prisma.groupInvite.findUnique({ where: { id: inviteId } });
    if (!invite) return res.status(404).json({ ok: false, error: 'INVITE_NOT_FOUND' });
    if (invite.status !== 'pending') return res.status(409).json({ ok: false, error: 'INVITE_NOT_PENDING' });

    // Only the invitee (user) can accept
    if (invite.inviteeUserId && invite.inviteeUserId !== me) {
      return res.status(403).json({ ok: false, error: 'FORBIDDEN' });
    }

    // Expiration check
    if (invite.expiresAt && invite.expiresAt < new Date()) {
      await prisma.groupInvite.update({ where: { id: inviteId }, data: { status: 'expired' } });
      return res.status(410).json({ ok: false, error: 'INVITE_EXPIRED' });
    }

    // Idempotent membership
    await prisma.groupMembership.upsert({
      where: { userId_groupId: { userId: me, groupId: invite.groupId } },
      update: {},
      create: { userId: me, groupId: invite.groupId, role: 'member' },
    });

    const updated = await prisma.groupInvite.update({
      where: { id: inviteId },
      data: { status: 'accepted', acceptedAt: new Date() },
    });

    return res.json({ ok: true, data: updated });
  } catch (err) {
    console.error('acceptInvite error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
};

/**
 * POST /api/groups/invites/:inviteId/decline
 */
exports.declineInvite = async (req, res) => {
  try {
    const me = getAuthUserId(req);
    if (!me) return res.status(401).json({ ok: false, error: 'AUTH_REQUIRED' });

    const { inviteId } = req.params;
    const invite = await prisma.groupInvite.findUnique({ where: { id: inviteId } });
    if (!invite) return res.status(404).json({ ok: false, error: 'INVITE_NOT_FOUND' });
    if (invite.status !== 'pending') return res.status(409).json({ ok: false, error: 'INVITE_NOT_PENDING' });

    if (invite.inviteeUserId && invite.inviteeUserId !== me) {
      return res.status(403).json({ ok: false, error: 'FORBIDDEN' });
    }

    const updated = await prisma.groupInvite.update({
      where: { id: inviteId },
      data: { status: 'declined', declinedAt: new Date() },
    });

    return res.json({ ok: true, data: updated });
  } catch (err) {
    console.error('declineInvite error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
};

/**
 * POST /api/groups/invites/:inviteId/cancel
 * Inviter or a group admin can cancel a pending invite.
 */
exports.cancelInvite = async (req, res) => {
  try {
    const me = getAuthUserId(req);
    if (!me) return res.status(401).json({ ok: false, error: 'AUTH_REQUIRED' });

    const { inviteId } = req.params;
    const invite = await prisma.groupInvite.findUnique({ where: { id: inviteId } });
    if (!invite) return res.status(404).json({ ok: false, error: 'INVITE_NOT_FOUND' });
    if (invite.status !== 'pending') return res.status(409).json({ ok: false, error: 'INVITE_NOT_PENDING' });

    const allowed = invite.invitedById === me || (await isGroupAdmin(me, invite.groupId));
    if (!allowed) return res.status(403).json({ ok: false, error: 'FORBIDDEN' });

    const updated = await prisma.groupInvite.update({
      where: { id: inviteId },
      data: { status: 'canceled', canceledAt: new Date() },
    });

    return res.json({ ok: true, data: updated });
  } catch (err) {
    console.error('cancelInvite error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
};
