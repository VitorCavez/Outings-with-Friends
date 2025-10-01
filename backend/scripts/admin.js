#!/usr/bin/env node
/* backend/scripts/admin.js
 * Simple admin CLI for Outings
 *
 * Usage examples:
 *   node backend/scripts/admin.js stats
 *   node backend/scripts/admin.js env:check
 *   node backend/scripts/admin.js backup:print
 */

require('dotenv').config();
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

function redacted(v, keep = 6) {
  if (!v) return '';
  const s = String(v);
  if (s.length <= keep) return '***';
  return s.slice(0, keep) + '…';
}

async function cmdStats() {
  try {
    // List public tables and count each
    const tables = await prisma.$queryRawUnsafe(`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
      ORDER BY table_name;
    `);

    const results = {};
    for (const row of tables) {
      const t = row.table_name;
      try {
        const cnt = await prisma.$queryRawUnsafe(
          `SELECT COUNT(*)::int AS c FROM "${t}";`
        );
        results[t] = cnt?.[0]?.c ?? 0;
      } catch (e) {
        results[t] = `error: ${e.message}`;
      }
    }

    console.log(JSON.stringify({ ok: true, stats: results }, null, 2));
  } finally {
    await prisma.$disconnect();
  }
}

async function cmdEnvCheck() {
  try {
    const out = {
      NODE_ENV: process.env.NODE_ENV || '(not set)',
      PORT: process.env.PORT || '(not set)',
      DATABASE_URL: redacted(process.env.DATABASE_URL),
      CORS_ORIGINS: process.env.CORS_ORIGINS || process.env.CORS_ORIGIN || '(not set)',
      GOOGLE_APPLICATION_CREDENTIALS: process.env.GOOGLE_APPLICATION_CREDENTIALS || '(not set)',
      // If you later move to inline JSON for Firebase:
      FIREBASE_SERVICE_ACCOUNT_JSON: process.env.FIREBASE_SERVICE_ACCOUNT_JSON
        ? '(set)'
        : '(not set)',
    };

    const warnings = [];

    if (!process.env.DATABASE_URL) {
      warnings.push('DATABASE_URL is not set.');
    }
    if (process.env.NODE_ENV !== 'production') {
      warnings.push('NODE_ENV is not "production" (this is fine for local).');
    }
    if (!process.env.CORS_ORIGINS && process.env.NODE_ENV === 'production') {
      warnings.push('CORS_ORIGINS not set in production (will allow all).');
    }
    if (
      !process.env.GOOGLE_APPLICATION_CREDENTIALS &&
      !process.env.FIREBASE_SERVICE_ACCOUNT_JSON
    ) {
      warnings.push(
        'Firebase Admin: neither GOOGLE_APPLICATION_CREDENTIALS nor FIREBASE_SERVICE_ACCOUNT_JSON is set.'
      );
    }

    console.log(JSON.stringify({ ok: true, env: out, warnings }, null, 2));
  } finally {
    await prisma.$disconnect();
  }
}

async function cmdBackupPrint() {
  try {
    const url = process.env.DATABASE_URL || '(set DATABASE_URL first)';
    // Render/Railway usually have pg_dump available on their PG services or via jobs.
    const cmd =
      `pg_dump "${url}" --no-owner --format=c -f backup_$(date +%F).dump`;
    console.log(
      JSON.stringify(
        {
          ok: true,
          hint: 'Run this on a machine with pg_dump installed (or as a scheduled job).',
          command: cmd,
        },
        null,
        2
      )
    );
  } finally {
    await prisma.$disconnect();
  }
}

async function main() {
  const cmd = process.argv[2];
  switch (cmd) {
    case 'stats':
      await cmdStats();
      break;
    case 'env:check':
      await cmdEnvCheck();
      break;
    case 'backup:print':
      await cmdBackupPrint();
      break;
    default:
      console.log(
        JSON.stringify(
          {
            ok: false,
            error: 'Unknown command',
            usage: [
              'node backend/scripts/admin.js stats',
              'node backend/scripts/admin.js env:check',
              'node backend/scripts/admin.js backup:print',
            ],
          },
          null,
          2
        )
      );
      await prisma.$disconnect();
  }
}

main().catch(async (e) => {
  console.error(e);
  await prisma.$disconnect();
  process.exit(1);
});
