// backend/src/app.js
require('dotenv').config();

const path = require('path');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const compression = require('compression');
const morgan = require('morgan');

const app = express();

/* ---------------- Security & Ops middleware ---------------- */

// Helmet: sensible security headers
// Note: allow cross-origin images from /uploads if you host on a different origin
app.use(
  helmet({
    crossOriginResourcePolicy: { policy: 'cross-origin' },
  })
);

// CORS: allow all in dev; allow-list in production via env
// Set CORS_ORIGINS="https://app.example.com,https://admin.example.com" in prod
const allowList =
  (process.env.CORS_ORIGINS || process.env.CORS_ORIGIN || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

const allowAll = allowList.length === 0 || process.env.NODE_ENV !== 'production';

const corsOptions = {
  origin: (origin, cb) => {
    // allow non-browser clients (curl, Postman) and same-origin
    if (!origin) return cb(null, true);
    if (allowAll || allowList.includes(origin)) return cb(null, true);
    return cb(new Error('CORS: origin not allowed'));
  },
  credentials: true,
  methods: ['GET', 'HEAD', 'PUT', 'PATCH', 'POST', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  optionsSuccessStatus: 204,
};
app.use(cors(corsOptions));
// ✅ Express 5 compatible: use a RegExp (previous '(.*)' string caused path-to-regexp error)
app.options(/.*/, cors(corsOptions));

// Compression for responses
app.use(compression());

// Logging (skip during tests)
if (process.env.NODE_ENV !== 'test') {
  app.use(morgan('combined'));
}

// Body parsers with sane limits
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true, limit: '1mb' }));

// Public uploads for attachments
app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));

/* -------------------- Rate limiting -------------------- */
// Apply to all /api routes (adjust limits as needed)
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 min
  limit: 300,               // max requests per window per IP
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later.' },
});
app.use('/api', apiLimiter);

/* ------------------------ Routes ------------------------ */

// Health/ready probes
app.get('/healthz', (req, res) => {
  res.status(200).json({ ok: true, uptime: process.uptime() });
});

// REST routes
const authRoutes = require('./routes/auth');
app.use('/api/auth', authRoutes);

const groupRoutes = require('./routes/groupRoutes');
app.use('/api/groups', groupRoutes);

const outingRoutes = require('./routes/outingRoutes');
app.use('/api/outings', outingRoutes);

const rsvpRoutes = require('./routes/rsvpRoutes');
app.use('/api/rsvp', rsvpRoutes);

const availabilityRoutes = require('./routes/availabilityRoutes');
app.use('/api/availability', availabilityRoutes);

const calendarRoutes = require('./routes/calendarRoutes');
app.use('/api/calendar', calendarRoutes);

const messageRoutes = require('./routes/messageRoutes');
app.use('/api/messages', messageRoutes);

const dmRoutes = require('./routes/directMessages');
app.use('/api/dm', dmRoutes);

const uploadRoutes = require('./routes/uploadRoutes');
app.use('/api/uploads', uploadRoutes);

const pushRoutes = require('./routes/pushRoutes');
app.use('/api/push', pushRoutes);

const groupSocialRoutes = require('./routes/groupSocialRoutes');
app.use(groupSocialRoutes);

const groupInviteRoutes = require('./routes/groupInviteRoutes');
app.use('/api/groups', groupInviteRoutes);

// ✅ Phase 6 routes (existing)
const imageRoutes = require('./routes/imageRoutes');
app.use(imageRoutes); // routes contain full /api/... paths

const unsplashRoutes = require('./routes/unsplashRoutes');
app.use(unsplashRoutes); // routes contain full /api/... paths

// ✅ Phase 6 routes (profile + itinerary + favorites)
const profileRoutes = require('./routes/profileRoutes');
app.use(profileRoutes); // defines /api/users/:userId/...

const itineraryRoutes = require('./routes/itineraryRoutes');
app.use(itineraryRoutes); // assumes non-conflicting paths like /api/itinerary/...

const favoriteRoutes = require('./routes/favoriteRoutes');
// Ensure favoriteRoutes uses non-conflicting base paths (e.g., /api/favorites/...)
app.use(favoriteRoutes);

// Default root (health/info)
app.get('/', (req, res) => {
  res.send('📡 Outings API running (Express app)');
});

/* -------------------- 404 & Errors -------------------- */

// 404 handler
app.use((req, res, next) => {
  res.status(404).json({ error: 'Not found' });
});

// Error handler
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  const status = err.status || 500;
  if (process.env.NODE_ENV !== 'test') {
    console.error('❌ Error:', err);
  }
  res.status(status).json({
    error: err.message || 'Server error',
  });
});

module.exports = app;
