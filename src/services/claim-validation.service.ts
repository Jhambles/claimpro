import { ClaimWithRelations } from "@/repositories/interfaces";

export type IssueSeverity = "blocking" | "warning";

export interface ClaimIssue {
  code: string;
  severity: IssueSeverity;
  message: string;
}

// Runs entirely against data already loaded with the claim (documents, LOA,
// payments) â€” nothing here is cached or persisted, so it can never go stale:
// every call reflects the claim's current state at the moment it's asked for.
// "blocking" issues are checked by ClaimService before a claim is allowed to
// move to APPROVED; "warning" issues are surfaced to staff but don't block.
export class ClaimValidationService {
  private static readonly STALE_AFTER_DAYS = 14;

  evaluate(claim: ClaimWithRelations): ClaimIssue[] {
    const issues: ClaimIssue[] = [];

    // --- Missing information -------------------------------------------------
    if (claim.documents.length === 0) {
      issues.push({
        code: "NO_DOCUMENTS",
        severity: "blocking",
        message: "No supporting documents have been uploaded for this claim.",
      });
    } else if (!claim.documents.some((d) => d.mimeType.startsWith("image/"))) {
      issues.push({
        code: "NO_PHOTO_EVIDENCE",
        severity: "warning",
        message: "No photographic evidence has been uploaded â€” only non-image documents are on file.",
      });
    }

    if (!Number.isFinite(Number(claim.estimate)) || Number(claim.estimate) <= 0) {
      issues.push({
        code: "MISSING_ESTIMATE",
        severity: "blocking",
        message: "The claim has no valid estimated amount.",
      });
    }

    if ((claim.status === "APPROVED" || claim.status === "VERIFIED") && !claim.processorId) {
      issues.push({
        code: "NO_PROCESSOR_OF_RECORD",
        severity: "blocking",
        message: "The claim has moved past PENDING but has no processor of record assigned.",
      });
    }

    // --- Inconsistent information ---------------------------------------------
    const corruptDocs = claim.documents.filter((d) => d.sizeBytes <= 0 || !d.fileUrl);
    if (corruptDocs.length > 0) {
      issues.push({
        code: "CORRUPT_DOCUMENT",
        severity: "blocking",
        message: `${corruptDocs.length} uploaded document(s) appear empty or corrupted (0 bytes or missing file reference).`,
      });
    }

    const paidTotal = claim.payments.filter((p) => p.status === "PAID").reduce((sum, p) => sum + Number(p.amount), 0);
    if (paidTotal > Number(claim.estimate)) {
      issues.push({
        code: "PAYOUT_EXCEEDS_ESTIMATE",
        severity: "blocking",
        message: `Total paid out (PHP ${paidTotal.toLocaleString()}) exceeds the claim's estimated amount (PHP ${Number(claim.estimate).toLocaleString()}).`,
      });
    }

    const pendingProviders = new Set(claim.payments.filter((p) => p.status === "PENDING").map((p) => p.provider));
    if (pendingProviders.size > 1) {
      issues.push({
        code: "MULTIPLE_PENDING_PAYOUTS",
        severity: "warning",
        message: `Payout requests are pending across ${pendingProviders.size} different methods (${[...pendingProviders].join(", ")}) â€” confirm only one is actually completed to avoid a double payout.`,
      });
    }

    if (claim.status === "APPROVED" && !claim.loa) {
      issues.push({
        code: "APPROVED_WITHOUT_LOA",
        severity: "warning",
        message: "The claim is approved but no Letter of Authorization has been generated yet.",
      });
    }

    // --- Staleness (prevents stale/outdated info from being acted on) --------
    if (claim.status === "PENDING" || claim.status === "VERIFIED") {
      const ageDays = (Date.now() - new Date(claim.updatedAt).getTime()) / (1000 * 60 * 60 * 24);
      if (ageDays > ClaimValidationService.STALE_AFTER_DAYS) {
        issues.push({
          code: "STALE_CLAIM",
          severity: "warning",
          message: `This claim has had no status update in ${Math.floor(ageDays)} days â€” verify the information on file is still current before acting on it.`,
        });
      }
    }

    return issues;
  }

  hasBlockingIssues(claim: ClaimWithRelations): boolean {
    return this.evaluate(claim).some((i) => i.severity === "blocking");
  }
}
