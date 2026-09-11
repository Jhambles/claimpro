import { PaymentProvider } from "@prisma/client";
import { ILoaRepository } from "@/repositories/interfaces";
import { PrismaLoaRepository } from "@/repositories/loa.repository";
import { IClaimRepository } from "@/repositories/interfaces";
import { PrismaClaimRepository } from "@/repositories/claim.repository";
import { PayoutPreferenceService } from "./payout-preference.service";
import { ServiceError } from "./claim.service";

const PROVIDER_LABEL: Record<PaymentProvider, string> = {
  GCASH: "GCash",
  MAYA: "Maya",
  PAYPAL: "PayPal",
  BANK_TRANSFER: "Bank Transfer",
};

// Generates the Letter of Authorization text and persists it once a claim
// is APPROVED. Kept separate from ClaimService (SRP) since LOA formatting
// is a distinct responsibility from claim lifecycle rules.
export class LoaService {
  constructor(
    private readonly loas: ILoaRepository = new PrismaLoaRepository(),
    private readonly claims: IClaimRepository = new PrismaClaimRepository(),
    private readonly payoutPreferences: PayoutPreferenceService = new PayoutPreferenceService()
  ) {}

  async generateForClaim(claimId: string, generatedById: string) {
    const claim = await this.claims.findById(claimId);
    if (!claim) throw new ServiceError("Claim not found.", 404);
    if (claim.status !== "APPROVED") {
      throw new ServiceError("LOA can only be generated for approved claims.", 409);
    }
    // Already generated: return as-is. The provider named in the letter's
    // text is locked in at first generation â€” re-deriving it from whatever
    // the claimant's Settings preference happens to be *now* would risk the
    // letter's printed text and the QR silently disagreeing.
    if (claim.loa) return claim.loa;

    const preference = await this.payoutPreferences.get(claim.userId);
    const provider: PaymentProvider = preference?.provider ?? "GCASH";

    const content = this.buildLetter(claim.referenceId, claim.category, claim.user.name, provider);
    return this.loas.createForClaim(claimId, content, generatedById, provider);
  }

  private buildLetter(referenceId: string, category: string, claimantName: string, provider: PaymentProvider): string {
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
      `Scan the QR code below to claim your payout via ${PROVIDER_LABEL[provider]}.`,
      "",
      "Signature: ________________",
      "Claims Administrator",
    ].join("\n");
  }
}
