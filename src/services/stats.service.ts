import { IClaimRepository } from "@/repositories/interfaces";
import { PrismaClaimRepository } from "@/repositories/claim.repository";
import { ILoaRepository } from "@/repositories/interfaces";
import { PrismaLoaRepository } from "@/repositories/loa.repository";
import { SystemStats } from "@/types";

// Aggregates the numbers shown on the Admin "System Health" dashboard.
export class StatsService {
  constructor(
    private readonly claims: IClaimRepository = new PrismaClaimRepository(),
    private readonly loas: ILoaRepository = new PrismaLoaRepository()
  ) {}

  async getSystemStats(): Promise<SystemStats> {
    const [total, approved, loaCount, byCategory] = await Promise.all([
      this.claims.count(),
      this.claims.countByStatus("APPROVED"),
      this.loas.count(),
      this.claims.countByCategory(),
    ]);

    return {
      totalRequests: total,
      approvalRate: total === 0 ? 0 : Math.round((approved / total) * 1000) / 10,
      loaGenerationRate: approved === 0 ? 0 : Math.round((loaCount / approved) * 1000) / 10,
      claimsByCategory: byCategory,
    };
  }
}
