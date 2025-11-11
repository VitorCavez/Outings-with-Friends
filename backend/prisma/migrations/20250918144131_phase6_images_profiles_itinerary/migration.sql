-- CreateEnum
CREATE TYPE "ImageProvider" AS ENUM ('cloudinary', 'unsplash', 'external');

-- AlterTable
ALTER TABLE "OutingImage" ADD COLUMN     "authorLink" TEXT,
ADD COLUMN     "authorName" TEXT,
ADD COLUMN     "blurHash" TEXT,
ADD COLUMN     "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "height" INTEGER,
ADD COLUMN     "provider" "ImageProvider" NOT NULL DEFAULT 'external',
ADD COLUMN     "publicId" TEXT,
ADD COLUMN     "unsplashId" TEXT,
ADD COLUMN     "uploaderId" TEXT,
ADD COLUMN     "width" INTEGER;

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "badges" TEXT[] DEFAULT ARRAY[]::TEXT[];

-- CreateTable
CREATE TABLE "Favorite" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "outingId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Favorite_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ItineraryItem" (
    "id" TEXT NOT NULL,
    "outingId" TEXT NOT NULL,
    "orderIndex" INTEGER NOT NULL DEFAULT 0,
    "title" TEXT NOT NULL,
    "notes" TEXT,
    "locationName" TEXT,
    "latitude" DOUBLE PRECISION,
    "longitude" DOUBLE PRECISION,
    "startTime" TIMESTAMP(3),
    "endTime" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ItineraryItem_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Favorite_userId_idx" ON "Favorite"("userId");

-- CreateIndex
CREATE INDEX "Favorite_outingId_idx" ON "Favorite"("outingId");

-- CreateIndex
CREATE UNIQUE INDEX "Favorite_userId_outingId_key" ON "Favorite"("userId", "outingId");

-- CreateIndex
CREATE INDEX "ItineraryItem_outingId_idx" ON "ItineraryItem"("outingId");

-- CreateIndex
CREATE INDEX "ItineraryItem_orderIndex_idx" ON "ItineraryItem"("orderIndex");

-- CreateIndex
CREATE INDEX "ItineraryItem_startTime_idx" ON "ItineraryItem"("startTime");

-- CreateIndex
CREATE INDEX "ItineraryItem_endTime_idx" ON "ItineraryItem"("endTime");

-- CreateIndex
CREATE INDEX "OutingImage_provider_idx" ON "OutingImage"("provider");

-- CreateIndex
CREATE INDEX "OutingImage_uploaderId_idx" ON "OutingImage"("uploaderId");

-- CreateIndex
CREATE INDEX "OutingImage_createdAt_idx" ON "OutingImage"("createdAt");

-- AddForeignKey
ALTER TABLE "OutingImage" ADD CONSTRAINT "OutingImage_uploaderId_fkey" FOREIGN KEY ("uploaderId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Favorite" ADD CONSTRAINT "Favorite_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Favorite" ADD CONSTRAINT "Favorite_outingId_fkey" FOREIGN KEY ("outingId") REFERENCES "Outing"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ItineraryItem" ADD CONSTRAINT "ItineraryItem_outingId_fkey" FOREIGN KEY ("outingId") REFERENCES "Outing"("id") ON DELETE CASCADE ON UPDATE CASCADE;
