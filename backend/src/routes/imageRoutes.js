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

// Run multer ONLY when the request is multipart/form-data
function maybeUploadSingleImage(req, res, next) {
  // Some clients send "multipart/form-data; boundary=..."
  const isMultipart = req.is('multipart/form-data');
  if (!isMultipart) return next();

  // Delegate to multer middleware
  return uploader.single('image')(req, res, next);
}

// List images for an outing
router.get('/api/outings/:outingId/images', authenticateToken, listOutingImages);

// Create image for an outing
// - multipart/form-data (field "image") OR
// - JSON { imageUrl, imageSource }
router.post(
  '/api/outings/:outingId/images',
  authenticateToken,
  maybeUploadSingleImage,
  uploadOutingImage
);

// Delete image by id
router.delete('/api/images/:imageId', authenticateToken, deleteImage);

// (Optional) Fetch single image metadata – kept simple for now.
router.get('/api/images/:id', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;
    res.json({ id, url: null, caption: null });
  } catch (err) {
    console.error('imageRoutes error:', err);
    res.status(500).json({ error: 'Failed to load image' });
  }
});

module.exports = router;
