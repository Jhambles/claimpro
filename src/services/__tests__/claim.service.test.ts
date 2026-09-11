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
  return { claimRepo, notifications, audit };
}

describe("ClaimService.transitionStatus", () => {
  it("allows PENDING -> VERIFIED", async () => {
    const claim = makeClaim({ status: "PENDING" });
    const { claimRepo, notifications, audit } = makeMocks(claim);
    const service = new ClaimService(claimRepo as any, notifications, audit, new ClaimValidationService());

    const result = await service.transitionStatus("claim_1", "VERIFIED", "staff_1");
    expect(result.status).toBe("VERIFIED");
    expect(claimRepo.updateStatus).toHaveBeenCalledWith("claim_1", "VERIFIED", "staff_1");
  });

  it("rejects an invalid transition (PENDING -> APPROVED, skipping VERIFIED)", async () => {
    const claim = makeClaim({ status: "PENDING" });
    const { claimRepo, notifications, audit } = makeMocks(claim);
    const service = new ClaimService(claimRepo as any, notifications, audit, new ClaimValidationService());

    await expect(service.transitionStatus("claim_1", "APPROVED", "staff_1")).rejects.toThrow(ServiceError);
    expect(claimRepo.updateStatus).not.toHaveBeenCalled();
  });

  it("blocks VERIFIED -> APPROVED when the claim has no documents", async () => {
    const claim = makeClaim({ status: "VERIFIED", processorId: "staff_1", documents: [] });
    const { claimRepo, notifications, audit } = makeMocks(claim);
    const service = new ClaimService(claimRepo as any, notifications, audit, new ClaimValidationService());

    await expect(service.transitionStatus("claim_1", "APPROVED", "staff_1")).rejects.toThrow(/unresolved issues/i);
    expect(claimRepo.updateStatus).not.toHaveBeenCalled();
  });

  it("allows VERIFIED -> APPROVED when the claim is complete", async () => {
    const claim = makeClaim({ status: "VERIFIED", processorId: "staff_1" });
    const { claimRepo, notifications, audit } = makeMocks(claim);
    const service = new ClaimService(claimRepo as any, notifications, audit, new ClaimValidationService());

    const result = await service.transitionStatus("claim_1", "APPROVED", "staff_1", { name: "Staff", role: "PROCESSOR" });
    expect(result.status).toBe("APPROVED");
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: "CLAIM_STATUS_CHANGED" }));
  });

  it("still updates status even if the notification write fails", async () => {
    const claim = makeClaim({ status: "PENDING" });
    const { claimRepo, notifications, audit } = makeMocks(claim);
    notifications.notifyStatusChange.mockRejectedValue(new Error("db down"));
    const service = new ClaimService(claimRepo as any, notifications, audit, new ClaimValidationService());

    const result = await service.transitionStatus("claim_1", "VERIFIED", "staff_1");
    expect(result.status).toBe("VERIFIED");
  });

  it("throws 404 for a claim that doesn't exist", async () => {
    const { claimRepo, notifications, audit } = makeMocks(null);
    claimRepo.findById.mockResolvedValue(null);
    const service = new ClaimService(claimRepo as any, notifications, audit, new ClaimValidationService());

    await expect(service.transitionStatus("nope", "VERIFIED", "staff_1")).rejects.toMatchObject({ statusCode: 404 });
  });
});

describe("ClaimService.createClaim", () => {
  it("rejects a non-positive estimate", async () => {
    const { claimRepo, notifications, audit } = makeMocks(null);
    const service = new ClaimService(claimRepo as any, notifications, audit, new ClaimValidationService());

    await expect(service.createClaim("user_1", { category: "HOMEOWNERS" as any, estimate: 0 })).rejects.toThrow(ServiceError);
    await expect(service.createClaim("user_1", { category: "HOMEOWNERS" as any, estimate: NaN })).rejects.toThrow(ServiceError);
  });
});
