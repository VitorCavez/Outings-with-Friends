// backend/tests/__mocks__/prismaPkg.js
// Mock for `@prisma/client`. Provides a PrismaClient class that returns
// a lightweight client compatible with routes we touch in tests.

class PrismaClient {
  constructor() {
    return {
      user: {
        findUnique: async () => null,
        create: async ({ data }) => ({ id: 'u_test', ...data }),
        update: async ({ where, data }) => ({ id: where?.id || 'u_test', ...data }),
      },
      groupMembership: {
        findMany: async () => [],
      },
      outing: {
        findMany: async () => [],
        create: async ({ data }) => ({ id: 'o_test', ...data }),
      },
    };
  }
}

module.exports = { PrismaClient };
