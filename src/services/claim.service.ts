import { ClaimStatus, PolicyCategory, Role } from "@prisma/client";
import { IClaimRepository } from "@/repositories/interfaces";
import { PrismaClaimRepository } from "@/repositories/claim.repository";
import { NotificationService } from "./notification.service";

// Business rules live here (SRP). Route handlers stay thin "controllers" that
// only translate HTTP <-> service calls; the service never touches req/res.
export class ClaimService {
  constructor(
    private readonly claims: IClaimRepository = new PrismaClaimRepository(),
    private readonly notifications: NotificationService = new NotificationService()
  ) {}

  private static readonly VALID_TRANSITIONS: Record<ClaimStatus, ClaimStatus[]> = {
    PENDING: ["VERIFIED", "REJECTED"],
    VERIFIED: ["APPROVED", "REJECTED"],
    APPROVED: [],
    REJECTED: [],
  };

  async listClaimsFor(user: { id: string; role: Role }) {
    if (user.role === "CLIENT") {
      return this.claims.findMany({ userId: user.id });
    }
    // Processors and admins see the full queue.
    return this.claims.findMany({});
  }

  getClaim(id: string) {
    return this.claims.findById(id);
  }

  async createClaim(userId: string, input: { category: PolicyCategory; estimate: number }) {
    // Number.isFinite rejects NaN and Infinity, unlike a bare `<= 0` check
    // (NaN <= 0 is false in JS, so a malformed estimate used to slip through).
    if (!Number.isFinite(input.estimate) || input.estimate <= 0) {
      throw new ServiceError("Claim estimate must be a valid number greater than zero.", 400);
    }

    // Reference IDs are derived from a count-based sequence, so two near-simultaneous
    // submissions can compute the same value. Retry a few times on the unique-constraint
    // collision instead of failing the request outright.
    const MAX_ATTEMPTS = 5;
    for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
      const referenceId = await this.generateReferenceId();
      try {
        return await this.claims.create({ userId, ...input, referenceId });
      } catch (err: any) {
        const isUniqueConflict = err?.code === "P2002";
        if (!isUniqueConflict || attempt === MAX_ATTEMPTS - 1) throw err;
      }
    }
    throw new ServiceError("Could not generate a unique reference ID. Please try again.", 500);
  }

  async transitionStatus(claimId: string, nextStatus: ClaimStatus, processorId: string) {
    const claim = await this.claims.findById(claimId);
    if (!claim) throw new ServiceError("Claim not found.", 404);

    const allowed = ClaimService.VALID_TRANSITIONS[claim.status];
    if (!allowed.includes(nextStatus)) {
      throw new ServiceError(`Cannot move claim from ${claim.status} to ${nextStatus}.`, 409);
    }

    const updated = await this.claims.updateStatus(claimId, nextStatus, processorId);
    try {
      // Awaited (not fire-and-forget): on a serverless runtime like Vercel, an
      // un-awaited promise can be cut off the instant the response is sent, so
      // a "best-effort" background write could silently never land.
      await this.notifications.notifyStatusChange(updated.userId, updated.referenceId, nextStatus, updated.id);
    } catch (err) {
      // A notification failure still shouldn't fail the (already-persisted) status change.
      console.error("Failed to create status-change notification:", err);
    }

    return updated;
  }

  private async generateReferenceId(): Promise<string> {
    const year = new Date().getFullYear();
    const count = await this.claims.count();
    // Mix in a short random suffix so two requests racing on the same `count`
    // don't produce the exact same reference ID (the retry loop above still
    // catches the rare remaining collision).
    const randomSuffix = Math.random().toString(36).slice(2, 5).toUpperCase();
    const sequence = (count + 1).toString(36).toUpperCase();
    return `CLM-${year}-X${sequence}${randomSuffix}`;
  }
}

export class ServiceError extends Error {
  constructor(message: string, public readonly statusCode: number) {
    super(message);
    this.name = "ServiceError";
  }
}
