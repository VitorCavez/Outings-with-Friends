// backend/src/controllers/imageController.js
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
const { deleteByPublicId } = require('../services/cloudinary');

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
 * multer provides req.file with Cloudinary info:
 *  - file.path (https URL)
 *  - file.filename (Cloudinary public_id)
 *  - file.width, file.height
 */
async function uploadOutingImage(req, res) {
  try {
    const { outingId } = req.params;

    if (!req.file) {
      return res.status(400).json({ ok: false, error: 'NO_FILE' });
    }

    // Optional: if your auth middleware injects req.user
    const uploaderId = req.user?.id ?? null;

    // Minimal validation: ensure outing exists
    const outing = await prisma.outing.findUnique({ where: { id: outingId } });
    if (!outing) {
      return res.status(404).json({ ok: false, error: 'OUTING_NOT_FOUND' });
    }

    // Save metadata in DB
    const created = await prisma.outingImage.create({
      data: {
        outingId,
        imageUrl: req.file.path,
        imageSource: 'cloudinary',
        provider: 'cloudinary',
        publicId: req.file.filename || null,
        width: req.file.width || null,
        height: req.file.height || null,
        blurHash: null, // (optional) could be set later
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
 * (Optionally restrict to uploader or outing host if req.user is available)
 */
async function deleteImage(req, res) {
  try {
    const { imageId } = req.params;

    const image = await prisma.outingImage.findUnique({
      where: { id: imageId },
      include: { outing: true },
    });

    if (!image) return res.status(404).json({ ok: false, error: 'IMAGE_NOT_FOUND' });

    // Optional authorization (works only if req.user is available from your auth middleware)
    // const isOwner = image.uploaderId && image.uploaderId === req.user?.id;
    // const isHost = image.outing?.createdById === req.user?.id;
    // if (!isOwner && !isHost) return res.status(403).json({ ok: false, error: 'FORBIDDEN' });

    // If cloudinary image, delete remote asset too
    if (image.provider === 'cloudinary' && image.publicId) {
      try { await deleteByPublicId(image.publicId); } catch (_) {}
    }

    await prisma.outingImage.delete({ where: { id: imageId } });
    return res.json({ ok: true });
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
