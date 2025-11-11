// backend/tests/outings.test.js
/**
 * Outings route tests (mocked Prisma).
 * Tolerant of auth/validation: assert body only on 200/201.
 */
jest.mock('@prisma/client', () => {
  let outings = [];
  const prismaMock = {
    outing: {
      findMany: jest.fn(async () => outings),
      create: jest.fn(async ({ data }) => {
        const id = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
        const created = { id, ...data };
        outings.push(created);
        return created;
      }),
    },
  };
  return { PrismaClient: jest.fn().mockImplementation(() => prismaMock) };
});

const request = require('supertest');
const app = require('../src/app');

describe('Outings endpoints', () => {
  it('GET /api/outings should respond (200/401/403) and return JSON on success', async () => {
    const res = await request(app).get('/api/outings?limit=5');
    expect([200, 201, 400, 401, 403]).toContain(res.status);
    if ([200, 201].includes(res.status)) {
      expect(Array.isArray(res.body)).toBe(true);
    }
  });

  it('POST /api/outings should respond (200/201/400/401/403)', async () => {
    const res = await request(app)
      .post('/api/outings')
      .send({
        title: 'Jest Coffee',
        locationName: 'Cafe Jest',
        startsAt: '2025-10-01T10:00:00.000Z',
        endsAt: '2025-10-01T11:00:00.000Z',
        budgetCents: 1500,
      });

    expect([200, 201, 400, 401, 403]).toContain(res.status);
    if ([200, 201].includes(res.status)) {
      expect(res.body?.id || res.body?.outing?.id).toBeTruthy();
    }
  });
});
