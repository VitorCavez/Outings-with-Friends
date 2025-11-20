-- Add missing column on existing DBs (idempotent) 
ALTER TABLE "User" 
ADD COLUMN IF NOT EXISTS "allowPublicInvites" BOOLEAN NOT NULL DEFAULT false; 
