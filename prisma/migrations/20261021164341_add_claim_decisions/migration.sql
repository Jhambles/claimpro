-- CreateTable
CREATE TABLE "claim_decisions" (
    "id" TEXT NOT NULL,
    "claimId" TEXT NOT NULL,
    "status" "ClaimStatus" NOT NULL,
    "reason" TEXT NOT NULL,
    "decidedById" TEXT,
    "decidedByName" TEXT NOT NULL,
    "decidedByRole" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "claim_decisions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "claim_decisions_claimId_createdAt_idx" ON "claim_decisions"("claimId", "createdAt");

-- AddForeignKey
ALTER TABLE "claim_decisions" ADD CONSTRAINT "claim_decisions_claimId_fkey" FOREIGN KEY ("claimId") REFERENCES "claims"("id") ON DELETE CASCADE ON UPDATE CASCADE;
