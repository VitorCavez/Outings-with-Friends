// backend/tests/__mocks__/prismaClient.js
// Mock for local wrapper imports like require('../../prisma/client')
// Keep it minimal: enough shape so requiring controllers/routes doesn't crash.

const prismaMock = {
  user: {
    findUnique: async () => null,
    create: async ({ data }) => ({ id: 'u_test', ...data }),
    update: async ({ data, where }) => ({ id: where?.id || 'u_test', ...data }),
  },
  groupMembership: {
    findMany: async () => [], // used by joinUserGroups()
  },
  outing: {
    findMany: async () => [],
    create: async ({ data }) => ({ id: 'o_test', ...data }),
  },
  // add other models if a specific test needs them later
};

module.exports = prismaMock;
