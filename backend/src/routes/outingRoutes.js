// backend/src/routes/outingRoutes.js
const express = require('express');
const router = express.Router();

// 🔄 Use shared Prisma client + enums
const prisma = require('../../prisma/client');
const { Prisma, GroupRole } = require('@prisma/client');

const { requireAuth } = require('../middleware/auth');
const { optionalAuth } = require('../middleware/optionalAuth');
const { v4: uuidv4 } = require('uuid');

// NEW: stub mailer/SMS
const mailer = require('../services/mailer');
const sms = require('../services/sms');

/* ───────── helpers ───────── */
function toIntOrNull(v) {
  if (v === undefined || v === null || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : null;
}
function toFloatOrNull(v) {
  if (v === undefined || v === null || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}
function toDateIfString(v) {
  if (!v) return v;
  const d = typeof v === 'string' ? new Date(v) : v;
  return d instanceof Date && !isNaN(d) ? d : null;
}
function centsFromFloat(v) {
  if (v === undefined || v === null) return null;
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  return Math.round(n * 100);
}

const VisibilityEnum = {
  PUBLIC: 'PUBLIC',
  CONTACTS: 'CONTACTS',
  INVITED: 'INVITED',
  GROUPS: 'GROUPS',
};
const ParticipantRoleEnum = {
  OWNER: 'OWNER',
  PARTICIPANT: 'PARTICIPANT',
  VIEWER: 'VIEWER',
};
// Match your Prisma enum: PENDING/ACCEPTED/DECLINED/CANCELED
const InviteStatusEnum = {
  PENDING: 'PENDING',
  ACCEPTED: 'ACCEPTED',
  DECLINED: 'DECLINED',
  CANCELED: 'CANCELED',
};

function asVisibility(v) {
  if (!v) return null;
  const up = String(v).toUpperCase();
  return VisibilityEnum[up] ? up : null;
}
function asParticipantRole(v) {
  if (!v) return ParticipantRoleEnum.PARTICIPANT;
  const up = String(v).toUpperCase();
  return ParticipantRoleEnum[up] ? up : ParticipantRoleEnum.PARTICIPANT;
}

// Normalize a contact to a consistent value (+ type)
function normalizeContact(raw) {
  if (!raw) return { value: null, kind: null };
  const s = String(raw).trim();
  if (s.includes('@')) return { value: s.toLowerCase(), kind: 'email' };
  const digits = s.replace(/[^\d+]/g, '');
  return { value: digits, kind: 'phone' };
}

// Build a public join URL for an invite code
function buildJoinUrl(req, code) {
  const base =
    process.env.PUBLIC_APP_BASE_URL ||
    process.env.APP_BASE_URL ||
    process.env.BASE_URL ||
    `${req.protocol}://${req.get('host')}`;
  return `${String(base).replace(/\/+$/, '')}/join/${code}`;
}

async function assertOwner(outingId, userId) {
  const o = await prisma.outing.findUnique({
    where: { id: outingId },
    select: { id: true, createdById: true },
  });
  if (!o) return { ok: false, code: 404, msg: 'Outing not found' };
  if (o.createdById !== userId)
    return { ok: false, code: 403, msg: 'Only the organizer can perform this action' };
  return { ok: true };
}

/* quick helpers for perms */
async function isParticipant(outingId, userId) {
  if (!userId) return false;
  const row = await prisma.outingParticipant.findUnique({
    where: { outingId_userId: { outingId, userId } },
    select: { userId: true },
  });
  return !!row;
}
async function hasInvite(outingId, userId) {
  if (!userId) return false;
  const row = await prisma.outingInvite.findFirst({
    where: {
      outingId,
      inviteeUserId: userId,
      status: { in: [InviteStatusEnum.PENDING, InviteStatusEnum.ACCEPTED] },
    },
    select: { id: true },
  });
  return !!row;
}
async function shareGroup(outingGroupId, userId) {
  if (!outingGroupId || !userId) return false;
  const row = await prisma.groupMembership.findFirst({
    where: { groupId: outingGroupId, userId },
    select: { id: true },
  });
  return !!row;
}
async function isContactEitherDirection(a, b) {
  if (!a || !b) return false;
  const row = await prisma.contact.findFirst({
    where: {
      OR: [
        { ownerUserId: a, contactUserId: b, isBlocked: false },
        { ownerUserId: b, contactUserId: a, isBlocked: false },
      ],
    },
    select: { id: true },
  });
  return !!row;
}

// Ensure an outing has a linked Group + creator is admin.
// Returns the groupId.
async function ensureOutingGroup(outingId, organizerId) {
  // Fetch outing with current groupId
  const outing = await prisma.outing.findUnique({
    where: { id: outingId },
    select: { id: true, title: true, createdById: true, groupId: true },
  });

  if (!outing) {
    throw new Error(`OUTING_NOT_FOUND:${outingId}`);
  }

  const ownerId = organizerId || outing.createdById;
  let groupId = outing.groupId;

  // Create group if missing
  if (!groupId) {
    const group = await prisma.group.create({
      data: {
        name: `${outing.title || 'Outing'} chat`,
        description: null,
        visibility: 'private',
        createdById: ownerId,
      },
    });

    groupId = group.id;

    // Link outing → group
    await prisma.outing.update({
      where: { id: outing.id },
      data: { groupId },
    });
  }

  // Make sure owner is admin member (idempotent)
  await prisma.groupMembership.upsert({
    where: {
      userId_groupId: { userId: ownerId, groupId },
    },
    update: { role: GroupRole.admin, isAdmin: true },
    create: {
      userId: ownerId,
      groupId,
      role: GroupRole.admin,
      isAdmin: true,
    },
  });

  return groupId;
}

/* viewer checks */
async function canViewOuting(outing, viewerId) {
  if (!outing) return false;
  if (viewerId) {
    if (outing.createdById === viewerId) return true;
    if (await isParticipant(outing.id, viewerId)) return true;
  }
  if (!outing.isPublished) return false;
  switch (outing.visibility) {
    case VisibilityEnum.PUBLIC:
      return true;
    case VisibilityEnum.CONTACTS:
      return viewerId
        ? await isContactEitherDirection(outing.createdById, viewerId)
        : false;
    case VisibilityEnum.INVITED:
      return viewerId ? await hasInvite(outing.id, viewerId) : false;
    case VisibilityEnum.GROUPS:
      return viewerId ? await shareGroup(outing.groupId, viewerId) : false;
    default:
      return false;
  }
}
async function sanitizeOutingForViewer(outing, viewerId) {
  const isOwner = viewerId && outing.createdById === viewerId;
  const participant = viewerId ? await isParticipant(outing.id, viewerId) : false;
  if (outing.showOrganizer === false && !isOwner && !participant) {
    const { createdById, ...rest } = outing;
    return { ...rest, organizerHidden: true };
  }
  return outing;
}
async function canEditOuting(outing, viewerId) {
  if (!viewerId) return false;
  if (outing.createdById === viewerId) return true;
  if (outing.allowParticipantEdits && (await isParticipant(outing.id, viewerId)))
    return true;
  return false;
}

// TEMP: debug the DB column nullability from within Render
router.get('/dev/coords-debug', async (req, res) => {
  try {
    const rows = await prisma.$queryRaw`
      SELECT
        table_schema,
        table_name,
        column_name,
        is_nullable,
        data_type
      FROM information_schema.columns
      WHERE table_name = 'Outing'
        AND column_name IN ('latitude', 'longitude')
      ORDER BY table_schema, column_name;
    `;
    res.json({ ok: true, rows });
  } catch (e) {
    console.error('coords-debug error:', e);
    res.status(500).json({ ok: true, error: e.message });
  }
});

// TEMP: one-off fixer to drop NOT NULL on coords in the actual DB Render uses
router.get('/dev/fix-coords-nullable', async (req, res) => {
  try {
    const r1 = await prisma.$executeRaw`
      ALTER TABLE "Outing" ALTER COLUMN "latitude" DROP NOT NULL
    `;
    const r2 = await prisma.$executeRaw`
      ALTER TABLE "Outing" ALTER COLUMN "longitude" DROP NOT NULL
    `;
    res.json({ ok: true, results: { r1, r2 } });
  } catch (e) {
    console.error('fix-coords-nullable error:', e);
    res.status(500).json({ ok: false, error: e.message });
  }
});

/* ───────── routes (order matters) ───────── */

router.get('/', optionalAuth, async (req, res) => {
  try {
    const userId = req.user?.userId || null;
    if (!userId) {
      const items = await prisma.outing.findMany({
        where: { isPublished: true, visibility: 'PUBLIC' },
        orderBy: { createdAt: 'desc' },
        take: 50,
      });
      return res.json(items);
    }
    const [mine, pub] = await Promise.all([
      prisma.outing.findMany({
        where: { createdById: userId },
        orderBy: { createdAt: 'desc' },
        take: 50,
      }),
      prisma.outing.findMany({
        where: { isPublished: true, visibility: 'PUBLIC' },
        orderBy: { createdAt: 'desc' },
        take: 50,
      }),
    ]);
    const map = new Map();
    [...mine, ...pub].forEach((o) => map.set(o.id, o));
    res.json(Array.from(map.values()));
  } catch (e) {
    console.error('Fetch all outings error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/', requireAuth, async (req, res) => {
  const userId = req.user?.userId;
  if (!userId) return res.status(401).json({ error: 'AUTH_REQUIRED' });

  const {
    title,
    outingType,
    groupId,
    locationName,
    latitude,
    longitude,
    address,
    dateTimeStart,
    dateTimeEnd,
    description,
    budgetMin,
    budgetMax,
    piggyBankEnabled = false,
    piggyBankTarget,
    piggyBankTargetCents,
    checklist = [],
    suggestedItinerary,
    liveLocationEnabled = false,
    isPublic = false,
  } = req.body || {};

  // basic required fields
  if (!title || !outingType || !locationName) {
    return res.status(400).json({
      error: 'MISSING_FIELDS',
      details: 'title, outingType, locationName are required',
    });
  }

  // coords (optional)
  const lat = toFloatOrNull(latitude);
  const lng = toFloatOrNull(longitude);

  // dates
  const start = toDateIfString(dateTimeStart);
  const end = toDateIfString(dateTimeEnd);
  if (!start || !end || !(end > start)) {
    return res.status(400).json({
      error: 'INVALID_DATES',
      details: 'dateTimeStart/dateTimeEnd invalid',
    });
  }

  // budgets
  const budgetMinNum = toFloatOrNull(budgetMin);
  const budgetMaxNum = toFloatOrNull(budgetMax);

  // piggy bank target
  const targetCents =
    toIntOrNull(piggyBankTargetCents) ?? centsFromFloat(piggyBankTarget);
  if (piggyBankEnabled === true && (!targetCents || targetCents <= 0)) {
    return res.status(400).json({
      error: 'INVALID_PB_TARGET',
      details: 'piggyBankTargetCents must be positive',
    });
  }

  try {
    // ensure user exists
    const userExists = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true },
    });
    if (!userExists) {
      return res.status(400).json({ error: 'INVALID_USER' });
    }

    // optional group connect (schema now expects `group`, not `groupId`)
    let groupConnect = null;
    if (groupId) {
      const g = await prisma.group.findUnique({
        where: { id: groupId },
        select: { id: true },
      });
      if (!g) {
        return res.status(400).json({ error: 'INVALID_GROUP' });
      }
      groupConnect = g.id;
    }

    // base data object
    const data = {
      title,
      outingType,
      locationName,
      address: address ?? null,
      dateTimeStart: start,
      dateTimeEnd: end,
      description: description ?? null,
      budgetMin: budgetMinNum,
      budgetMax: budgetMaxNum,
      piggyBankEnabled: !!piggyBankEnabled,
      piggyBankTarget:
        piggyBankTarget ?? (targetCents != null ? targetCents / 100 : null),
      piggyBankTargetCents: targetCents ?? null,
      checklist: Array.isArray(checklist) ? checklist : [],
      suggestedItinerary,
      liveLocationEnabled: !!liveLocationEnabled,
      isPublic: !!isPublic,

      // relations
      createdBy: {
        connect: { id: userId },
      },
      ...(groupConnect
        ? {
            group: {
              connect: { id: groupConnect },
            },
          }
        : {}),
    };

    // only send coords if we actually have numbers
    if (lat != null && lng != null) {
      data.latitude = lat;
      data.longitude = lng;
    }

    const outing = await prisma.outing.create({ data });

    return res
      .status(201)
      .json({ message: 'Outing created successfully', outing });
  } catch (e) {
    console.error('Create outing error:', e);
    if (e.code === 'P2003') {
      return res.status(400).json({
        error: 'FK_CONSTRAINT',
        details: e.meta || 'Foreign key constraint failed',
      });
    }
    return res.status(500).json({ error: 'Internal server error' });
  }
});

/* participants */
router.get('/:id/participants', requireAuth, async (req, res) => {
  const { id } = req.params;
  try {
    const outing = await prisma.outing.findUnique({
      where: { id },
      select: { id: true, createdById: true, allowParticipantEdits: true },
    });
    if (!outing) return res.status(404).json({ error: 'Outing not found' });

    const userId = req.user.userId;
    const owner = outing.createdById === userId;
    const isPart = await prisma.outingParticipant.findUnique({
      where: { outingId_userId: { outingId: id, userId } },
      select: { id: true },
    });
    if (!owner && !isPart)
      return res.status(403).json({ error: 'Not allowed to view participants' });

    const participants = await prisma.outingParticipant.findMany({
      where: { outingId: id },
      include: {
        user: {
          select: {
            id: true,
            fullName: true,
            username: true,
            profilePhotoUrl: true,
          },
        },
      },
      orderBy: { createdAt: 'asc' },
    });
    res.json({ ok: true, data: participants });
  } catch (e) {
    console.error('list participants error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/* publish + invites */
router.patch('/:id/publish', requireAuth, async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.user.userId;
    const { visibility, allowParticipantEdits, showOrganizer } = req.body || {};

    const own = await assertOwner(id, userId);
    if (!own.ok) return res.status(own.code).json({ error: own.msg });

    const vis = asVisibility(visibility) ?? 'INVITED';

    const updated = await prisma.outing.update({
      where: { id },
      data: {
        isPublished: true,
        publishedAt: new Date(),
        visibility: vis,
        allowParticipantEdits:
          typeof allowParticipantEdits === 'boolean'
            ? allowParticipantEdits
            : undefined,
        showOrganizer:
          typeof showOrganizer === 'boolean' ? showOrganizer : undefined,
      },
    });

    await prisma.outingParticipant.upsert({
      where: { outingId_userId: { outingId: id, userId } },
      create: { outingId: id, userId, role: 'OWNER' },
      update: { role: 'OWNER' },
    });

    // ⭐ guarantee a group chat exists for this outing + creator is admin
    try {
      const groupId = await ensureOutingGroup(id, userId);
      return res.json({ ok: true, data: { ...updated, groupId } });
    } catch (err) {
      console.error('ensureOutingGroup (publish) failed:', err);
      return res.json({ ok: true, data: updated });
    }
  } catch (e) {
    console.error('Publish outing error:', e);
    res.status(500).json({ error: 'Internal error' });
  }
});

router.post('/:id/invites', requireAuth, async (req, res) => {
  try {
    const { id } = req.params;
    const inviterId = req.user.userId;
    const own = await assertOwner(id, inviterId);
    if (!own.ok) return res.status(own.code).json({ error: own.msg });

    // Ensure outing exists
    const outing = await prisma.outing.findUnique({
      where: { id },
      select: { id: true, title: true, createdById: true, groupId: true },
    });
    if (!outing) return res.status(404).json({ error: 'Outing not found' });

    // ⭐ Ensure there is a group for this outing and inviter is admin
    const groupId = await ensureOutingGroup(outing.id, inviterId);

    // Collect invitees
    const {
      invitees,
      userIds = [],
      contacts = [],
      role,
      expiresInDays = 14,
    } = req.body || {};
    const normalized = Array.isArray(invitees)
      ? invitees
      : [
          ...userIds.map((u) => ({ userId: u })),
          ...contacts.map((c) => {
            const n = normalizeContact(c);
            return { contact: n.value };
          }),
        ];
    if (!normalized.length)
      return res.status(400).json({ error: 'No invite targets provided' });

    const roleVal = asParticipantRole(role);
    const expiresAt = expiresInDays
      ? new Date(Date.now() + expiresInDays * 86400000)
      : null;

    async function resolveContactToUserId(contact) {
      if (!contact) return null;
      const { value } = normalizeContact(contact);
      if (!value) return null;

      // Email match
      if (value.includes('@')) {
        const u = await prisma.user.findUnique({
          where: { email: value },
          select: { id: true },
        });
        return u ? u.id : null;
      }

      // Phone (E.164) match
      const u = await prisma.user.findFirst({
        where: { phoneE164: value },
        select: { id: true },
      });
      return u ? u.id : null;
    }

    const created = [];
    for (const i of normalized) {
      let inviteeUserId = i.userId || null;
      let inviteeContact = i.contact || null;

      if (inviteeContact) {
        inviteeContact = normalizeContact(inviteeContact).value;
      }
      if (!inviteeUserId && inviteeContact) {
        try {
          const resolved = await resolveContactToUserId(inviteeContact);
          if (resolved) inviteeUserId = resolved;
        } catch (_) {}
      }

      if (inviteeUserId && inviteeUserId === inviterId) continue;

      const exists = await prisma.outingInvite.findFirst({
        where: {
          outingId: id,
          status: InviteStatusEnum.PENDING,
          OR: [
            inviteeUserId ? { inviteeUserId } : { id: '__none__' },
            inviteeContact ? { inviteeContact } : { id: '__none__' },
          ],
        },
        select: { id: true },
      });
      if (exists) continue;

      const inv = await prisma.outingInvite.create({
        data: {
          id: uuidv4(),
          outingId: id,
          inviterId,
          inviteeUserId: inviteeUserId || null,
          inviteeContact: inviteeContact || null,
          role: roleVal,
          status: InviteStatusEnum.PENDING,
          code: uuidv4(),
          expiresAt,
        },
      });
      created.push(inv);

      if (inviteeContact) {
        const joinUrl = buildJoinUrl(req, inv.code);
        try {
          if (inviteeContact.includes('@')) {
            await mailer.sendInvite({
              to: inviteeContact,
              subject: "You're invited to an Outing",
              text: `You were invited to join an outing. Open: ${joinUrl}`,
              joinUrl,
              inviterId,
              outingId: id,
              code: inv.code,
            });
          } else {
            await sms.sendInvite({
              to: inviteeContact,
              text: `You're invited to an Outing. Join: ${joinUrl}`,
              joinUrl,
              inviterId,
              outingId: id,
              code: inv.code,
            });
          }
        } catch (notifyErr) {
          console.warn(
            'Invite created but notify failed:',
            notifyErr?.message || notifyErr,
          );
        }
      }
    }

    return res
      .status(201)
      .json({ ok: true, invites: created, linkedGroupId: groupId });
  } catch (e) {
    console.error('create invites error:', e);
    return res.status(500).json({ error: e.message || 'Internal error' });
  }
});

/* me lists */
router.get('/mine', requireAuth, async (req, res) => {
  const userId = req.user?.userId;
  if (!userId) return res.status(401).json({ error: 'AUTH_REQUIRED' });
  const limit = Math.max(1, Math.min(100, toIntOrNull(req.query.limit) ?? 20));
  const offset = Math.max(0, toIntOrNull(req.query.offset) ?? 0);
  try {
    const [items, total] = await Promise.all([
      prisma.outing.findMany({
        where: { createdById: userId },
        orderBy: { createdAt: 'desc' },
        skip: offset,
        take: limit,
      }),
      prisma.outing.count({ where: { createdById: userId } }),
    ]);
    res.json({ ok: true, meta: { total, limit, offset }, data: items });
  } catch (e) {
    console.error('list mine error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/shared-with-me', requireAuth, async (req, res) => {
  const userId = req.user?.userId;
  if (!userId) return res.status(401).json({ error: 'AUTH_REQUIRED' });
  const limit = Math.max(1, Math.min(100, toIntOrNull(req.query.limit) ?? 20));
  const offset = Math.max(0, toIntOrNull(req.query.offset) ?? 0);
  try {
    const rows = await prisma.outingParticipant.findMany({
      where: { userId },
      include: { outing: true },
      orderBy: { createdAt: 'desc' },
      skip: offset,
      take: limit,
    });
    const filtered = rows.filter((r) => r.outing?.createdById !== userId);
    res.json({
      ok: true,
      meta: { total: filtered.length, limit, offset },
      data: filtered.map((r) => ({
        role: r.role,
        permissions: r.permissions,
        outing: r.outing,
      })),
    });
  } catch (e) {
    console.error('list shared-with-me error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// RECEIVER: list my incoming invites (by userId or my email as inviteeContact)
router.get('/invites', requireAuth, async (req, res) => {
  const userId = req.user?.userId;
  if (!userId) return res.status(401).json({ error: 'AUTH_REQUIRED' });

  const statusParam = String(req.query.status || 'PENDING').toUpperCase();
  const status = InviteStatusEnum[statusParam] || InviteStatusEnum.PENDING;

  try {
    const me = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, email: true },
    });

    const orClauses = [{ inviteeUserId: userId }];
    if (me?.email) {
      orClauses.push({
        inviteeContact: {
          equals: me.email.toLowerCase().trim(),
          mode: 'insensitive',
        },
      });
    }

    const invites = await prisma.outingInvite.findMany({
      where: { status, OR: orClauses },
      include: { outing: true },
      orderBy: { createdAt: 'desc' },
    });

    return res.json({ ok: true, data: invites });
  } catch (e) {
    console.error('list invites error:', e);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

/* -------- Sent invites endpoints (organizer) -------- */

router.get('/sent-invites', requireAuth, async (req, res) => {
  const userId = req.user?.userId;
  if (!userId) return res.status(401).json({ error: 'AUTH_REQUIRED' });

  const statusParam = req.query.status
    ? String(req.query.status).toUpperCase()
    : null;
  const status =
    statusParam && InviteStatusEnum[statusParam] ? statusParam : undefined;
  const outingId = req.query.outingId ? String(req.query.outingId) : undefined;

  try {
    const invites = await prisma.outingInvite.findMany({
      where: {
        inviterId: userId,
        ...(status ? { status } : {}),
        ...(outingId ? { outingId } : {}),
      },
      include: { outing: true },
      orderBy: { createdAt: 'desc' },
    });
    res.json({ ok: true, data: invites });
  } catch (e) {
    console.error('list sent-invites error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/:id/invites/sent', requireAuth, async (req, res) => {
  const { id } = req.params;
  const userId = req.user?.userId;
  const own = await assertOwner(id, userId);
  if (!own.ok) return res.status(own.code).json({ error: own.msg });

  try {
    const invites = await prisma.outingInvite.findMany({
      where: { outingId: id, inviterId: userId },
      include: { outing: true },
      orderBy: { createdAt: 'desc' },
    });
    res.json({ ok: true, data: invites });
  } catch (e) {
    console.error('list sent invites (by outing) error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Accept / decline an invite (also join group if present + system message)
router.patch('/invites/:inviteId', requireAuth, async (req, res) => {
  const { inviteId } = req.params;
  const userId = req.user?.userId;
  const actionRaw = String(req.body?.action || '').toUpperCase();
  if (!['ACCEPT', 'DECLINE'].includes(actionRaw)) {
    return res.status(400).json({
      error: 'INVALID_ACTION',
      details: 'action must be ACCEPT or DECLINE',
    });
  }

  const normPhone = (s) => (s ? String(s).replace(/[^\d+]/g, '') : '');

  try {
    const inv = await prisma.outingInvite.findUnique({
      where: { id: inviteId },
      include: { outing: true },
    });
    if (!inv) return res.status(404).json({ error: 'Invite not found' });

    const me = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, email: true, phoneE164: true, fullName: true },
    });
    if (!me) return res.status(401).json({ error: 'AUTH_REQUIRED' });

    const contact = inv.inviteeContact || '';
    const contactMatchesUser =
      !!contact &&
      ((me.email && me.email.toLowerCase() === contact.toLowerCase()) ||
        (me.phoneE164 &&
          normPhone(me.phoneE164) === normPhone(contact)));

    const isInvitee = inv.inviteeUserId === userId || contactMatchesUser;
    if (!isInvitee) return res.status(403).json({ error: 'FORBIDDEN' });

    // Handle expiry first -> mark as CANCELED (schema enum)
    if (
      inv.expiresAt &&
      inv.expiresAt < new Date() &&
      inv.status === InviteStatusEnum.PENDING
    ) {
      const expired = await prisma.outingInvite.update({
        where: { id: inviteId },
        data: { status: InviteStatusEnum.CANCELED },
      });
      return res.status(410).json({ error: 'EXPIRED', data: expired });
    }

    // If already processed, return as-is
    if (inv.status !== InviteStatusEnum.PENDING) {
      // keep shape so Flutter can still parse
      return res.json({ ok: true, invite: inv });
    }

    if (actionRaw === 'DECLINE') {
      const declined = await prisma.outingInvite.update({
        where: { id: inviteId },
        data: {
          status: InviteStatusEnum.DECLINED,
          ...(inv.inviteeUserId ? {} : { inviteeUserId: userId }),
        },
      });
      return res.json({ ok: true, invite: declined });
    }

    // ACCEPT
    const result = await prisma.$transaction(async (tx) => {
      const updated = await tx.outingInvite.update({
        where: { id: inviteId },
        data: {
          status: InviteStatusEnum.ACCEPTED,
          ...(inv.inviteeUserId ? {} : { inviteeUserId: userId }),
        },
      });

      // Add as OutingParticipant
      await tx.outingParticipant.upsert({
        where: {
          outingId_userId: { outingId: updated.outingId, userId },
        },
        create: {
          outingId: updated.outingId,
          userId,
          role: updated.role || 'PARTICIPANT',
        },
        update: { role: updated.role || 'PARTICIPANT' },
      });

      // Also add to the outing's group if there is one
      const o = await tx.outing.findUnique({
        where: { id: updated.outingId },
        select: { groupId: true },
      });

      let systemMessage = null;
      if (o?.groupId) {
        // Ensure group membership for the invitee
        await tx.groupMembership.upsert({
          where: { userId_groupId: { userId, groupId: o.groupId } },
          update: { role: GroupRole.member, isAdmin: false },
          create: {
            userId,
            groupId: o.groupId,
            role: GroupRole.member,
            isAdmin: false,
          },
        });

        // Create an automatic "invite accepted" message in the group chat
        const text =
          `${me.fullName || 'Someone'} accepted the outing invitation`;

        systemMessage = await tx.message.create({
          data: {
            text,
            senderId: userId,
            groupId: o.groupId,
            recipientId: null,
            isRead: false,
            messageType: 'text',
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

        return {
          invite: updated,
          groupId: o.groupId,
          systemMessage,
        };
      }

      // No group attached to this outing
      return { invite: updated, groupId: null, systemMessage: null };
    });

    // 🚀 Broadcast the system message over Socket.IO so both users see it
    try {
      const io = req.app.get('io');
      if (io && result.groupId && result.systemMessage) {
        io.to(`group:${result.groupId}`).emit('receive_message', {
          id: result.systemMessage.id,
          text: result.systemMessage.text,
          senderId: result.systemMessage.senderId,
          recipientId: result.systemMessage.recipientId,
          groupId: result.systemMessage.groupId,
          createdAt: result.systemMessage.createdAt,
          isRead: result.systemMessage.isRead,
          messageType: result.systemMessage.messageType,
          mediaUrl: result.systemMessage.mediaUrl,
          fileName: result.systemMessage.fileName,
          fileSize: result.systemMessage.fileSize,
          readAt: result.systemMessage.readAt,
        });
      }
    } catch (emitErr) {
      console.warn('Socket emit failed for invite accept:', emitErr?.message || emitErr);
    }

    // Keep response shape compatible with the Flutter OutingShareService
    return res.json({ ok: true, invite: result.invite });
  } catch (e) {
    console.error('update invite error:', e);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

/* piggy bank + expenses (nested) */
router.get('/:id/piggybank', optionalAuth, async (req, res) => {
  const { id } = req.params;
  try {
    const outing = await prisma.outing.findUnique({ where: { id } });
    if (!outing) return res.status(404).json({ error: 'Outing not found' });
    const targetCents =
      outing.piggyBankTargetCents ??
      centsFromFloat(outing.piggyBankTarget) ??
      0;
    const contributions = await prisma.outingContribution.findMany({
      where: { outingId: id },
      orderBy: { createdAt: 'desc' },
    });
    const raisedCents = contributions.reduce((s, c) => {
      if (
        typeof c.amountCents === 'number' &&
        Number.isFinite(c.amountCents)
      )
        return s + c.amountCents;
      if (c.amount != null) return s + centsFromFloat(c.amount);
      return s;
    }, 0);
    const progressPct =
      targetCents > 0
        ? Math.min(100, Math.round((raisedCents / targetCents) * 100))
        : 0;
    res.json({ targetCents, raisedCents, progressPct, contributions });
  } catch (e) {
    console.error('Piggy bank summary error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/:id/piggybank/contributions', requireAuth, async (req, res) => {
  const { id } = req.params;
  const { userId, amountCents, note } = req.body;
  if (!userId)
    return res.status(400).json({ error: 'userId is required.' });
  const cents = toIntOrNull(amountCents);
  if (cents == null || cents <= 0)
    return res
      .status(400)
      .json({ error: 'amountCents must be a positive integer.' });
  try {
    const outing = await prisma.outing.findUnique({ where: { id } });
    if (!outing) return res.status(404).json({ error: 'Outing not found' });
    if (!outing.piggyBankEnabled)
      return res
        .status(400)
        .json({ error: 'Piggy bank is not enabled for this outing.' });
    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) return res.status(400).json({ error: 'Invalid userId' });
    const contribution = await prisma.outingContribution.create({
      data: {
        outingId: id,
        userId,
        amountCents: cents,
        amount: cents / 100,
        note: note ?? null,
      },
    });
    res.status(201).json({ message: 'Contribution added', contribution });
  } catch (e) {
    console.error('Add contribution error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/* NEW: delete a piggy bank contribution */
router.delete(
  '/:id/piggybank/contributions/:contributionId',
  requireAuth,
  async (req, res) => {
    const { id, contributionId } = req.params;
    const userId = req.user?.userId;
    if (!userId) return res.status(401).json({ error: 'AUTH_REQUIRED' });

    try {
      const contrib = await prisma.outingContribution.findUnique({
        where: { id: contributionId },
      });

      if (!contrib || contrib.outingId !== id) {
        return res
          .status(404)
          .json({ error: 'CONTRIBUTION_NOT_FOUND' });
      }

      const outing = await prisma.outing.findUnique({
        where: { id },
        select: { createdById: true },
      });

      if (!outing) {
        return res.status(404).json({ error: 'Outing not found' });
      }

      const isOwner = contrib.userId === userId;
      const isOrganizer = outing.createdById === userId;

      if (!isOwner && !isOrganizer) {
        return res
          .status(403)
          .json({ error: 'Only the contributor or organizer can delete.' });
      }

      await prisma.outingContribution.delete({ where: { id: contributionId } });
      return res.json({ ok: true });
    } catch (e) {
      console.error('Delete contribution error:', e);
      return res.status(500).json({ error: 'Internal server error' });
    }
  },
);

router.post('/:id/expenses', requireAuth, async (req, res) => {
  const { id } = req.params;
  const { payerId, amountCents, description, category } = req.body;
  if (!payerId)
    return res.status(400).json({ error: 'payerId is required.' });
  const cents = toIntOrNull(amountCents);
  if (cents == null || cents <= 0)
    return res
      .status(400)
      .json({ error: 'amountCents must be a positive integer.' });
  try {
    const outing = await prisma.outing.findUnique({ where: { id } });
    if (!outing) return res.status(404).json({ error: 'Outing not found' });
    const payer = await prisma.user.findUnique({ where: { id: payerId } });
    if (!payer) return res.status(400).json({ error: 'Invalid payerId' });
    const expense = await prisma.expense.create({
      data: {
        outingId: id,
        payerId,
        amountCents: cents,
        description: description ?? null,
        category: category ?? null,
      },
    });
    res.status(201).json(expense);
  } catch (e) {
    console.error('Create expense error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/:id/expenses/summary', optionalAuth, async (req, res) => {
  const { id } = req.params;
  try {
    const expenses = await prisma.expense.findMany({
      where: { outingId: id },
      orderBy: { createdAt: 'asc' },
    });
    const rsvps = await prisma.outingUser.findMany({ where: { outingId: id } });
    const participantSet = new Set(
      [...rsvps.map((r) => r.userId), ...expenses.map((e) => e.payerId)].filter(
        Boolean,
      ),
    );
    const participants = Array.from(participantSet);
    const totalCents = expenses.reduce(
      (s, e) => s + (e.amountCents || 0),
      0,
    );
    const count = participants.length || 1;
    const perPersonCents = Math.round(totalCents / count);
    const paidMap = {};
    for (const pid of participants) paidMap[pid] = 0;
    for (const e of expenses) {
      if (!paidMap[e.payerId]) paidMap[e.payerId] = 0;
      paidMap[e.payerId] += e.amountCents || 0;
    }
    const balances = participants.map((userId) => {
      const paidCents = paidMap[userId] || 0;
      const balanceCents = paidCents - perPersonCents;
      return {
        userId,
        paidCents,
        owesCents: Math.max(0, perPersonCents - paidCents),
        balanceCents,
      };
    });
    res.json({
      totalCents,
      participants,
      perPersonCents,
      balances,
      expenses,
    });
  } catch (e) {
    console.error('Expense summary error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/* by-id (keep last) */
router.get('/:id', optionalAuth, async (req, res) => {
  const { id } = req.params;
  const userId = req.user?.userId || null;
  try {
    const outing = await prisma.outing.findUnique({ where: { id } });
    if (!outing) return res.status(404).json({ error: 'Outing not found' });
    const allowed = await canViewOuting(outing, userId);
    if (!allowed)
      return res
        .status(403)
        .json({ error: 'Not allowed to view this outing' });
    const sanitized = await sanitizeOutingForViewer(outing, userId);
    res.json(sanitized);
  } catch (e) {
    console.error('Fetch outing by ID error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/* UPDATE — accept PUT & PATCH, map notes->description and whitelist fields */
function buildUpdateData(raw) {
  const body = { ...raw };

  // map alias
  if (Object.prototype.hasOwnProperty.call(body, 'notes')) {
    body.description = body.notes;
    delete body.notes;
  }

  // sanitize/normalize specific fields
  if ('dateTimeStart' in body)
    body.dateTimeStart = toDateIfString(body.dateTimeStart);
  if ('dateTimeEnd' in body)
    body.dateTimeEnd = toDateIfString(body.dateTimeEnd);
  if ('latitude' in body) body.latitude = toFloatOrNull(body.latitude);
  if ('longitude' in body) body.longitude = toFloatOrNull(body.longitude);
  if ('budgetMin' in body) body.budgetMin = toFloatOrNull(body.budgetMin);
  if ('budgetMax' in body) body.budgetMax = toFloatOrNull(body.budgetMax);

  // piggy bank normalization (only if user sent one of the targets)
  const normalizedTarget =
    'piggyBankTargetCents' in body || 'piggyBankTarget' in body
      ? toIntOrNull(body.piggyBankTargetCents) ??
        centsFromFloat(body.piggyBankTarget)
      : null;

  if (normalizedTarget != null) {
    body.piggyBankTargetCents = normalizedTarget;
    if (!('piggyBankTarget' in body)) {
      body.piggyBankTarget = normalizedTarget / 100;
    }
  }

  // whitelist of fields allowed to update
  const allowed = [
    'title',
    'description',
    'outingType',
    'groupId',
    'locationName',
    'address',
    'latitude',
    'longitude',
    'dateTimeStart',
    'dateTimeEnd',
    'budgetMin',
    'budgetMax',
    'piggyBankEnabled',
    'piggyBankTarget',
    'piggyBankTargetCents',
    'allowParticipantEdits',
    'showOrganizer',
    'visibility',
    'isPublished',
    'suggestedItinerary',
    'checklist',
    'liveLocationEnabled',
  ];

  const data = {};
  for (const k of allowed) {
    if (Object.prototype.hasOwnProperty.call(body, k)) {
      data[k] = body[k];
    }
  }
  return data;
}

async function updateOutingHandler(req, res) {
  const { id } = req.params;
  const userId = req.user.userId;

  try {
    const existing = await prisma.outing.findUnique({ where: { id } });
    if (!existing) return res.status(404).json({ error: 'Outing not found' });
    if (!(await canEditOuting(existing, userId))) {
      return res
        .status(403)
        .json({ error: 'You cannot edit this outing' });
    }

    // If enabling PB, ensure valid target
    const nextEnabled =
      'piggyBankEnabled' in req.body
        ? !!req.body.piggyBankEnabled
        : existing.piggyBankEnabled;
    const currentTargetCents =
      existing.piggyBankTargetCents ??
      centsFromFloat(existing.piggyBankTarget) ??
      null;
    const normalizedTarget =
      'piggyBankTargetCents' in req.body || 'piggyBankTarget' in req.body
        ? toIntOrNull(req.body.piggyBankTargetCents) ??
          centsFromFloat(req.body.piggyBankTarget)
        : null;
    const nextTargetCents =
      normalizedTarget != null ? normalizedTarget : currentTargetCents;
    if (nextEnabled === true && (!nextTargetCents || nextTargetCents <= 0)) {
      return res.status(400).json({
        error: 'INVALID_PB_TARGET',
        details:
          'piggyBankTargetCents must be > 0 when piggyBankEnabled is true',
      });
    }

    const data = buildUpdateData(req.body);

    const outing = await prisma.outing.update({ where: { id }, data });
    res.json({ message: 'Outing updated successfully', outing });
  } catch (e) {
    console.error('Update outing error:', e);
    if (e instanceof Prisma.PrismaClientValidationError) {
      return res.status(400).json({
        error: 'VALIDATION_ERROR',
        details: e.message,
      });
    }
    if (e.code === 'P2025') {
      return res.status(404).json({ error: 'Outing not found' });
    }
    res.status(500).json({ error: 'Internal server error' });
  }
}
router.put('/:id', requireAuth, updateOutingHandler);
router.patch('/:id', requireAuth, updateOutingHandler);

/* delete */
router.delete('/:id', requireAuth, async (req, res) => {
  const { id } = req.params;
  try {
    const deleted = await prisma.outing.delete({ where: { id } });
    res.json({ message: 'Outing deleted successfully', deleted });
  } catch (e) {
    console.error('Delete outing error:', e);
    if (e.code === 'P2025')
      return res.status(404).json({ error: 'Outing not found' });
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
