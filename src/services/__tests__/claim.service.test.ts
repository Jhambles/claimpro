import { ClaimService, ServiceError } from "@/services/claim.service";
import { ClaimValidationService } from "@/services/claim-validation.service";

function makeClaim(overrides: any = {}) {
  return {
    id: "claim_1",
    referenceId: "CLM-2026-X001",
    category: "HOMEOWNERS",
    estimate: 5000,
    status: "PENDING",
    userId: "user_1",
    processorId: null,
    createdAt: new Date(),
    updatedAt: new Date(),
    user: { id: "user_1", name: "Jane", email: "jane@example.com" },
    documents: [{ mimeType: "image/jpeg", sizeBytes: 1024, fileUrl: "x" }],
    loa: null,
    payments: [],
    ...overrides,
  };
}

function makeMocks(claim: any) {
  const claimRepo = {
    findById: jest.fn().mockResolvedValue(claim),
    updateStatus: jest.fn().mockImplementation((id, status, processorId) =>
      Promise.resolve({ ...claim, status, processorId })
    ),
    findMany: jest.fn(),
    create: jest.fn(),
    count: jest.fn(),
    countByStatus: jest.fn(),
    countByCategory: jest.fn(),
    countByUserAndStatus: jest.fn(),
    countByProcessorAndStatus: jest.fn(),
  };
  const notifications = { notifyStatusChange: jest.fn().mockResolvedValue(undefined) } as any;
  const audit = { log: jest.fn().mockResolvedValue(undefined) } as any;
  const decisions = { create: jest.fn().mockResolvedValue({}), listForClaim: jest.fn().mockResolvedValue([]) } as any;
  return { claimRepo, notifications, audit, decisions };
}

function build(claim: any) {
  const m = makeMocks(claim);
  const service = new ClaimService(m.claimRepo as any, m.notifications, m.audit, new ClaimValidationService(), m.decisions);
  return { service, ...m };
}

const REASON = "Documents reviewed and match the claim details.";

describe("ClaimService.transitionStatus", () => {
  it("allows PENDING -> VERIFIED", async () => {
    const { service, claimRepo } = build(makeClaim({ status: "PENDING" }));

    const result = await service.transitionStatus("claim_1", "VERIFIED", "staff_1", REASON);
    expect(result.status).toBe("VERIFIED");
    expect(claimRepo.updateStatus).toHaveBeenCalledWith("claim_1", "VERIFIED", "staff_1");
  });

  it("requires a reason - a missing or too-short reason is rejected before anything changes", async () => {
    const { service, claimRepo, decisions } = build(makeClaim({ status: "PENDING" }));

    await expect(service.transitionStatus("claim_1", "VERIFIED", "staff_1", "")).rejects.toMatchObject({ statusCode: 400 });
    await expect(service.transitionStatus("claim_1", "VERIFIED", "staff_1", "   ")).rejects.toMatchObject({ statusCode: 400 });
    await expect(service.transitionStatus("claim_1", "VERIFIED", "staff_1", "ok")).rejects.toMatchObject({ statusCode: 400 });
    expect(claimRepo.updateStatus).not.toHaveBeenCalled();
    expect(decisions.create).not.toHaveBeenCalled();
  });

  it("rejects an over-long reason", async () => {
    const { service, claimRepo } = build(makeClaim({ status: "PENDING" }));

    await expect(service.transitionStatus("claim_1", "REJECTED", "staff_1", "x".repeat(501))).rejects.toMatchObject({ statusCode: 400 });
    expect(claimRepo.updateStatus).not.toHaveBeenCalled();
  });

  it("records the decision with the trimmed reason and who made it", async () => {
    const { service, decisions } = build(makeClaim({ status: "PENDING" }));

    await service.transitionStatus("claim_1", "REJECTED", "staff_1", "  Photos do not match the report.  ", { name: "Staff", role: "PROCESSOR" });
    expect(decisions.create).toHaveBeenCalledWith(
      expect.objectContaining({
        claimId: "claim_1",
        status: "REJECTED",
        reason: "Photos do not match the report.",
        decidedById: "staff_1",
        decidedByName: "Staff",
        decidedByRole: "PROCESSOR",
      })
    );
  });

  it("passes the reason to the claimant's notification and the audit log", async () => {
    const { service, notifications, audit } = build(makeClaim({ status: "PENDING" }));

    await service.transitionStatus("claim_1", "REJECTED", "staff_1", "Policy had lapsed.", { name: "Staff", role: "PROCESSOR" });
    expect(notifications.notifyStatusChange).toHaveBeenCalledWith("user_1", "CLM-2026-X001", "REJECTED", "claim_1", "Policy had lapsed.");
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ detail: expect.stringContaining("Policy had lapsed.") }));
  });

  it("rejects an invalid transition (PENDING -> APPROVED, skipping VERIFIED)", async () => {
    const { service, claimRepo } = build(makeClaim({ status: "PENDING" }));

    await expect(service.transitionStatus("claim_1", "APPROVED", "staff_1", REASON)).rejects.toThrow(ServiceError);
    expect(claimRepo.updateStatus).not.toHaveBeenCalled();
  });

  it("blocks VERIFIED -> APPROVED when the claim has no documents", async () => {
    const { service, claimRepo } = build(makeClaim({ status: "VERIFIED", processorId: "staff_1", documents: [] }));

    await expect(service.transitionStatus("claim_1", "APPROVED", "staff_1", REASON)).rejects.toThrow(/unresolved issues/i);
    expect(claimRepo.updateStatus).not.toHaveBeenCalled();
  });

  it("allows VERIFIED -> APPROVED when the claim is complete", async () => {
    const { service, audit } = build(makeClaim({ status: "VERIFIED", processorId: "staff_1" }));

    const result = await service.transitionStatus("claim_1", "APPROVED", "staff_1", REASON, { name: "Staff", role: "PROCESSOR" });
    expect(result.status).toBe("APPROVED");
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: "CLAIM_STATUS_CHANGED" }));
  });

  it("still updates status even if the notification write fails", async () => {
    const { service, notifications } = build(makeClaim({ status: "PENDING" }));
    notifications.notifyStatusChange.mockRejectedValue(new Error("db down"));

    const result = await service.transitionStatus("claim_1", "VERIFIED", "staff_1", REASON);
    expect(result.status).toBe("VERIFIED");
  });

  it("still updates status even if recording the decision fails", async () => {
    const { service, decisions } = build(makeClaim({ status: "PENDING" }));
    decisions.create.mockRejectedValue(new Error("db down"));

    const result = await service.transitionStatus("claim_1", "VERIFIED", "staff_1", REASON);
    expect(result.status).toBe("VERIFIED");
  });

  it("throws 404 for a claim that doesn't exist", async () => {
    const { service, claimRepo } = build(null);
    claimRepo.findById.mockResolvedValue(null);

    await expect(service.transitionStatus("nope", "VERIFIED", "staff_1", REASON)).rejects.toMatchObject({ statusCode: 404 });
  });
});

describe("ClaimService.createClaim", () => {
  it("rejects a non-positive estimate", async () => {
    const { service } = build(null);

    await expect(service.createClaim("user_1", { category: "HOMEOWNERS" as any, estimate: 0 })).rejects.toThrow(ServiceError);
    await expect(service.createClaim("user_1", { category: "HOMEOWNERS" as any, estimate: NaN })).rejects.toThrow(ServiceError);
  });
});
