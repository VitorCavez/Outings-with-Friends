// backend/prisma/seed.js
/* eslint-disable no-console */
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const { PrismaClient } = require('@prisma/client');
const bcrypt = require('bcryptjs');

const prisma = new PrismaClient();

async function runSeed() {
  console.log('Seeding…');

  // Clear everything (child -> parent order)
  await prisma.$transaction([
    prisma.outingParticipant.deleteMany(),
    prisma.outingInvite.deleteMany(),
    prisma.outingImage.deleteMany(),
    prisma.outingContribution.deleteMany(),
    prisma.expense.deleteMany(),
    prisma.outingUser.deleteMany(),
    prisma.itineraryItem.deleteMany(),
    prisma.favorite.deleteMany(),
    prisma.calendarEntry.deleteMany(),
    prisma.message.deleteMany(),
    prisma.groupInvitation.deleteMany(),
    prisma.groupMembership.deleteMany(),
    prisma.outing.deleteMany(),
    prisma.group.deleteMany(),
    prisma.contact.deleteMany(),
    prisma.inviteRequest.deleteMany(),
    prisma.availabilitySlot.deleteMany(),
    prisma.user.deleteMany(),
  ]);

  // Users
  const pw = await bcrypt.hash('password123', 10);
  const [alice, bob, cara] = await Promise.all([
    prisma.user.create({
      data: {
        fullName: 'Alice Organizer',
        username: 'alice',
        email: 'alice@example.com',
        password: pw,
        phoneE164: '+15551110001',
        isProfilePublic: true,
        allowPublicInvites: true,
      },
    }),
    prisma.user.create({
      data: {
        fullName: 'Bob Friend',
        username: 'bob',
        email: 'bob@example.com',
        password: pw,
        phoneE164: '+15551110002',
      },
    }),
    prisma.user.create({
      data: {
        fullName: 'Cara Tester',
        username: 'cara',
        email: 'cara@example.com',
        password: pw,
        phoneE164: '+15551110003',
      },
    }),
  ]);

  // Contacts (two-way graph: Alice<->Bob, Alice<->Cara, Bob<->Cara)
  await prisma.$transaction([
    prisma.contact.create({ data: { ownerUserId: alice.id, contactUserId: bob.id } }),
    prisma.contact.create({ data: { ownerUserId: bob.id,   contactUserId: alice.id } }),
    prisma.contact.create({ data: { ownerUserId: alice.id, contactUserId: cara.id } }),
    prisma.contact.create({ data: { ownerUserId: cara.id,  contactUserId: alice.id } }),
    prisma.contact.create({ data: { ownerUserId: bob.id,   contactUserId: cara.id } }),
    prisma.contact.create({ data: { ownerUserId: cara.id,  contactUserId: bob.id } }),
  ]);

  // One group (optional)
  const hikers = await prisma.group.create({
    data: {
      name: 'Weekend Hikers',
      createdById: alice.id,
      visibility: 'private',
      members: {
        create: [
          { userId: alice.id, isAdmin: true, role: 'admin' },
          { userId: bob.id,   isAdmin: false, role: 'member' },
        ],
      },
    },
  });

  // Outings
  const now = new Date();
  const in3d = new Date(now.getTime() + 3 * 86400000);
  const in3dEnd = new Date(in3d.getTime() + 3 * 3600000);

  const brunch = await prisma.outing.create({
    data: {
      title: 'Brunch @ Sunny Cafe',
      outingType: 'food',
      createdById: alice.id,
      locationName: 'Sunny Cafe',
      latitude: 37.7749,
      longitude: -122.4194,
      address: '123 Market St, San Francisco',
      dateTimeStart: in3d,
      dateTimeEnd: in3dEnd,
      isPublished: true,
      showOrganizer: true,
      visibility: 'INVITED',
      allowParticipantEdits: true,
      participants: {
        create: [
          { userId: alice.id, role: 'OWNER' },
        ],
      },
    },
  });

  const trail = await prisma.outing.create({
    data: {
      title: 'Trail Walk',
      outingType: 'outdoor',
      createdById: alice.id,
      groupId: hikers.id,
      locationName: 'Redwood Park',
      latitude: 37.88,
      longitude: -122.23,
      dateTimeStart: new Date(now.getTime() + 5 * 86400000),
      dateTimeEnd: new Date(now.getTime() + 5 * 86400000 + 2 * 3600000),
      isPublished: true,
      visibility: 'CONTACTS',
      participants: {
        create: [
          { userId: alice.id, role: 'OWNER' },
        ],
      },
    },
  });

  // Outing invites (seed with mixed styles)
  //  - Bob as a direct app user invite to brunch (PENDING)
  //  - Cara as a contact/email invite to brunch (PENDING)
  await prisma.$transaction([
    prisma.outingInvite.create({
      data: {
        outingId: brunch.id,
        inviterId: alice.id,
        inviteeUserId: bob.id,
        status: 'PENDING',              // matches schema enum
        role: 'PARTICIPANT',
        code: 'SEED-CODE-BOB',
      },
    }),
    prisma.outingInvite.create({
      data: {
        outingId: brunch.id,
        inviterId: alice.id,
        inviteeContact: 'cara@example.com',
        status: 'PENDING',
        role: 'PARTICIPANT',
        code: 'SEED-CODE-CARA',
      },
    }),
  ]);

  console.log('Seed complete.');
  console.table([
    { user: 'alice@example.com', id: alice.id },
    { user: 'bob@example.com',   id: bob.id   },
    { user: 'cara@example.com',  id: cara.id  },
  ]);
  console.table([
    { outing: 'Brunch', id: brunch.id },
    { outing: 'Trail',  id: trail.id  },
  ]);

  return { alice, bob, cara, brunch, trail };
}

if (require.main === module) {
  runSeed().then(() => prisma.$disconnect()).catch(async (e) => {
    console.error(e);
    await prisma.$disconnect();
    process.exit(1);
  });
}

module.exports = { runSeed };
