// backend/src/jobs/saverModeJob.js
/**
 * Saver Mode auto-toggle based on "spend spike" proxy:
 * - We treat "upload volume spike" as a spend spike (Cloudinary/storage/network).
 * - If last 24h uploads exceed baseline avg/day * MULTIPLIER (and MIN_UPLOADS),
 *   we flip saverMode ON.
 *
 * Env overrides:
 * - SAVER_MODE=true                -> always ON
 * - SAVER_MODE_FORCE=true/false    -> hard force ON/OFF
 * - SAVER_MODE_MIN_UPLOADS=30      -> minimum uploads in last 24h to consider spike
 * - SAVER_MODE_MULTIPLIER=1.8      -> multiplier over baseline avg/day
 * - SAVER_MODE_CHECK_MINUTES=30    -> how often to recalc
 */

function envBool(name) {
  const v = (process.env[name] || '').toLowerCase().trim();
  if (v === 'true') return true;
  if (v === 'false') return false;
  return null;
}

function envInt(name, def) {
  const v = parseInt(process.env[name] || '', 10);
  return Number.isFinite(v) ? v : def;
}

function envFloat(name, def) {
  const v = parseFloat(process.env[name] || '');
  return Number.isFinite(v) ? v : def;
}

async function computeSaverMode(prisma) {
  const now = new Date();

  // Windows
  const last24hStart = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const baselineDays = 7;

  // Baseline excludes last 24h: [now - (baselineDays+1)d, now - 1d)
  const baselineStart = new Date(now.getTime() - (baselineDays + 1) * 24 * 60 * 60 * 1000);
  const baselineEnd = last24hStart;

  const [recentCount, baselineCount] = await Promise.all([
    prisma.outingImage.count({
      where: { createdAt: { gte: last24hStart, lte: now } },
    }),
    prisma.outingImage.count({
      where: { createdAt: { gte: baselineStart, lt: baselineEnd } },
    }),
  ]);

  const avgPerDay = baselineCount / baselineDays; // avg uploads/day (previous 7 days)
  const multiplier = envFloat('SAVER_MODE_MULTIPLIER', 1.8);
  const minUploads = envInt('SAVER_MODE_MIN_UPLOADS', 30);

  const threshold = Math.max(minUploads, Math.ceil(avgPerDay * multiplier));
  const spike = recentCount >= threshold;

  return {
    enabled: spike,
    reason: spike
      ? `upload_spike: last24h=${recentCount} >= threshold=${threshold} (avg/day=${avgPerDay.toFixed(
          1
        )}, x${multiplier})`
      : `normal: last24h=${recentCount} < threshold=${threshold} (avg/day=${avgPerDay.toFixed(
          1
        )}, x${multiplier})`,
    updatedAt: now.toISOString(),
    metrics: {
      last24h: recentCount,
      baseline7dCount: baselineCount,
      baselineAvgPerDay: avgPerDay,
      threshold,
      multiplier,
      minUploads,
    },
  };
}

function getPolicy(enabled) {
  // Defaults (normal mode)
  const normal = {
    maxPhotosPerOuting: envInt('IMAGE_MAX_PHOTOS_PER_OUTING', 10),
    pickerMaxWidth: envInt('IMAGE_PICKER_MAX_WIDTH', 1440),
    pickerMaxHeight: envInt('IMAGE_PICKER_MAX_HEIGHT', 1440),
    pickerQuality: envInt('IMAGE_PICKER_QUALITY', 85),
    compressQuality: envInt('IMAGE_COMPRESS_QUALITY', 75),
  };

  // Saver policy (tighter)
  const saver = {
    maxPhotosPerOuting: envInt('SAVER_IMAGE_MAX_PHOTOS_PER_OUTING', 6),
    pickerMaxWidth: envInt('SAVER_IMAGE_PICKER_MAX_WIDTH', 1024),
    pickerMaxHeight: envInt('SAVER_IMAGE_PICKER_MAX_HEIGHT', 1024),
    pickerQuality: envInt('SAVER_IMAGE_PICKER_QUALITY', 72),
    compressQuality: envInt('SAVER_IMAGE_COMPRESS_QUALITY', 60),
  };

  return enabled ? saver : normal;
}

function initSaverModeJob(app, prisma) {
  if (!app || !prisma) throw new Error('initSaverModeJob requires (app, prisma)');

  // Initialize state
  if (!app.locals) app.locals = {};
  if (!app.locals.saverMode) {
    app.locals.saverMode = {
      enabled: false,
      reason: 'init',
      updatedAt: new Date().toISOString(),
      metrics: null,
    };
  }

  const checkMinutes = envInt('SAVER_MODE_CHECK_MINUTES', 30);

  async function refresh() {
    // Hard force override wins
    const forced = envBool('SAVER_MODE_FORCE');
    const alwaysOn = envBool('SAVER_MODE'); // legacy/simple switch

    if (forced !== null) {
      const st = {
        enabled: forced,
        reason: `forced:${forced}`,
        updatedAt: new Date().toISOString(),
        metrics: null,
      };
      app.locals.saverMode = st;
      app.locals.imageUploadPolicy = getPolicy(st.enabled);
      return;
    }

    if (alwaysOn === true) {
      const st = {
        enabled: true,
        reason: 'env:SAVER_MODE=true',
        updatedAt: new Date().toISOString(),
        metrics: null,
      };
      app.locals.saverMode = st;
      app.locals.imageUploadPolicy = getPolicy(true);
      return;
    }

    try {
      const st = await computeSaverMode(prisma);
      app.locals.saverMode = st;
      app.locals.imageUploadPolicy = getPolicy(st.enabled);
    } catch (e) {
      // Keep last state, but note error
      app.locals.saverMode = {
        ...(app.locals.saverMode || {}),
        reason: `error:${e?.message || e}`,
        updatedAt: new Date().toISOString(),
      };
      app.locals.imageUploadPolicy = getPolicy(app.locals.saverMode.enabled === true);
    }
  }

  // First run
  refresh().then(() => {
    console.log(
      `🧯 SaverMode initialized: enabled=${app.locals.saverMode.enabled} reason="${app.locals.saverMode.reason}"`
    );
  });

  // Schedule interval
  const ms = checkMinutes * 60 * 1000;
  setInterval(() => {
    refresh().then(() => {
      console.log(
        `🧯 SaverMode refreshed: enabled=${app.locals.saverMode.enabled} reason="${app.locals.saverMode.reason}"`
      );
    });
  }, ms).unref();
}

module.exports = { initSaverModeJob };
