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
      return res.status(400).json({ error: 'invalid_phone', reason: norm.reason || 'normalize_failed' });
    }

    const user = await prisma.user.findUnique({
      where: { phoneE164: norm.e164 },
      select: { id: true, fullName: true, profilePhotoUrl: true, isProfilePublic: true, allowPublicInvites: true },
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
        return res.status(400).json({ error: 'invalid_phone', reason: norm.reason || 'normalize_failed' });
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
  addContact,
  listContacts,
  removeContact,
};
