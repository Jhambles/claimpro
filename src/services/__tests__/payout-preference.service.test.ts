import { PayoutPreferenceService } from "@/services/payout-preference.service";
import { ServiceError } from "@/services/claim.service";

function makeMocks(existing: any = null) {
  const repo = {
    findByUserId: jest.fn().mockResolvedValue(existing),
    upsert: jest.fn().mockImplementation((userId, data) => Promise.resolve({ id: "pref_1", userId, ...data })),
  };
  return repo;
}

describe("PayoutPreferenceService.save", () => {
  it("saves a non-bank provider with bank fields nulled out", async () => {
    const repo = makeMocks();
    const service = new PayoutPreferenceService(repo as any);

    const result = await service.save("user_1", { provider: "GCASH" });
    expect(repo.upsert).toHaveBeenCalledWith("user_1", {
      provider: "GCASH",
      bankName: null,
      accountName: null,
      accountNumber: null,
    });
    expect(result.provider).toBe("GCASH");
  });

  it("rejects BANK_TRANSFER with missing bank details", async () => {
    const repo = makeMocks();
    const service = new PayoutPreferenceService(repo as any);

    await expect(service.save("user_1", { provider: "BANK_TRANSFER" })).rejects.toThrow(ServiceError);
    await expect(
      service.save("user_1", { provider: "BANK_TRANSFER", bankName: "BDO Unibank" })
    ).rejects.toThrow(/account name/i);
    expect(repo.upsert).not.toHaveBeenCalled();
  });

  it("saves BANK_TRANSFER with trimmed bank details", async () => {
    const repo = makeMocks();
    const service = new PayoutPreferenceService(repo as any);

    await service.save("user_1", {
      provider: "BANK_TRANSFER",
      bankName: "  BDO Unibank  ",
      accountName: "  Jane Dela Cruz  ",
      accountNumber: "  1234567890  ",
    });

    expect(repo.upsert).toHaveBeenCalledWith("user_1", {
      provider: "BANK_TRANSFER",
      bankName: "BDO Unibank",
      accountName: "Jane Dela Cruz",
      accountNumber: "1234567890",
    });
  });

  it("clears stale bank details when switching away from BANK_TRANSFER", async () => {
    const existing = { provider: "BANK_TRANSFER", bankName: "BDO Unibank", accountName: "Jane", accountNumber: "123" };
    const repo = makeMocks(existing);
    const service = new PayoutPreferenceService(repo as any);

    await service.save("user_1", { provider: "PAYPAL" });

    expect(repo.upsert).toHaveBeenCalledWith("user_1", {
      provider: "PAYPAL",
      bankName: null,
      accountName: null,
      accountNumber: null,
    });
  });
});

describe("PayoutPreferenceService.get", () => {
  it("returns null when the user has no saved preference", async () => {
    const repo = makeMocks(null);
    const service = new PayoutPreferenceService(repo as any);

    const result = await service.get("user_1");
    expect(result).toBeNull();
  });

  it("returns the existing preference when one is saved", async () => {
    const existing = { provider: "GCASH" };
    const repo = makeMocks(existing);
    const service = new PayoutPreferenceService(repo as any);

    const result = await service.get("user_1");
    expect(result).toEqual(existing);
  });
});
