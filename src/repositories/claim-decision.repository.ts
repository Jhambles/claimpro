import { ClaimStatus, PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/prisma";

export interface DecisionRecord {
  id: string;
  claimId: string;
  status: ClaimStatus;
  reason: string;
  decidedById: string | null;
  decidedByName: string;
  decidedByRole: string;
  createdAt: Date;
}

export interface IClaimDecisionRepository {
  create(data: {
    claimId: string;
    status: ClaimStatus;
    reason: string;
    decidedById?: string;
    decidedByName: string;
    decidedByRole: string;
  }): Promise<DecisionRecord>;
  listForClaim(claimId: string): Promise<DecisionRecord[]>;
}

export class PrismaClaimDecisionRepository implements IClaimDecisionRepository {
  constructor(private readonly db: PrismaClient = prisma) {}

  create(data: {
    claimId: string;
    status: ClaimStatus;
    reason: string;
    decidedById?: string;
    decidedByName: string;
    decidedByRole: string;
  }) {
    return this.db.claimDecision.create({ data });
  }

  listForClaim(claimId: string) {
    return this.db.claimDecision.findMany({ where: { claimId }, orderBy: { createdAt: "asc" } });
  }
}
