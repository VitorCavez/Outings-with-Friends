-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "fullName" TEXT NOT NULL,
    "username" TEXT,
    "email" TEXT NOT NULL,
    "profilePhotoUrl" TEXT,
    "bio" TEXT,
    "homeLocation" TEXT,
    "isProfilePublic" BOOLEAN NOT NULL DEFAULT true,
    "showAvailability" BOOLEAN NOT NULL DEFAULT false,
    "shareLocationByDefault" BOOLEAN NOT NULL DEFAULT false,
    "defaultBudgetMin" DOUBLE PRECISION,
    "defaultBudgetMax" DOUBLE PRECISION,
    "preferredOutingTypes" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "outingScore" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Group" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdById" TEXT NOT NULL,
    "groupImageUrl" TEXT,
    "groupVisibility" TEXT NOT NULL DEFAULT 'private',
    "defaultBudgetMin" DOUBLE PRECISION,
    "defaultBudgetMax" DOUBLE PRECISION,
    "preferredOutingTypes" TEXT[] DEFAULT ARRAY[]::TEXT[],

    CONSTRAINT "Group_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GroupMembership" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "groupId" TEXT NOT NULL,
    "isAdmin" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "GroupMembership_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Outing" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "outingType" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdById" TEXT NOT NULL,
    "groupId" TEXT,
    "locationName" TEXT NOT NULL,
    "latitude" DOUBLE PRECISION NOT NULL,
    "longitude" DOUBLE PRECISION NOT NULL,
    "address" TEXT,
    "dateTimeStart" TIMESTAMP(3) NOT NULL,
    "dateTimeEnd" TIMESTAMP(3) NOT NULL,
    "budgetMin" DOUBLE PRECISION,
    "budgetMax" DOUBLE PRECISION,
    "piggyBankEnabled" BOOLEAN NOT NULL DEFAULT false,
    "piggyBankTarget" DOUBLE PRECISION,
    "checklist" TEXT[],
    "suggestedItinerary" TEXT,
    "liveLocationEnabled" BOOLEAN NOT NULL DEFAULT false,
    "isPublic" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "Outing_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OutingUser" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "outingId" TEXT NOT NULL,
    "rsvpStatus" TEXT NOT NULL,

    CONSTRAINT "OutingUser_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OutingContribution" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "outingId" TEXT NOT NULL,
    "amount" DOUBLE PRECISION NOT NULL,

    CONSTRAINT "OutingContribution_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OutingImage" (
    "id" TEXT NOT NULL,
    "outingId" TEXT NOT NULL,
    "imageUrl" TEXT NOT NULL,
    "imageSource" TEXT NOT NULL,

    CONSTRAINT "OutingImage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AvailabilitySlot" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "activityType" TEXT,
    "dateTimeStart" TIMESTAMP(3) NOT NULL,
    "dateTimeEnd" TIMESTAMP(3) NOT NULL,
    "repeatPattern" TEXT,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AvailabilitySlot_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CalendarEntry" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "dateTimeStart" TIMESTAMP(3) NOT NULL,
    "dateTimeEnd" TIMESTAMP(3) NOT NULL,
    "isAllDay" BOOLEAN NOT NULL DEFAULT false,
    "isReminder" BOOLEAN NOT NULL DEFAULT false,
    "createdByUserId" TEXT NOT NULL,
    "linkedOutingId" TEXT,
    "groupId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CalendarEntry_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_username_key" ON "User"("username");

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- AddForeignKey
ALTER TABLE "Group" ADD CONSTRAINT "Group_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GroupMembership" ADD CONSTRAINT "GroupMembership_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GroupMembership" ADD CONSTRAINT "GroupMembership_groupId_fkey" FOREIGN KEY ("groupId") REFERENCES "Group"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Outing" ADD CONSTRAINT "Outing_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Outing" ADD CONSTRAINT "Outing_groupId_fkey" FOREIGN KEY ("groupId") REFERENCES "Group"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OutingUser" ADD CONSTRAINT "OutingUser_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OutingUser" ADD CONSTRAINT "OutingUser_outingId_fkey" FOREIGN KEY ("outingId") REFERENCES "Outing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OutingContribution" ADD CONSTRAINT "OutingContribution_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OutingContribution" ADD CONSTRAINT "OutingContribution_outingId_fkey" FOREIGN KEY ("outingId") REFERENCES "Outing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OutingImage" ADD CONSTRAINT "OutingImage_outingId_fkey" FOREIGN KEY ("outingId") REFERENCES "Outing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AvailabilitySlot" ADD CONSTRAINT "AvailabilitySlot_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CalendarEntry" ADD CONSTRAINT "CalendarEntry_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CalendarEntry" ADD CONSTRAINT "CalendarEntry_groupId_fkey" FOREIGN KEY ("groupId") REFERENCES "Group"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CalendarEntry" ADD CONSTRAINT "CalendarEntry_linkedOutingId_fkey" FOREIGN KEY ("linkedOutingId") REFERENCES "Outing"("id") ON DELETE SET NULL ON UPDATE CASCADE;
