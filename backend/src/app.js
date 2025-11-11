// backend/src/app.js
require('dotenv').config();

const path = require('path');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

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
/* ---------------- Core app/proxy settings ---------------- */
app.set('trust proxy', 1); // behind Render/Ingress

/* ---------------- Security & Ops middleware -------------- */
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

app.use(compression());

// concise logs in prod, detailed elsewhere
app.use(
  morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev')
);

/* ---------------- CORS ----------------------------------- */
const allowList = (process.env.CORS_ORIGINS || process.env.CORS_ORIGIN || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

// In non-prod, allow all to avoid local dev pain.
const allowAll = allowList.length === 0 || process.env.NODE_ENV !== 'production';

const corsOptions = {
  origin: (origin, cb) => {
    // allow non-browser clients (curl, Postman) and same-origin
    if (!origin) return cb(null, true);
    if (!origin) return cb(null, true); // mobile apps / curl
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

  methods: ['GET', 'HEAD', 'PUT', 'PATCH', 'POST', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  optionsSuccessStatus: 204,
};

app.use(cors(corsOptions));
app.options(/.*/, cors(corsOptions));

/* ---------------- Parsers & statics ---------------------- */
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true, limit: '1mb' }));

// public uploads
app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));

/* ---------------- Health/ready probes -------------------- */
// Fast and stable for Render’s health check.
app.get('/healthz', (req, res) => {
  res.type('text/plain').send('ok');
});

// Optional friendly root page (plain text avoids 502 HTML confusion)
app.get('/', (req, res) => {
  res.type('text/plain').send('📡 Outings API running. See /healthz and /api/*');
});

/* ---------------- Rate limiting (API only) --------------- */
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 300,

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

/* ---------------- Routes -------------------------------- */

// DEV helpers (only when not production)
if (process.env.NODE_ENV !== 'production') {
  const devRoutes = require('./routes/devRoutes');
  app.use('/dev', express.json(), devRoutes);
}

// Users
const usersRoutes = require('./routes/users');
app.use('/api/users', usersRoutes);

// Auth
const authRoutes = require('./routes/auth');
app.use('/api/auth', authRoutes);

// Groups
const groupRoutes = require('./routes/groupRoutes');
app.use('/api/groups', groupRoutes);

// Group invites (shares /api/groups/* paths)
const groupInviteRoutes = require('./routes/groupInviteRoutes');
app.use('/api/groups', groupInviteRoutes);

// Group social (module defines its own /api/... paths)
const groupSocialRoutes = require('./routes/groupSocialRoutes');
app.use(groupSocialRoutes);

// Outings / RSVP
const outingRoutes = require('./routes/outingRoutes');
app.use('/api/outings', outingRoutes);

const rsvpRoutes = require('./routes/rsvpRoutes');
app.use('/api/rsvp', rsvpRoutes);

// Availability / Calendar
const availabilityRoutes = require('./routes/availabilityRoutes');
app.use('/api/availability', availabilityRoutes);

const calendarRoutes = require('./routes/calendarRoutes');
app.use('/api/calendar', calendarRoutes);

// Messages / DM
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
  
// Uploads (signed URLs, etc.)
const uploadRoutes = require('./routes/uploadRoutes');
app.use('/api/uploads', uploadRoutes);

// Push registration
const pushRoutes = require('./routes/pushRoutes');
app.use('/api/push', pushRoutes);

// Discover (⚠️ moved under /api)
const discoverRoutes = require('./routes/discoverRoutes');
// If the router exports paths like GET /discover, this makes it /api/discover
app.use('/api', discoverRoutes);

// Images / Unsplash (modules define their own /api/* if applicable)
const imageRoutes = require('./routes/imageRoutes');
app.use(imageRoutes);

const unsplashRoutes = require('./routes/unsplashRoutes');
app.use(unsplashRoutes);

// Profile / Itinerary / Favorites (modules define their own /api/*)
const profileRoutes = require('./routes/profileRoutes');
app.use(profileRoutes);

const itineraryRoutes = require('./routes/itineraryRoutes');
app.use(itineraryRoutes);

const favoriteRoutes = require('./routes/favoriteRoutes');
app.use(favoriteRoutes);

// Contacts / Invites
const contactRoutes = require('./routes/contactRoutes');
app.use('/api/contacts', contactRoutes);

const inviteRoutes = require('./routes/inviteRoutes');
app.use('/api/invites', inviteRoutes);

// Geo / Places (modules define their own /api/*)
const geoRoutes = require('./routes/geoRoutes');
app.use(geoRoutes);

const placeRoutes = require('./routes/placeRoutes');
app.use(placeRoutes);

/* ---------------- 404 & Errors --------------------------- */
app.use((req, res) => {
  res.status(404).json({ error: 'Not found', path: req.originalUrl });
});

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  if (process.env.NODE_ENV !== 'test') {
    console.error('❌ Error:', err);
  }
  const status = err.status || 500;
  res.status(status).json({
    error: err.message || 'Server error',
  });
});

module.exports = app;
