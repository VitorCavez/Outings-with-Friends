// backend/src/routes/uploadRoutes.js
const express = require('express');
const multer = require('multer');
const fs = require('fs');
const path = require('path');

const router = express.Router();

// Ensure uploads dir exists: backend/uploads
const uploadsDir = path.join(__dirname, '..', '..', 'uploads');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

// Configure multer storage (filename keeps original, prefixed with timestamp)
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, uploadsDir);
  },
  filename: function (req, file, cb) {
    const safe = file.originalname.replace(/[^a-zA-Z0-9.\-_]/g, '_');
    cb(null, `${Date.now()}_${safe}`);
  },
});

const upload = multer({
  storage,
  limits: {
    fileSize: 25 * 1024 * 1024, // 25 MB (adjust as needed)
  },
});

// POST /api/uploads
// form-data: field "file" = <binary>
router.post('/', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }

    const filename = req.file.filename;
    const fileSize = req.file.size;

    // Public URL to the uploaded file
    const base = process.env.PUBLIC_BASE_URL || `http://localhost:${process.env.PORT || 4000}`;
    const url = `${base}/uploads/${filename}`;

    return res.status(201).json({
      url,
      fileName: req.file.originalname,
      fileSize,
      mimeType: req.file.mimetype,
    });
  } catch (err) {
    console.error('Upload error:', err);
    return res.status(500).json({ error: 'Upload failed' });
  }
});

module.exports = router;
