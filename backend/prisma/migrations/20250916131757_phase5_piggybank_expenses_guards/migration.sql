-- DropForeignKey
ALTER TABLE "AvailabilitySlot" DROP CONSTRAINT "AvailabilitySlot_userId_fkey";

-- DropForeignKey
ALTER TABLE "CalendarEntry" DROP CONSTRAINT "CalendarEntry_createdByUserId_fkey";

-- DropForeignKey
ALTER TABLE "Expense" DROP CONSTRAINT "Expense_outingId_fkey";

-- DropForeignKey
ALTER TABLE "Expense" DROP CONSTRAINT "Expense_payerId_fkey";

-- DropForeignKey
ALTER TABLE "GroupMembership" DROP CONSTRAINT "GroupMembership_groupId_fkey";

-- DropForeignKey
ALTER TABLE "GroupMembership" DROP CONSTRAINT "GroupMembership_userId_fkey";

-- DropForeignKey
ALTER TABLE "OutingContribution" DROP CONSTRAINT "OutingContribution_outingId_fkey";

-- DropForeignKey
ALTER TABLE "OutingContribution" DROP CONSTRAINT "OutingContribution_userId_fkey";

-- DropForeignKey
ALTER TABLE "OutingImage" DROP CONSTRAINT "OutingImage_outingId_fkey";

-- DropForeignKey
ALTER TABLE "OutingUser" DROP CONSTRAINT "OutingUser_outingId_fkey";

-- DropForeignKey
ALTER TABLE "OutingUser" DROP CONSTRAINT "OutingUser_userId_fkey";

-- AlterTable
ALTER TABLE "Outing" ALTER COLUMN "checklist" SET DEFAULT ARRAY[]::TEXT[];

-- AddForeignKey
ALTER TABLE "GroupMembership" ADD CONSTRAINT "GroupMembership_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GroupMembership" ADD CONSTRAINT "GroupMembership_groupId_fkey" FOREIGN KEY ("groupId") REFERENCES "Group"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OutingUser" ADD CONSTRAINT "OutingUser_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OutingUser" ADD CONSTRAINT "OutingUser_outingId_fkey" FOREIGN KEY ("outingId") REFERENCES "Outing"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OutingContribution" ADD CONSTRAINT "OutingContribution_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OutingContribution" ADD CONSTRAINT "OutingContribution_outingId_fkey" FOREIGN KEY ("outingId") REFERENCES "Outing"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Expense" ADD CONSTRAINT "Expense_outingId_fkey" FOREIGN KEY ("outingId") REFERENCES "Outing"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Expense" ADD CONSTRAINT "Expense_payerId_fkey" FOREIGN KEY ("payerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OutingImage" ADD CONSTRAINT "OutingImage_outingId_fkey" FOREIGN KEY ("outingId") REFERENCES "Outing"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AvailabilitySlot" ADD CONSTRAINT "AvailabilitySlot_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CalendarEntry" ADD CONSTRAINT "CalendarEntry_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
