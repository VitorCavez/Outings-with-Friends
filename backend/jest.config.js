// backend/jest.config.js
module.exports = {
  testEnvironment: 'node',
  roots: ['<rootDir>/tests'],
  testMatch: ['**/*.test.js'],
  collectCoverageFrom: ['src/**/*.js'],
  coveragePathIgnorePatterns: [
    '/node_modules/',
    '/tests/',
    'src/index.js', // server bootstrap not covered
  ],
  verbose: true,

  // 👇 Map prisma imports to test doubles so we don't need a real DB in unit tests
  moduleNameMapper: {
    // Any import that ends with /prisma/client (e.g., ../../prisma/client)
    '.*/prisma/client$': '<rootDir>/tests/__mocks__/prismaClient.js',

    // Direct package import: @prisma/client
    '^@prisma/client$': '<rootDir>/tests/__mocks__/prismaPkg.js',
  },
};
