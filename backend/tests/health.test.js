const request = require('supertest');
const app = require('../src/app');

describe('Health & routing smoke tests', () => {
  it('GET / should respond 200 and contain a health string', async () => {
    const res = await request(app).get('/');
    expect(res.status).toBe(200);
    expect(res.text).toMatch(/Outings API/i);
  });

  it('Non-existent route should return 404 (Express default)', async () => {
    const res = await request(app).get('/definitely-not-here');
    // Express by default returns 404 with empty body for unknown routes
    expect(res.status).toBe(404);
  });
});
