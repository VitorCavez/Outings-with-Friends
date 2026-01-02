// backend/src/index.js
const path = require('path');
const http = require('http');

// Load .env only for local/dev. Do NOT override platform vars (like PORT) on Render.
const isProduction = process.env.NODE_ENV === 'production';
const isRender = !!process.env.RENDER || !!process.env.RENDER_INTERNAL_HOSTNAME;
if (!isProduction && !isRender) {
  require('dotenv').config({
    path: path.join(__dirname, '..', '.env'),
    override: false,
  });
}

// -----------------------------
// Firebase Admin (top-level init)
// -----------------------------
const admin = require('firebase-admin');
try {
  let credential;

  if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    // Prefer inline JSON for PaaS (Render/Railway/Heroku)
    const json = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    credential = admin.credential.cert(json);
  } else {
    // Fallback to file path for local dev
    const saPath =
      process.env.GOOGLE_APPLICATION_CREDENTIALS ||
      path.join(__dirname, '..', 'firebaseServiceAccount.json');
    credential = admin.credential.cert(require(saPath));
  }

  admin.initializeApp({ credential });
  console.log(
    `✅ Firebase Admin initialized (${process.env.FIREBASE_SERVICE_ACCOUNT_JSON ? 'env JSON' : 'file'})`
  );
} catch (e) {
  console.warn('⚠️ Firebase Admin not initialized:', e?.message);
}

// Bring in the Express app (no server started here)
const app = require('./app');

// ✅ Trust proxy so real client IP is visible behind Render/Ingress
app.set('trust proxy', 1);

// Create HTTP server and bind Socket.IO
const server = http.createServer(app);

// -----------------------------
// Socket.IO
// -----------------------------
// Make crypto available (Node 16+)
try {
  const { webcrypto } = require('node:crypto');
  if (webcrypto) globalThis.crypto = webcrypto;
} catch (_) {}

/**
 * Align Socket.IO CORS with API CORS:
 * - In production: use allow-list from CORS_ORIGINS (comma-separated)
 * - In dev / if not set: allow all
 */
const allowList = (process.env.CORS_ORIGINS || process.env.CORS_ORIGIN || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);
const allowAll = allowList.length === 0 || !isProduction;
const ioCorsOrigin = allowAll ? '*' : allowList;

const { Server } = require('socket.io');
const io = new Server(server, {
  cors: { origin: ioCorsOrigin, methods: ['GET', 'POST'] },
});

// Make io available to routes if needed
app.set('io', io);

// Track online users (simple in-memory)
const onlineUsers = new Set();

// Prisma (for DB work incl. FCM token + groups)
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

// Saver Mode auto-toggle + policy
const { initSaverModeJob } = require('./jobs/saverModeJob');
initSaverModeJob(app, prisma);

// -----------------------------
// ✅ Image retention job (thumb-only after N days)
// -----------------------------
const { startImageRetentionJob } = require('./jobs/imageRetentionJob');
startImageRetentionJob();

// ---- Helpers -------------------------------------------------
function toUser(userId) {
  return io.to(`user:${userId}`);
}

async function sendPushToUser(userId, data) {
  try {
    const u = await prisma.user.findUnique({
      where: { id: userId },
      select: { fcmToken: true },
    });
    const token = u?.fcmToken;
    if (!token) return;

    await admin.messaging().send({
      token,
      notification: {
        title: 'New message',
        body: data.text || 'You have a new message',
      },
      data: {
        senderId: data.senderId || '',
        recipientId: data.recipientId || '',
        groupId: data.groupId || '',
        messageId: data.id || '',
        messageType: data.messageType || 'text',
        mediaUrl: data.mediaUrl || '',
      },
    });
  } catch (err) {
    console.error('push error:', err);
  }
}

// Join all group rooms a user belongs to
async function joinUserGroups(socket, userId) {
  try {
    const rows = await prisma.groupMembership.findMany({
      where: { userId },
      select: { groupId: true },
    });
    for (const r of rows) {
      socket.join(`group:${r.groupId}`);
    }
    console.log(`👥 user ${userId} joined ${rows.length} group rooms`);
  } catch (err) {
    console.error('joinUserGroups error:', err);
  }
}

// Identify user from handshake (auth or query)
io.use((socket, next) => {
  const userId =
    socket.handshake?.auth?.userId ||
    socket.handshake?.query?.userId ||
    null;
  socket.userId = userId ? String(userId) : null;
  next();
});

// ---- Single connection handler -------------------------------
io.on('connection', (socket) => {
  const userId = socket.userId;
  console.log(`🟢 Connected: ${socket.id}${userId ? ` (user:${userId})` : ''}`);

  if (userId) {
    socket.join(`user:${userId}`);
    onlineUsers.add(userId);
    io.emit('presence', { userId, online: true });
    // Join group rooms at connect time
    joinUserGroups(socket, userId);
  }

  // typing: { isTyping, recipientId?, groupId? }
  socket.on('typing', (payload = {}) => {
    try {
      const { isTyping, recipientId, groupId } = payload;
      if (recipientId) {
        toUser(recipientId).emit('typing', { isTyping: !!isTyping, userId });
      } else if (groupId) {
        io.to(`group:${groupId}`).emit('typing', { isTyping: !!isTyping, userId, groupId });
      }
    } catch (err) {
      console.error('typing error:', err);
    }
  });

  /**
   * send_message:
   * { text, senderId, recipientId?, groupId?, messageType?, mediaUrl?, fileName?, fileSize? }
   * ✅ Persist with Prisma, then emit to the relevant rooms.
   */
  socket.on('send_message', async (payload = {}) => {
    try {
      const now = new Date();
      const data = {
        text: payload.text ?? '',
        senderId: (payload.senderId ?? userId ?? '').toString(),
        recipientId: payload.recipientId ? String(payload.recipientId) : null,
        groupId: payload.groupId ? String(payload.groupId) : null,
        messageType: payload.messageType || 'text',
        mediaUrl: payload.mediaUrl || null,
        fileName: payload.fileName || null,
        fileSize: payload.fileSize ?? null,
        createdAt: now,
      };

      // Basic guard: require either recipientId or groupId
      if (!data.recipientId && !data.groupId) return;

      // ✅ Persist
      const saved = await prisma.message.create({
        data: {
          text: data.text,
          senderId: data.senderId,
          recipientId: data.recipientId,
          groupId: data.groupId,
          messageType: data.messageType,
          mediaUrl: data.mediaUrl,
          fileName: data.fileName,
          fileSize: data.fileSize,
        },
        select: {
          id: true,
          text: true,
          senderId: true,
          recipientId: true,
          groupId: true,
          createdAt: true,
          isRead: true,
          messageType: true,
          mediaUrl: true,
          fileName: true,
          fileSize: true,
          readAt: true,
        },
      });

      const msgPayload = {
        id: saved.id,
        text: saved.text,
        senderId: saved.senderId,
        recipientId: saved.recipientId,
        groupId: saved.groupId,
        createdAt: saved.createdAt,
        isRead: saved.isRead ?? false,
        messageType: saved.messageType || 'text',
        mediaUrl: saved.mediaUrl || null,
        fileName: saved.fileName || null,
        fileSize: saved.fileSize || null,
        readAt: saved.readAt || null,
      };

      if (saved.recipientId) {
        // direct: echo to both participants
        toUser(saved.senderId).emit('receive_message', msgPayload);
        toUser(saved.recipientId).emit('receive_message', msgPayload);

        // push for offline recipient
        if (!onlineUsers.has(saved.recipientId)) {
          await sendPushToUser(saved.recipientId, msgPayload);
        }
        return;
      }

      if (saved.groupId) {
        // group: emit to group room + echo to sender's user room
        io.to(`group:${saved.groupId}`).emit('receive_message', msgPayload);
        toUser(saved.senderId).emit('receive_message', msgPayload);
        return;
      }
    } catch (err) {
      console.error('send_message error:', err);
    }
  });

  // read_message: { messageId }
  socket.on('read_message', async (payload = {}) => {
    try {
      const { messageId } = payload;
      if (!messageId) return;
      const readerId = userId;

      // ✅ persist read status (best-effort)
      try {
        await prisma.message.update({
          where: { id: String(messageId) },
          data: { isRead: true, readAt: new Date() },
        });
      } catch (_) {
        // ignore if schema doesn't have readAt
        await prisma.message.update({
          where: { id: String(messageId) },
          data: { isRead: true },
        });
      }

      io.emit('message_read', { messageId, readerId });
    } catch (err) {
      console.error('read_message error:', err);
    }
  });

  // dynamic group joins/leaves/refresh
  socket.on('join_group', (payload = {}) => {
    try {
      const gid = String(payload.groupId || '').trim();
      if (!gid) return;
      socket.join(`group:${gid}`);
      console.log(`➕ ${userId} joined group:${gid}`);
    } catch (err) {
      console.error('join_group error:', err);
    }
  });

  socket.on('leave_group', (payload = {}) => {
    try {
      const gid = String(payload.groupId || '').trim();
      if (!gid) return;
      socket.leave(`group:${gid}`);
      console.log(`➖ ${userId} left group:${gid}`);
    } catch (err) {
      console.error('leave_group error:', err);
    }
  });

  socket.on('refresh_groups', async () => {
    try {
      if (!userId) return;
      for (const room of socket.rooms) {
        if (room.startsWith('group:')) socket.leave(room);
      }
      await joinUserGroups(socket, userId);
      console.log(`🔄 refreshed groups for ${userId}`);
    } catch (err) {
      console.error('refresh_groups error:', err);
    }
  });

  socket.on('presence_query', (payload = {}) => {
    try {
      const peer = String(payload.peerUserId || '').trim();
      if (!peer) return;
      const online = onlineUsers.has(peer);
      socket.emit('presence', { userId: peer, online });
    } catch (err) {
      console.error('presence_query error:', err);
    }
  });

  socket.on('disconnect', () => {
    console.log(`🔴 Disconnected: ${socket.id}${userId ? ` (user:${userId})` : ''}`);
    if (userId) {
      onlineUsers.delete(userId);
      io.emit('presence', { userId, online: false });
    }
  });
});

// Launch
const PORT = process.env.PORT || 4000; // Render sets PORT (e.g. 10000)
server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Server + WebSocket listening on 0.0.0.0:${PORT} (NODE_ENV=${process.env.NODE_ENV || 'development'})`);
});

/* ---------------- Graceful shutdown & error hooks ---------------- */
async function shutdown(signal) {
  try {
    console.log(`\n🛑 Received ${signal}, shutting down...`);
    try { await io.close(); } catch (_) {}
    try { await prisma.$disconnect(); } catch (_) {}
    server.close(() => {
      console.log('✅ HTTP server closed');
      process.exit(0);
    });
    setTimeout(() => process.exit(0), 5000).unref(); // safety
  } catch (err) {
    console.error('❌ Shutdown error:', err);
    process.exit(1);
  }
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('uncaughtException', (err) => console.error('💥 Uncaught exception:', err));
process.on('unhandledRejection', (reason) => console.error('💥 Unhandled rejection:', reason));
