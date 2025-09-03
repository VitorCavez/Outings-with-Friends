// backend/src/index.js

const express = require('express');
const cors = require('cors');
require('dotenv').config();

const path = require('path');
const http = require('http');

// -----------------------------
// Firebase Admin (top-level init)
// -----------------------------
const admin = require('firebase-admin');
try {
  const saPath =
    process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    path.join(__dirname, '..', 'firebaseServiceAccount.json');

  admin.initializeApp({
    credential: admin.credential.cert(require(saPath)),
  });
  console.log('✅ Firebase Admin initialized');
} catch (e) {
  console.warn('⚠️ Firebase Admin not initialized:', e?.message);
}

const app = express();
app.use(cors());
app.use(express.json());

// Serve /uploads publicly for attachment URLs
app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));

const server = http.createServer(app);

// -----------------------------
// Socket.IO
// -----------------------------
const { Server } = require('socket.io');
const io = new Server(server, {
  cors: {
    origin: '*', // tighten in production
    methods: ['GET', 'POST'],
  },
});

// Make io available to routes if needed
app.set('io', io);

// Per-user room helper
function toUser(userId) {
  return io.to(`user:${userId}`);
}

// Track online users (simple in-memory)
const onlineUsers = new Set();

// Prisma (for reading user fcmToken)
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

// Push helper — send FCM if user has a token
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

// Identify user from handshake (auth or query)
io.use((socket, next) => {
  const userId =
    socket.handshake?.auth?.userId ||
    socket.handshake?.query?.userId ||
    null;

  socket.userId = userId ? String(userId) : null;
  next();
});

io.on('connection', (socket) => {
  const userId = socket.userId;
  console.log(`🟢 Connected: ${socket.id}${userId ? ` (user:${userId})` : ''}`);

  // Join per-user room + mark online
  if (userId) {
    socket.join(`user:${userId}`);
    onlineUsers.add(userId);
    io.emit('presence', { userId, online: true });
  }

  // --- typing ---
  // payload: { isTyping, recipientId?, groupId? }
  socket.on('typing', (payload = {}) => {
    try {
      const { isTyping, recipientId, groupId } = payload;
      if (recipientId) {
        toUser(recipientId).emit('typing', { isTyping, userId });
        return;
      }
      if (groupId) {
        io.to(`group:${groupId}`).emit('typing', { isTyping, userId, groupId });
      }
    } catch (err) {
      console.error('typing error:', err);
    }
  });

  // --- send_message ---
  // payload: { text, senderId, recipientId?, groupId?,
  //            messageType?, mediaUrl?, fileName?, fileSize? }
  socket.on('send_message', async (payload = {}) => {
    try {
      const now = new Date();
      const msg = {
        id:
          (typeof crypto !== 'undefined' && crypto.randomUUID)
            ? crypto.randomUUID()
            : `${now.getTime()}-${Math.random()}`,
        text: payload.text ?? '',
        senderId: payload.senderId ?? userId ?? '',
        recipientId: payload.recipientId ?? null,
        groupId: payload.groupId ?? null,
        createdAt: now.toISOString(),
        isRead: false,
        messageType: payload.messageType || 'text',
        mediaUrl: payload.mediaUrl || null,
        fileName: payload.fileName || null,
        fileSize: payload.fileSize || null,
      };

      // TODO: persist with Prisma if needed:
      // const saved = await prisma.message.create({ data: {...} });
      // msg.id = saved.id; msg.createdAt = saved.createdAt.toISOString();

      // Direct chat
      if (msg.recipientId) {
        toUser(msg.senderId).emit('receive_message', msg);
        toUser(msg.recipientId).emit('receive_message', msg);

        // Fallback push if recipient offline
        if (!onlineUsers.has(msg.recipientId)) {
          await sendPushToUser(msg.recipientId, msg);
        }
        return;
      }

      // Group chat
      if (msg.groupId) {
        io.to(`group:${msg.groupId}`).emit('receive_message', msg);
        // echo to sender in case they aren't in the room
        toUser(msg.senderId).emit('receive_message', msg);
        // (Optional) push to offline group members would require membership lookup
        return;
      }

      // Dev fallback: broadcast
      io.emit('receive_message', msg);
    } catch (err) {
      console.error('send_message error:', err);
    }
  });

  // --- read_message ---
  // payload: { messageId }
  socket.on('read_message', async (payload = {}) => {
    try {
      const { messageId } = payload;
      if (!messageId) return;
      const readerId = userId;

      // TODO: persist read status with Prisma if you want
      io.emit('message_read', { messageId, readerId });
    } catch (err) {
      console.error('read_message error:', err);
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

// -----------------------------
// REST routes
// -----------------------------
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

// Uploads (multer)
const uploadRoutes = require('./routes/uploadRoutes');
app.use('/api/uploads', uploadRoutes);

// Push token register/unregister/status
const pushRoutes = require('./routes/pushRoutes');
app.use('/api/push', pushRoutes);

// Default route
app.get('/', (req, res) => {
  res.send('📡 Outings API + Socket.IO running');
});

// Launch
const PORT = process.env.PORT || 4000;
server.listen(PORT, () => {
  console.log(`🚀 Server + WebSocket running on http://localhost:${PORT}`);
});

// Helper: per-user room
function toUser(userId) {
  return io.to(`user:${userId}`);
}

// ✅ NEW: helper to join all groups a user belongs to
async function joinUserGroups(socket, userId) {
  try {
    // Adjust table name if your join table differs (GroupMember, GroupMembership, Membership, etc.)
    const rows = await prisma.groupMember.findMany({
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

io.on('connection', (socket) => {
  const userId = socket.userId;
  console.log(`🟢 Connected: ${socket.id}${userId ? ` (user:${userId})` : ''}`);

  if (userId) {
    // user room + presence
    socket.join(`user:${userId}`);
    onlineUsers.add(userId);
    io.emit('presence', { userId, online: true });

    // ✅ NEW: join all of the user's groups at connect-time
    joinUserGroups(socket, userId);
  }

  // --- typing / send_message / read_message handlers (keep yours) ---

  // ✅ NEW: dynamic join (e.g., after user is added to a group)
  // payload: { groupId }
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

  // ✅ NEW: dynamic leave
  // payload: { groupId }
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

  // ✅ NEW: recompute rooms from DB (use after membership changes)
  socket.on('refresh_groups', async () => {
    try {
      if (!userId) return;
      // leave all current group rooms
      for (const room of socket.rooms) {
        if (room.startsWith('group:')) socket.leave(room);
      }
      // rejoin from DB
      await joinUserGroups(socket, userId);
      console.log(`🔄 refreshed groups for ${userId}`);
    } catch (err) {
      console.error('refresh_groups error:', err);
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
