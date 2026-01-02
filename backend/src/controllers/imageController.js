// backend/src/controllers/imageController.js
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
const { deleteByPublicId } = require('../services/cloudinary');

const MAX_PHOTOS_PER_OUTING = 10;

/**
 * GET /api/outings/:outingId/images
 */
async function listOutingImages(req, res) {
  try {
    const { outingId } = req.params;

    const images = await prisma.outingImage.findMany({
      where: { outingId },
      orderBy: { createdAt: 'desc' },
    });

    return res.json({ ok: true, data: images });
  } catch (err) {
    console.error('listOutingImages error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
}

/**
 * POST /api/outings/:outingId/images
 *
 * Supports BOTH:
 *  1) multipart/form-data with field name "image" (Cloudinary via multer)
 *  2) JSON body: { "imageUrl": "...", "imageSource": "unsplash" }
 */
async function uploadOutingImage(req, res) {
  try {
    const { outingId } = req.params;

    // Optional: if your auth middleware injects req.user
    const uploaderId = req.user?.id ?? null;

    // Ensure outing exists
    const outing = await prisma.outing.findUnique({ where: { id: outingId } });
    if (!outing) {
      return res.status(404).json({ ok: false, error: 'OUTING_NOT_FOUND' });
    }

    // Enforce limit on server too
    const existingCount = await prisma.outingImage.count({ where: { outingId } });
    if (existingCount >= MAX_PHOTOS_PER_OUTING) {
      return res.status(409).json({
        ok: false,
        error: 'IMAGE_LIMIT_REACHED',
        message: `Photo limit reached (${MAX_PHOTOS_PER_OUTING}). Delete one to add another.`,
      });
    }

    // CASE 1: multipart upload (Cloudinary)
    if (req.file) {
      const created = await prisma.outingImage.create({
        data: {
          outingId,
          imageUrl: req.file.path, // Cloudinary URL
          imageSource: 'cloudinary',
          provider: 'cloudinary',
          publicId: req.file.filename || null, // Cloudinary public_id
          width: req.file.width || null,
          height: req.file.height || null,
          blurHash: null,
          uploaderId,
        },
      });

      return res.status(201).json({ ok: true, data: created });
    }

    // CASE 2: JSON URL attach (e.g. Unsplash)
    const imageUrl = req.body?.imageUrl;
    const imageSource = req.body?.imageSource || req.body?.provider || 'external';

    if (typeof imageUrl !== 'string' || imageUrl.trim().length < 8) {
      return res.status(400).json({ ok: false, error: 'INVALID_IMAGE_URL' });
    }

    // Light validation: must be http(s)
    let parsed;
    try {
      parsed = new URL(imageUrl);
    } catch (_) {
      return res.status(400).json({ ok: false, error: 'INVALID_IMAGE_URL' });
    }
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return res.status(400).json({ ok: false, error: 'INVALID_IMAGE_URL' });
    }

    // Derive provider
    const host = (parsed.hostname || '').toLowerCase();
    let provider = 'external';
    if (imageSource === 'unsplash' || host.includes('unsplash.com')) {
      provider = 'unsplash';
    }

    const created = await prisma.outingImage.create({
      data: {
        outingId,
        imageUrl: imageUrl.trim(),
        imageSource: imageSource,
        provider: provider,
        publicId: null,
        width: null,
        height: null,
        blurHash: null,
        uploaderId,
      },
    });

    return res.status(201).json({ ok: true, data: created });
  } catch (err) {
    console.error('uploadOutingImage error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
}

/**
 * DELETE /api/images/:imageId
 */
async function deleteImage(req, res) {
  try {
    const { imageId } = req.params;

    const image = await prisma.outingImage.findUnique({
      where: { id: imageId },
      include: { outing: true },
    });

    if (!image) {
      return res.status(404).json({ ok: false, error: 'IMAGE_NOT_FOUND' });
    }

    // Optional authorization (enable if you want restrictions)
    // const isOwner = image.uploaderId && image.uploaderId === req.user?.id;
    // const isHost = image.outing?.createdById === req.user?.id;
    // if (!isOwner && !isHost) return res.status(403).json({ ok: false, error: 'FORBIDDEN' });

    // If Cloudinary image, delete remote asset too
    if (image.provider === 'cloudinary' && image.publicId) {
      try {
        await deleteByPublicId(image.publicId);
      } catch (_) {
        // ignore cloudinary delete errors
      }
    }

    await prisma.outingImage.delete({ where: { id: imageId } });
    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error('deleteImage error:', err);
    return res.status(500).json({ ok: false, error: 'SERVER_ERROR' });
  }
}

module.exports = {
  listOutingImages,
  uploadOutingImage,
  deleteImage,
};
