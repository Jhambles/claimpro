import { ClaimValidationService } from "@/services/claim-validation.service";
import { ClaimWithRelations } from "@/repositories/interfaces";

function baseClaim(overrides: Partial<ClaimWithRelations> = {}): ClaimWithRelations {
  return {
    id: "claim_1",
    referenceId: "CLM-2026-X001",
    category: "HOMEOWNERS",
    estimate: 5000 as any,
    status: "PENDING",
    userId: "user_1",
    processorId: null,
    createdAt: new Date(),
    updatedAt: new Date(),
    user: { id: "user_1", name: "Jane Dela Cruz", email: "jane@example.com" },
    documents: [{ id: "doc_1", claimId: "claim_1", fileName: "photo.jpg", fileUrl: "https://x/photo.jpg", mimeType: "image/jpeg", sizeBytes: 1024, uploadedAt: new Date() } as any],
    loa: null,
    payments: [],
    ...overrides,
  } as ClaimWithRelations;
}

describe("ClaimValidationService", () => {
  const service = new ClaimValidationService();

  it("flags a claim with no documents as blocking", () => {
    const claim = baseClaim({ documents: [] });
    const issues = service.evaluate(claim);
    expect(issues.map((i) => i.code)).toContain("NO_DOCUMENTS");
    expect(service.hasBlockingIssues(claim)).toBe(true);
  });

  it("warns (does not block) when documents exist but none are photos", () => {
    const claim = baseClaim({
      documents: [{ id: "doc_1", claimId: "claim_1", fileName: "notes.pdf", fileUrl: "https://x/notes.pdf", mimeType: "application/pdf", sizeBytes: 500, uploadedAt: new Date() } as any],
    });
    const issues = service.evaluate(claim);
    const issue = issues.find((i) => i.code === "NO_PHOTO_EVIDENCE");
    expect(issue?.severity).toBe("warning");
    expect(service.hasBlockingIssues(claim)).toBe(false);
  });

  it("flags a zero or missing estimate as blocking", () => {
    const claim = baseClaim({ estimate: 0 as any });
    expect(service.evaluate(claim).map((i) => i.code)).toContain("MISSING_ESTIMATE");
  });

  it("flags a VERIFIED/APPROVED claim with no processor of record as blocking", () => {
    const claim = baseClaim({ status: "VERIFIED", processorId: null });
    expect(service.evaluate(claim).map((i) => i.code)).toContain("NO_PROCESSOR_OF_RECORD");
  });

  it("flags corrupted (0-byte) documents as blocking", () => {
    const claim = baseClaim({
      documents: [{ id: "doc_1", claimId: "claim_1", fileName: "broken.jpg", fileUrl: "https://x/broken.jpg", mimeType: "image/jpeg", sizeBytes: 0, uploadedAt: new Date() } as any],
    });
    expect(service.evaluate(claim).map((i) => i.code)).toContain("CORRUPT_DOCUMENT");
  });

  it("flags when total paid exceeds the estimate", () => {
    const claim = baseClaim({
      estimate: 1000 as any,
      payments: [{ id: "p1", provider: "GCASH", amount: 1500 as any, status: "PAID" } as any],
    });
    expect(service.evaluate(claim).map((i) => i.code)).toContain("PAYOUT_EXCEEDS_ESTIMATE");
  });

  it("warns when multiple providers have pending payouts simultaneously", () => {
    const claim = baseClaim({
      payments: [
        { id: "p1", provider: "GCASH", amount: 500 as any, status: "PENDING" } as any,
        { id: "p2", provider: "MAYA", amount: 500 as any, status: "PENDING" } as any,
      ],
    });
    expect(service.evaluate(claim).map((i) => i.code)).toContain("MULTIPLE_PENDING_PAYOUTS");
  });

  it("warns when APPROVED without an LOA", () => {
    const claim = baseClaim({ status: "APPROVED", processorId: "staff_1", loa: null });
    expect(service.evaluate(claim).map((i) => i.code)).toContain("APPROVED_WITHOUT_LOA");
  });

  it("warns on a stale PENDING/VERIFIED claim (no update in 14+ days)", () => {
    const old = new Date();
    old.setDate(old.getDate() - 20);
    const claim = baseClaim({ status: "PENDING", updatedAt: old });
    expect(service.evaluate(claim).map((i) => i.code)).toContain("STALE_CLAIM");
  });

  it("returns no issues for a clean, complete PENDING claim", () => {
    const claim = baseClaim();
    expect(service.evaluate(claim)).toHaveLength(0);
    expect(service.hasBlockingIssues(claim)).toBe(false);
  });
});
