/* scripts/backfill-membership-roles.js */
const { PrismaClient, GroupRole } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
  console.log('Backfilling GroupMembership.role from isAdmin…');

  // Admins
  const adminResult = await prisma.groupMembership.updateMany({
    where: { isAdmin: true },
    data: { role: GroupRole.admin },
  });
  console.log(`Promoted (legacy isAdmin=true) → admin: ${adminResult.count}`);

  // Everyone else
  const memberResult = await prisma.groupMembership.updateMany({
    where: { OR: [{ isAdmin: false }, { isAdmin: null }] },
    data: { role: GroupRole.member },
  });
  console.log(`Set others → member: ${memberResult.count}`);
}

main()
  .then(() => {
    console.log('Backfill complete ✅');
    return prisma.$disconnect();
  })
  .catch(async (e) => {
    console.error(e);
    await prisma.$disconnect();
    process.exit(1);
  });
