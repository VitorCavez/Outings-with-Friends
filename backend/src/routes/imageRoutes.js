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

module.exports = router;
