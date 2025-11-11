// backend/src/services/cloudinary.js
const { v2: cloudinary } = require('cloudinary');
const multer = require('multer');
const { CloudinaryStorage } = require('multer-storage-cloudinary');

const {
  CLOUDINARY_CLOUD_NAME,
  CLOUDINARY_API_KEY,
  CLOUDINARY_API_SECRET,
} = process.env;

if (!CLOUDINARY_CLOUD_NAME || !CLOUDINARY_API_KEY || !CLOUDINARY_API_SECRET) {
  console.warn('[cloudinary] Missing Cloudinary env vars. Uploads will fail.');
}

cloudinary.config({
  cloud_name: CLOUDINARY_CLOUD_NAME,
  api_key: CLOUDINARY_API_KEY,
  api_secret: CLOUDINARY_API_SECRET,
});

const storage = new CloudinaryStorage({
  cloudinary,
  params: async (req, file) => {
    return {
      folder: 'outings',
      resource_type: 'image',
      allowed_formats: ['jpg', 'jpeg', 'png', 'webp', 'heic'],
      transformation: [{ quality: 'auto', fetch_format: 'auto' }],
    };
  },
});

// 10 MB per image (adjust if you like)
const uploader = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 },
});

async function deleteByPublicId(publicId) {
  if (!publicId) return null;
  try {
    const res = await cloudinary.uploader.destroy(publicId, { resource_type: 'image' });
    return res;
  } catch (err) {
    console.error('[cloudinary] delete error:', err);
    throw err;
  }
}

module.exports = {
  cloudinary,
  uploader,
  deleteByPublicId,
};
