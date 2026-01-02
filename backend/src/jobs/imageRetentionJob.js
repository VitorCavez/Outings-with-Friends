// backend/src/jobs/imageRetentionJob.js
const cron = require('node-cron');
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

const {
  createThumbnailAssetFromPublicId,
  deleteByPublicId,
  isThumbPublicId,
} = require('../services/cloudinary');

/**
 * Runs once: converts old Cloudinary images into thumb-only assets.
 * - Uploads a small thumbnail variant as a NEW Cloudinary asset (thumbs/*)
 * - Updates DB row to point to thumb URL/publicId
 * - Deletes original publicId
 */
async function runImageRetentionOnce() {
  const enabled = (process.env.IMAGE_RETENTION_ENABLED ?? 'true') === 'true';
  if (!enabled) return;

  const days = Number(process.env.IMAGE_RETENTION_DAYS ?? 90);
  const batchSize = Number(process.env.IMAGE_RETENTION_BATCH ?? 50);
  const thumbW = Number(process.env.IMAGE_THUMB_W ?? 720);
  const thumbH = Number(process.env.IMAGE_THUMB_H ?? 720);

  const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

  console.log(
    `[retention] start: days=${days}, cutoff=${cutoff.toISOString()}, batch=${batchSize}, thumb=${thumbW}x${thumbH}`
  );

  // Process in batches until none left
  // (keeps the job safe for big datasets)
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const items = await prisma.outingImage.findMany({
      where: {
        provider: 'cloudinary',
        createdAt: { lt: cutoff },
        publicId: { not: null },
      },
      orderBy: { createdAt: 'asc' },
      take: batchSize,
    });

    if (!items.length) break;

    for (const img of items) {
      const originalPublicId = img.publicId;

      // Safety guards
      if (!originalPublicId) continue;
      if (isThumbPublicId(originalPublicId)) continue; // already thumb-only

      try {
        // 1) Create thumbnail asset (NEW publicId under thumbs/)
        const thumbUpload = await createThumbnailAssetFromPublicId(
          originalPublicId,
          {
            thumbW,
            thumbH,
          }
        );

        // 2) Update DB to point to thumb asset
        await prisma.outingImage.update({
          where: { id: img.id },
          data: {
            imageUrl: thumbUpload.secure_url || thumbUpload.url,
            publicId: thumbUpload.public_id,
            width: thumbUpload.width ?? img.width,
            height: thumbUpload.height ?? img.height,
            // leave provider = cloudinary
            // keep imageSource as-is (cloudinary)
          },
        });

        // 3) Delete original full-size asset
        try {
          await deleteByPublicId(originalPublicId);
        } catch (e) {
          console.warn(
            `[retention] delete original failed publicId=${originalPublicId}:`,
            e?.message || e
          );
        }

        console.log(
          `[retention] converted -> thumb-only: imageId=${img.id} ${originalPublicId} -> ${thumbUpload.public_id}`
        );
      } catch (e) {
        console.error(
          `[retention] failed imageId=${img.id} publicId=${originalPublicId}:`,
          e?.message || e
        );
      }
    }
  }

  console.log('[retention] done');
}

/**
 * Call once at app startup.
 * Schedules daily job and (optionally) runs on boot.
 */
function startImageRetentionJob() {
  const enabled = (process.env.IMAGE_RETENTION_ENABLED ?? 'true') === 'true';
  if (!enabled) {
    console.log('[retention] disabled via IMAGE_RETENTION_ENABLED=false');
    return;
  }

  // Daily at 03:15 UTC (safe low-traffic default)
  const schedule = process.env.IMAGE_RETENTION_CRON ?? '15 3 * * *';
  cron.schedule(
    schedule,
    () => runImageRetentionOnce().catch((e) => console.error('[retention] run error:', e)),
    { timezone: process.env.IMAGE_RETENTION_TZ ?? 'UTC' }
  );

  console.log(`[retention] scheduled cron="${schedule}" tz="${process.env.IMAGE_RETENTION_TZ ?? 'UTC'}"`);

  // Optional: run shortly after boot (useful for testing)
  const runOnBoot = (process.env.IMAGE_RETENTION_RUN_ON_BOOT ?? 'false') === 'true';
  if (runOnBoot) {
    setTimeout(() => {
      runImageRetentionOnce().catch((e) => console.error('[retention] boot run error:', e));
    }, 12_000);
  }
}

module.exports = {
  startImageRetentionJob,
  runImageRetentionOnce,
};
