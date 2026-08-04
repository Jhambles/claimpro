import { ClaimStatus, PolicyCategory, PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { ClaimWithRelations, IClaimRepository } from "./interfaces";

const CLAIM_INCLUDE = {
  user: { select: { id: true, name: true, email: true } },
  documents: true,
  loa: true,
  payments: true,
} as const;

// Concrete Prisma implementation of IClaimRepository (SRP: persistence only,
// no business rules — those live in ClaimService).
export class PrismaClaimRepository implements IClaimRepository {
  constructor(private readonly db: PrismaClient = prisma) {}

  findMany(filter: { userId?: string; status?: ClaimStatus }): Promise<ClaimWithRelations[]> {
    return this.db.claim.findMany({
      where: { userId: filter.userId, status: filter.status },
      include: CLAIM_INCLUDE,
      orderBy: { createdAt: "desc" },
    });
  }

  findById(id: string): Promise<ClaimWithRelations | null> {
    return this.db.claim.findUnique({ where: { id }, include: CLAIM_INCLUDE });
  }

  create(data: { userId: string; category: PolicyCategory; estimate: number; referenceId: string }): Promise<ClaimWithRelations> {
    return this.db.claim.create({
      data: {
        userId: data.userId,
        category: data.category,
        estimate: data.estimate,
        referenceId: data.referenceId,
      },
      include: CLAIM_INCLUDE,
    });
  }

  updateStatus(id: string, status: ClaimStatus, processorId: string): Promise<ClaimWithRelations> {
    return this.db.claim.update({
      where: { id },
      data: { status, processorId },
      include: CLAIM_INCLUDE,
    });
  }

  count(): Promise<number> {
    return this.db.claim.count();
  }

  countByStatus(status: ClaimStatus): Promise<number> {
    return this.db.claim.count({ where: { status } });
  }

  async countByCategory(): Promise<Record<PolicyCategory, number>> {
    const grouped = await this.db.claim.groupBy({ by: ["category"], _count: true });
    const result: Record<string, number> = { MEDICAL: 0, AUTOMOTIVE: 0, HOMEOWNERS: 0 };
    for (const g of grouped) result[g.category] = g._count;
    return result as Record<PolicyCategory, number>;
  }

  async countByUserAndStatus(userId: string): Promise<Record<ClaimStatus, number>> {
    const grouped = await this.db.claim.groupBy({ by: ["status"], where: { userId }, _count: true });
    const result: Record<string, number> = { PENDING: 0, VERIFIED: 0, APPROVED: 0, REJECTED: 0 };
    for (const g of grouped) result[g.status] = g._count;
    return result as Record<ClaimStatus, number>;
  }

  async countByProcessorAndStatus(processorId: string): Promise<Record<ClaimStatus, number>> {
    const grouped = await this.db.claim.groupBy({ by: ["status"], where: { processorId }, _count: true });
    const result: Record<string, number> = { PENDING: 0, VERIFIED: 0, APPROVED: 0, REJECTED: 0 };
    for (const g of grouped) result[g.status] = g._count;
    return result as Record<ClaimStatus, number>;
  }
}
