import { ILoaRepository } from "@/repositories/interfaces";
import { PrismaLoaRepository } from "@/repositories/loa.repository";
import { IClaimRepository } from "@/repositories/interfaces";
import { PrismaClaimRepository } from "@/repositories/claim.repository";
import { ServiceError } from "./claim.service";

// Generates the Letter of Authorization text and persists it once a claim
// is APPROVED. Kept separate from ClaimService (SRP) since LOA formatting
// is a distinct responsibility from claim lifecycle rules.
export class LoaService {
  constructor(
    private readonly loas: ILoaRepository = new PrismaLoaRepository(),
    private readonly claims: IClaimRepository = new PrismaClaimRepository()
  ) {}

  async generateForClaim(claimId: string, generatedById: string) {
    const claim = await this.claims.findById(claimId);
    if (!claim) throw new ServiceError("Claim not found.", 404);
    if (claim.status !== "APPROVED") {
      throw new ServiceError("LOA can only be generated for approved claims.", 409);
    }
    if (claim.loa) return claim.loa;

    const content = this.buildLetter(claim.referenceId, claim.category, claim.user.name);
    return this.loas.createForClaim(claimId, content, generatedById);
  }

  private buildLetter(referenceId: string, category: string, claimantName: string): string {
    const date = new Date().toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric" });
    return [
      "CLAIMS PRO INSURANCE",
      `Date: ${date}`,
      "",
      "LETTER OF AUTHORIZATION",
      "",
      "To Whom It May Concern,",
      "",
      `This document serves as formal authorization for Record #${referenceId}, filed by ${claimantName}.`,
      `The claim regarding ${category.toLowerCase()} coverage has been verified and approved for disbursement.`,
      "",
      "Scan the QR code below to claim your payout via GCash, Maya, or PayPal.",
      "",
      "Signature: ________________",
      "Claims Administrator",
    ].join("\n");
  }
}
