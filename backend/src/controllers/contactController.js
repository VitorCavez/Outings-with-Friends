// backend/src/controllers/contactController.js
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
const { normalizePhone } = require('../utils/phone');

// Return only minimal, non-sensitive public fields
function minimalUser(u) {
  if (!u) return null;
  return {
    id: u.id,
    fullName: u.fullName,
    profilePhotoUrl: u.profilePhotoUrl || null,
    isProfilePublic: !!u.isProfilePublic,
    allowPublicInvites: !!u.allowPublicInvites,
  };
}

/**
 * POST /api/contacts/lookup-by-phone
 * body: { phone: string, defaultCountryCode?: string }
 */
async function lookupByPhone(req, res) {
  try {
    const { phone, defaultCountryCode } = req.body || {};
    const norm = normalizePhone(phone, { defaultCountryCode });

    if (!norm.e164) {
      return res
        .status(400)
        .json({ error: 'invalid_phone', reason: norm.reason || 'normalize_failed' });
    }

    const user = await prisma.user.findUnique({
      where: { phoneE164: norm.e164 },
      select: {
        id: true,
        fullName: true,
        profilePhotoUrl: true,
        isProfilePublic: true,
        allowPublicInvites: true,
      },
    });

    if (!user) {
      return res.status(404).json({ error: 'not_found' });
    }

    return res.json({ user: minimalUser(user) });
  } catch (err) {
    console.error('lookupByPhone error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
}

/**
 * POST /api/contacts/match
 * body: { phones: string[], defaultCountryCode?: string }
 *
 * Bulk match phone numbers -> users.
 * Returns only matched users (minimal public fields), plus:
 * - matchedPhoneE164 (for mapping)
 * - alreadyInContacts flag
 */
async function matchContacts(req, res) {
  try {
    const ownerUserId = req.user?.userId;
    if (!ownerUserId) return res.status(401).json({ error: 'unauthorized' });

    const { phones, defaultCountryCode } = req.body || {};

    if (!Array.isArray(phones)) {
      return res.status(400).json({ error: 'invalid_body', message: 'phones must be an array of strings.' });
    }

    // Safety cap to avoid huge payloads
    const MAX_PHONES = 2000;
    if (phones.length > MAX_PHONES) {
      return res.status(400).json({
        error: 'too_many_phones',
        message: `Max ${MAX_PHONES} phone numbers per request.`,
      });
    }

    // Normalize + dedupe
    const e164Set = new Set();
    let invalidCount = 0;

    for (const raw of phones) {
      if (!raw || typeof raw !== 'string') {
        invalidCount += 1;
        continue;
      }
      const norm = normalizePhone(raw, { defaultCountryCode });
      if (norm?.e164) {
        e164Set.add(norm.e164);
      } else {
        invalidCount += 1;
      }
    }

    const e164List = Array.from(e164Set);
    if (e164List.length === 0) {
      return res.json({
        matches: [],
        totals: {
          submitted: phones.length,
          normalized: 0,
          matched: 0,
          invalid: invalidCount,
        },
      });
    }

    // Find users by phoneE164
    const users = await prisma.user.findMany({
      where: { phoneE164: { in: e164List } },
      select: {
        id: true,
        fullName: true,
        profilePhotoUrl: true,
        isProfilePublic: true,
        allowPublicInvites: true,
        phoneE164: true,
      },
    });

    // Never return yourself as a "match"
    const filteredUsers = users.filter((u) => u.id !== ownerUserId);

    const userIds = filteredUsers.map((u) => u.id);

    // Find which matched users are already in my contacts
    let existingSet = new Set();
    if (userIds.length > 0) {
      const existing = await prisma.contact.findMany({
        where: {
          ownerUserId,
          contactUserId: { in: userIds },
        },
        select: { contactUserId: true },
      });
      existingSet = new Set(existing.map((c) => c.contactUserId));
    }

    const matches = filteredUsers.map((u) => ({
      user: minimalUser(u),
      matchedPhoneE164: u.phoneE164, // helps client map results back
      alreadyInContacts: existingSet.has(u.id),
    }));

    return res.json({
      matches,
      totals: {
        submitted: phones.length,
        normalized: e164List.length,
        matched: matches.length,
        invalid: invalidCount,
      },
    });
  } catch (err) {
    console.error('matchContacts error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
}

/**
 * POST /api/contacts
 * body: { userId?: string, phone?: string, defaultCountryCode?: string, label?: string }
 * Adds a contact to the owner’s list (no mutual confirmation needed).
 */
async function addContact(req, res) {
  try {
    const ownerUserId = req.user?.userId;
    if (!ownerUserId) return res.status(401).json({ error: 'unauthorized' });

    let { userId, phone, defaultCountryCode, label } = req.body || {};
    let contactUserId = userId;

    if (!contactUserId && phone) {
      const norm = normalizePhone(phone, { defaultCountryCode });
      if (!norm.e164) {
        return res
          .status(400)
          .json({ error: 'invalid_phone', reason: norm.reason || 'normalize_failed' });
      }
      const target = await prisma.user.findUnique({
        where: { phoneE164: norm.e164 },
        select: { id: true },
      });
      if (!target) {
        return res.status(404).json({ error: 'not_found' });
      }
      contactUserId = target.id;
    }

    if (!contactUserId) {
      return res.status(400).json({ error: 'missing_target', message: 'Provide userId or phone.' });
    }

    if (contactUserId === ownerUserId) {
      return res.status(400).json({ error: 'cannot_add_self' });
    }

    // Create if not exists (unique on [ownerUserId, contactUserId])
    const already = await prisma.contact.findUnique({
      where: { ownerUserId_contactUserId: { ownerUserId, contactUserId } },
    });

    if (already) {
      // Update label if provided
      if (label && label !== already.label) {
        const updated = await prisma.contact.update({
          where: { ownerUserId_contactUserId: { ownerUserId, contactUserId } },
          data: { label },
        });
        return res.json({ ok: true, contact: updated });
      }
      return res.json({ ok: true, contact: already });
    }

    const contact = await prisma.contact.create({
      data: { ownerUserId, contactUserId, label: label || null },
    });

    return res.status(201).json({ ok: true, contact });
  } catch (err) {
    console.error('addContact error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
}

/**
 * GET /api/contacts
 * Returns my contacts with minimal profile info
 */
async function listContacts(req, res) {
  try {
    const ownerUserId = req.user?.userId;
    if (!ownerUserId) return res.status(401).json({ error: 'unauthorized' });

    const contacts = await prisma.contact.findMany({
      where: { ownerUserId },
      include: {
        contact: {
          select: {
            id: true,
            fullName: true,
            profilePhotoUrl: true,
            isProfilePublic: true,
            allowPublicInvites: true,
          },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    const list = contacts.map((c) => ({
      id: c.id,
      label: c.label,
      isBlocked: c.isBlocked,
      createdAt: c.createdAt,
      user: minimalUser(c.contact),
    }));

    return res.json({ contacts: list });
  } catch (err) {
    console.error('listContacts error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
}

/**
 * DELETE /api/contacts/:userId
 * Remove a specific contact from my list
 */
async function removeContact(req, res) {
  try {
    const ownerUserId = req.user?.userId;
    if (!ownerUserId) return res.status(401).json({ error: 'unauthorized' });

    const contactUserId = req.params.userId;
    if (!contactUserId) return res.status(400).json({ error: 'missing_userId' });

    await prisma.contact.delete({
      where: { ownerUserId_contactUserId: { ownerUserId, contactUserId } },
    });

    return res.json({ ok: true });
  } catch (err) {
    if (err?.code === 'P2025') {
      // not found
      return res.json({ ok: true });
    }
    console.error('removeContact error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
}

module.exports = {
  lookupByPhone,
  matchContacts,
  addContact,
  listContacts,
  removeContact,
};
