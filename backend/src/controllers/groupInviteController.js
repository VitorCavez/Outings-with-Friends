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
 * Small helper to drop a “X joined Y” system-like message into the group
 * and broadcast it via Socket.IO so both members see the thread appear.
 */
async function sendJoinSystemMessage({ req, groupId, userId }) {
  try {
    if (!groupId || !userId) return;

    // Try to make the text a bit friendlier: use user fullName/username and group name
    const [user, group] = await Promise.all([
      prisma.user.findUnique({
        where: { id: userId },
        select: { fullName: true, username: true },
      }),
      prisma.group.findUnique({
        where: { id: groupId },
        select: { name: true },
      }),
    ]);

    const displayName =
      user?.fullName ||
      user?.username ||
      'Someone';

    const groupName = group?.name || 'this group';

    const text = `${displayName} joined ${groupName}`;

    // Persist message (same shape as socket handler in index.js)
    const saved = await prisma.message.create({
      data: {
        text,
        senderId: userId,
        recipientId: null,
        groupId,
        messageType: 'text',
        mediaUrl: null,
        fileName: null,
        fileSize: null,
      },
      select: {
        id: true,
        text: true,
        senderId: true,
        recipientId: true,
        groupId: true,
        createdAt: true,
        isRead: true,
        messageType: true,
        mediaUrl: true,
        fileName: true,
        fileSize: true,
        readAt: true,
      },
    });

    const io = req.app?.get('io');
    if (!io || !saved.groupId) return;

    const payload = {
      id: saved.id,
      text: saved.text,
      senderId: saved.senderId,
      recipientId: saved.recipientId,
      groupId: saved.groupId,
      createdAt: saved.createdAt,
      isRead: saved.isRead ?? false,
      messageType: saved.messageType || 'text',
      mediaUrl: saved.mediaUrl || null,
      fileName: saved.fileName || null,
      fileSize: saved.fileSize || null,
      readAt: saved.readAt || null,
    };

    // Mirror the behaviour from index.js:
    // - emit to group room
    // - echo to sender's user room so their client updates too
    io.to(`group:${saved.groupId}`).emit('receive_message', payload);
    io.to(`user:${saved.senderId}`).emit('receive_message', payload);
  } catch (err) {
    console.error('sendJoinSystemMessage error:', err);
    // Non-fatal: do not break invite acceptance if this fails
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
 * Now also drops a “X joined Y” message into the group chat.
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

    // 🔔 New: emit a “joined” message into the group chat so everyone
    // (including the group creator) immediately sees this thread.
    await sendJoinSystemMessage({
      req,
      groupId: invite.groupId,
      userId: me,
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
