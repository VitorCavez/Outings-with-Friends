-- Add the missing columns safely (idempotent)
ALTER TABLE "User"
  ADD COLUMN IF NOT EXISTS "phoneE164" TEXT,
  ADD COLUMN IF NOT EXISTS "allowPublicInvites" BOOLEAN NOT NULL DEFAULT false;

-- Match Prisma’s expected unique index name
CREATE UNIQUE INDEX IF NOT EXISTS "User_phoneE164_key" ON "User"("phoneE164");
