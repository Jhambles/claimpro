import { LoaService } from "@/services/loa.service";
import { ServiceError } from "@/services/claim.service";

function makeApprovedClaim(overrides: any = {}) {
  return {
    id: "claim_1",
    referenceId: "CLM-2026-X001",
    category: "HOMEOWNERS",
    status: "APPROVED",
    userId: "user_1",
    user: { name: "Jane Dela Cruz" },
    loa: null,
    ...overrides,
  };
}

function makeMocks(claim: any, preference: any = null) {
  const loaRepo = {
    createForClaim: jest.fn().mockImplementation((claimId, content, generatedById, provider) =>
      Promise.resolve({ id: "loa_1", claimId, content, generatedById, provider, generatedAt: new Date() })
    ),
    count: jest.fn(),
  };
  const claimRepo = { findById: jest.fn().mockResolvedValue(claim) };
  const payoutPreferences = { get: jest.fn().mockResolvedValue(preference) };
  return { loaRepo, claimRepo, payoutPreferences };
}

describe("LoaService.generateForClaim", () => {
  it("defaults to GCASH and names it in the letter text when the claimant has no saved preference", async () => {
    const claim = makeApprovedClaim();
    const { loaRepo, claimRepo, payoutPreferences } = makeMocks(claim, null);
    const service = new LoaService(loaRepo as any, claimRepo as any, payoutPreferences as any);

    const loa = await service.generateForClaim("claim_1", "staff_1");
    expect(loa.provider).toBe("GCASH");
    expect(loa.content).toMatch(/via GCash/);
  });

  it("locks in the claimant's saved preference (e.g. Maya) instead of always defaulting to GCash", async () => {
    const claim = makeApprovedClaim();
    const { loaRepo, claimRepo, payoutPreferences } = makeMocks(claim, { provider: "MAYA" });
    const service = new LoaService(loaRepo as any, claimRepo as any, payoutPreferences as any);

    const loa = await service.generateForClaim("claim_1", "staff_1");
    expect(loa.provider).toBe("MAYA");
    expect(loa.content).toMatch(/via Maya/);
    expect(loaRepo.createForClaim).toHaveBeenCalledWith(expect.anything(), expect.anything(), expect.anything(), "MAYA");
  });

  it("locks in PayPal too, not just GCash/Maya", async () => {
    const claim = makeApprovedClaim();
    const { loaRepo, claimRepo, payoutPreferences } = makeMocks(claim, { provider: "PAYPAL" });
    const service = new LoaService(loaRepo as any, claimRepo as any, payoutPreferences as any);

    const loa = await service.generateForClaim("claim_1", "staff_1");
    expect(loa.provider).toBe("PAYPAL");
    expect(loa.content).toMatch(/via PayPal/);
  });

  it("returns the already-generated LOA as-is on a second call, without re-deriving the provider from a possibly-since-changed preference", async () => {
    const existingLoa = { id: "loa_existing", content: "already generated, names Maya", provider: "MAYA" };
    const claim = makeApprovedClaim({ loa: existingLoa });
    // Preference has since changed to GCash â€” the already-generated LOA must NOT
    // switch to GCash just because it's re-fetched.
    const { loaRepo, claimRepo, payoutPreferences } = makeMocks(claim, { provider: "GCASH" });
    const service = new LoaService(loaRepo as any, claimRepo as any, payoutPreferences as any);

    const loa = await service.generateForClaim("claim_1", "staff_1");
    expect(loa).toBe(existingLoa);
    expect(loa.provider).toBe("MAYA");
    expect(loaRepo.createForClaim).not.toHaveBeenCalled();
  });

  it("rejects a claim that isn't APPROVED", async () => {
    const claim = makeApprovedClaim({ status: "PENDING" });
    const { loaRepo, claimRepo, payoutPreferences } = makeMocks(claim);
    const service = new LoaService(loaRepo as any, claimRepo as any, payoutPreferences as any);

    await expect(service.generateForClaim("claim_1", "staff_1")).rejects.toThrow(ServiceError);
  });

  it("throws 404 for a claim that doesn't exist", async () => {
    const { loaRepo, claimRepo, payoutPreferences } = makeMocks(null);
    const service = new LoaService(loaRepo as any, claimRepo as any, payoutPreferences as any);

    await expect(service.generateForClaim("nope", "staff_1")).rejects.toMatchObject({ statusCode: 404 });
  });
});
