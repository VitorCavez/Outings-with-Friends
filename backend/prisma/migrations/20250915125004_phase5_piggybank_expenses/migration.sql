/*
  Warnings:

  - Added the required column `amountCents` to the `OutingContribution` table without a default value. This is not possible if the table is not empty.

*/
-- AlterTable
ALTER TABLE "Outing" ADD COLUMN     "piggyBankTargetCents" INTEGER;

-- AlterTable
ALTER TABLE "OutingContribution" ADD COLUMN     "amountCents" INTEGER NOT NULL,
ADD COLUMN     "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "note" TEXT,
ALTER COLUMN "amount" DROP NOT NULL;

-- CreateTable
CREATE TABLE "Expense" (
    "id" TEXT NOT NULL,
    "outingId" TEXT NOT NULL,
    "payerId" TEXT NOT NULL,
    "amountCents" INTEGER NOT NULL,
    "description" TEXT,
    "category" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Expense_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Expense_outingId_idx" ON "Expense"("outingId");

-- CreateIndex
CREATE INDEX "Expense_payerId_idx" ON "Expense"("payerId");

-- CreateIndex
CREATE INDEX "AvailabilitySlot_userId_idx" ON "AvailabilitySlot"("userId");

-- CreateIndex
CREATE INDEX "AvailabilitySlot_dateTimeStart_idx" ON "AvailabilitySlot"("dateTimeStart");

-- CreateIndex
CREATE INDEX "AvailabilitySlot_dateTimeEnd_idx" ON "AvailabilitySlot"("dateTimeEnd");

-- CreateIndex
CREATE INDEX "CalendarEntry_createdByUserId_idx" ON "CalendarEntry"("createdByUserId");

-- CreateIndex
CREATE INDEX "CalendarEntry_groupId_idx" ON "CalendarEntry"("groupId");

-- CreateIndex
CREATE INDEX "CalendarEntry_linkedOutingId_idx" ON "CalendarEntry"("linkedOutingId");

-- CreateIndex
CREATE INDEX "GroupMembership_userId_idx" ON "GroupMembership"("userId");

-- CreateIndex
CREATE INDEX "GroupMembership_groupId_idx" ON "GroupMembership"("groupId");

-- CreateIndex
CREATE INDEX "Message_senderId_idx" ON "Message"("senderId");

-- CreateIndex
CREATE INDEX "Message_createdAt_idx" ON "Message"("createdAt");

-- CreateIndex
CREATE INDEX "Outing_groupId_idx" ON "Outing"("groupId");

-- CreateIndex
CREATE INDEX "Outing_createdById_idx" ON "Outing"("createdById");

-- CreateIndex
CREATE INDEX "OutingContribution_outingId_idx" ON "OutingContribution"("outingId");

-- CreateIndex
CREATE INDEX "OutingContribution_userId_idx" ON "OutingContribution"("userId");

-- CreateIndex
CREATE INDEX "OutingContribution_outingId_userId_idx" ON "OutingContribution"("outingId", "userId");

-- CreateIndex
CREATE INDEX "OutingImage_outingId_idx" ON "OutingImage"("outingId");

-- CreateIndex
CREATE INDEX "OutingUser_userId_idx" ON "OutingUser"("userId");

-- CreateIndex
CREATE INDEX "OutingUser_outingId_idx" ON "OutingUser"("outingId");

-- AddForeignKey
ALTER TABLE "Expense" ADD CONSTRAINT "Expense_outingId_fkey" FOREIGN KEY ("outingId") REFERENCES "Outing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Expense" ADD CONSTRAINT "Expense_payerId_fkey" FOREIGN KEY ("payerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
