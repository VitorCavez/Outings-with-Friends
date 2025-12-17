// backend/src/controllers/piggyBankController.js
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

function getAuthUserId(req) {
  // Match your JWT payload: { userId, email }
  return req.user?.userId || req.headers['x-user-id'] || null;
}

/**
 * DELETE /api/outings/:outingId/piggybank/contributions/:contributionId
 */
async function deletePiggyBankContribution(req, res) {
  try {
    const { outingId, contributionId } = req.params;
    const me = getAuthUserId(req);
    if (!me) {
      return res.status(401).json({ ok: false, error: 'AUTH_REQUIRED' });
    }

    const contrib = await prisma.piggyBankContribution.findUnique({
      where: { id: contributionId },
      include: { outing: true },
    });

    if (!contrib || contrib.outingId !== outingId) {
      return res
        .status(404)
        .json({ ok: false, error: 'CONTRIBUTION_NOT_FOUND' });
    }

    const isOwner = contrib.userId === me;
    const isOrganizer = contrib.outing.createdById === me;

    if (!isOwner && !isOrganizer) {
      return res.status(403).json({ ok: false, error: 'FORBIDDEN' });
    }

    await prisma.piggyBankContribution.delete({ where: { id: contributionId } });

    return res.json({ ok: true });
  } catch (err) {
    console.error('deletePiggyBankContribution error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
}

module.exports = {
  // ...any existing exports like createPiggyBankContribution, getPiggyBankSummary
  deletePiggyBankContribution,
};
