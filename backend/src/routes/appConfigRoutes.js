// backend/src/routes/appConfigRoutes.js
const express = require('express');
const router = express.Router();

/**
 * GET /api/app/config
 * Returns:
 * - saverMode (flag + reason)
 * - imageUploadPolicy (limits/quality tuned for normal vs saver)
 *
 * Keep it lightweight: safe to be public for app UX.
 */
router.get('/api/app/config', (req, res) => {
  const saverMode = req.app.locals?.saverMode || {
    enabled: false,
    reason: 'default',
    updatedAt: new Date().toISOString(),
  };

  const policy = req.app.locals?.imageUploadPolicy || {
    maxPhotosPerOuting: 10,
    pickerMaxWidth: 1440,
    pickerMaxHeight: 1440,
    pickerQuality: 85,
    compressQuality: 75,
  };

  res.json({
    ok: true,
    data: {
      saverMode,
      imageUploadPolicy: policy,
    },
  });
});

module.exports = router;
