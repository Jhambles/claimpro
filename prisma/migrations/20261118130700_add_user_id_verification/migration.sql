CREATE TYPE "UserVerificationStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');

ALTER TABLE "users"
ADD COLUMN "verificationStatus" "UserVerificationStatus" NOT NULL DEFAULT 'APPROVED',
ADD COLUMN "idDocumentUrl" TEXT,
ADD COLUMN "idDocumentName" TEXT;
