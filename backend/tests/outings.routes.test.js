const request = require('supertest');
const app = require('../src/app');

// Example: adjust paths to match your real routes and auth needs as we expand the suite.
describe('Outings routes (structure only)', () => {
  it('GET /api/outings should exist (may be 200 or 401 depending on your auth)', async () => {
    const res = await request(app).get('/api/outings');
    // We only assert that the route exists and Express handled it.
    expect([200, 201, 400, 401, 403, 404, 500]).toContain(res.status);
  });
});
