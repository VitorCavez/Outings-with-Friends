// backend/src/routes/imageRoutes.js
const express = require('express');
const router = express.Router();
const { uploader } = require('../services/cloudinary');
const { listOutingImages, uploadOutingImage, deleteImage } = require('../controllers/imageController');

// If you have an auth middleware, require it here, e.g.:
// const { requireAuth } = require('../middleware/auth');

// List images for an outing
router.get('/api/outings/:outingId/images', /* requireAuth, */ listOutingImages);

// Upload image for an outing (multipart/form-data, field name "image")
router.post(
  '/api/outings/:outingId/images',
  /* requireAuth, */
  uploader.single('image'),
  uploadOutingImage
);

// Delete image by id
router.delete('/api/images/:imageId', /* requireAuth, */ deleteImage);

/** Defines its own /api/* paths */
router.get('/api/images/:id', async (req, res) => {
  try {
    const { id } = req.params;
    res.json({ id, url: null, caption: null });
  } catch (err) {
    console.error('imageRoutes error:', err);
    res.status(500).json({ error: 'Failed to load image' });
  }
});

module.exports = router;
