// backend/src/routes/imageRoutes.js
const express = require('express');
const router = express.Router();

const { uploader } = require('../services/cloudinary');
const {
  listOutingImages,
  uploadOutingImage,
  deleteImage,
} = require('../controllers/imageController');

const { authenticateToken } = require('./auth_middleware');

// List images for an outing
// (You can remove authenticateToken here if you truly want this to be public.)
router.get(
  '/api/outings/:outingId/images',
  authenticateToken,
  listOutingImages
);

// Upload image for an outing (multipart/form-data, field name "image")
// Same endpoint is also used for JSON body (Unsplash URL); controller
// should handle both a file upload and { imageUrl, imageSource } payloads.
router.post(
  '/api/outings/:outingId/images',
  authenticateToken,
  uploader.single('image'),
  uploadOutingImage
);

// Delete image by id
// Frontend calls DELETE /api/images/:imageId
router.delete(
  '/api/images/:imageId',
  authenticateToken,
  deleteImage
);

// (Optional) Fetch single image metadata – kept simple for now.
router.get('/api/images/:id', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;
    // If you later store extra metadata for a single image,
    // you can look it up here. For now we just echo the id.
    res.json({ id, url: null, caption: null });
  } catch (err) {
    console.error('imageRoutes error:', err);
    res.status(500).json({ error: 'Failed to load image' });
  }
});

module.exports = router;
