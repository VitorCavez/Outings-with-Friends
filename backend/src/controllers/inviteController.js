// backend/src/controllers/inviteController.js
const { PrismaClient, InviteStatus, InviteSource } = require('@prisma/client');
const prisma = new PrismaClient();

/**
 * POST /api/invites
 * body: { toUserId: string, source?: 'contacts'|'public_feed'|'other', message?: string }
 */
async function createInvite(req, res) {
  try {
    const fromUserId = req.user?.userId;
    if (!fromUserId) return res.status(401).json({ error: 'unauthorized' });

    const { toUserId, source = 'contacts', message } = req.body || {};
    if (!toUserId) return res.status(400).json({ error: 'missing_toUserId' });
    if (toUserId === fromUserId) return res.status(400).json({ error: 'cannot_invite_self' });

    // If from public feed, ensure recipient allows public invites
    if (source === 'public_feed') {
      const recip = await prisma.user.findUnique({
        where: { id: toUserId },
        select: { allowPublicInvites: true },
      });
      if (!recip) return res.status(404).json({ error: 'recipient_not_found' });
      if (!recip.allowPublicInvites) {
        return res.status(403).json({ error: 'recipient_not_accepting_public_invites' });
      }
    }

    let invite;
    try {
      invite = await prisma.inviteRequest.create({
        data: {
          fromUserId,
          toUserId,
          status: InviteStatus.pending,
          source: Object.values(InviteSource).includes(source) ? source : InviteSource.contacts,
          message: message || null,
        },
      });
    } catch (err) {
      // Unique constraint for duplicate pending invites between same pair
      if (err?.code === 'P2002') {
        return res.status(409).json({ error: 'duplicate_pending_invite' });
      }
      throw err;
    }

    return res.status(201).json({ ok: true, invite });
  } catch (err) {
    console.error('createInvite error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
}

/**
 * POST /api/invites/:id/accept
 */
async function acceptInvite(req, res) {
  try {
    const userId = req.user?.userId;
    if (!userId) return res.status(401).json({ error: 'unauthorized' });

    const id = req.params.id;
    const inv = await prisma.inviteRequest.findUnique({ where: { id } });
    if (!inv) return res.status(404).json({ error: 'not_found' });

    if (inv.toUserId !== userId) return res.status(403).json({ error: 'forbidden' });
    if (inv.status !== 'pending') return res.status(400).json({ error: 'not_pending' });

    const updated = await prisma.inviteRequest.update({
      where: { id },
      data: { status: 'accepted', respondedAt: new Date() },
    });

    return res.json({ ok: true, invite: updated });
  } catch (err) {
    console.error('acceptInvite error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
}

/**
 * POST /api/invites/:id/decline
 */
async function declineInvite(req, res) {
  try {
    const userId = req.user?.userId;
    if (!userId) return res.status(401).json({ error: 'unauthorized' });

    const id = req.params.id;
    const inv = await prisma.inviteRequest.findUnique({ where: { id } });
    if (!inv) return res.status(404).json({ error: 'not_found' });

    if (inv.toUserId !== userId) return res.status(403).json({ error: 'forbidden' });
    if (inv.status !== 'pending') return res.status(400).json({ error: 'not_pending' });

    const updated = await prisma.inviteRequest.update({
      where: { id },
      data: { status: 'declined', respondedAt: new Date() },
    });

    return res.json({ ok: true, invite: updated });
  } catch (err) {
    console.error('declineInvite error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
}

/**
 * GET /api/invites?direction=received|sent|all
 */
async function listInvites(req, res) {
  try {
    const userId = req.user?.userId;
    if (!userId) return res.status(401).json({ error: 'unauthorized' });

    const direction = (req.query.direction || 'received').toLowerCase();

    const baseSelect = {
      id: true, status: true, source: true, message: true, createdAt: true, respondedAt: true,
      fromUser: { select: { id: true, fullName: true, profilePhotoUrl: true } },
      toUser: { select: { id: true, fullName: true, profilePhotoUrl: true } },
    };

    if (direction === 'sent') {
      const sent = await prisma.inviteRequest.findMany({
        where: { fromUserId: userId },
        select: baseSelect,
        orderBy: { createdAt: 'desc' },
      });
      return res.json({ invites: sent });
    }

    if (direction === 'all') {
      const [received, sent] = await Promise.all([
        prisma.inviteRequest.findMany({
          where: { toUserId: userId },
          select: baseSelect,
          orderBy: { createdAt: 'desc' },
        }),
        prisma.inviteRequest.findMany({
          where: { fromUserId: userId },
          select: baseSelect,
          orderBy: { createdAt: 'desc' },
        }),
      ]);
      return res.json({ received, sent });
    }

    // default: received
    const received = await prisma.inviteRequest.findMany({
      where: { toUserId: userId },
      select: baseSelect,
      orderBy: { createdAt: 'desc' },
    });
    return res.json({ invites: received });
  } catch (err) {
    console.error('listInvites error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
}

module.exports = {
  createInvite,
  acceptInvite,
  declineInvite,
  listInvites,
};
