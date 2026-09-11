import { PaymentService } from "@/services/payment.service";
import { ServiceError } from "@/services/claim.service";

jest.mock("@/services/payments/provider.factory", () => ({
  getPaymentProvider: jest.fn(() => ({
    createCheckout: jest.fn().mockResolvedValue({ redirectUrl: "https://pay.example/checkout", providerRef: "ref_1" }),
  })),
}));

function makeMocks(claim: any, payment?: any) {
  const paymentRepo = {
    create: jest.fn().mockResolvedValue(payment ?? { id: "pay_1", claimId: claim?.id, provider: "GCASH", amount: 500, status: "PENDING" }),
    findById: jest.fn().mockResolvedValue(payment),
    updateStatus: jest.fn().mockImplementation((id, status) => Promise.resolve({ ...payment, status })),
    listForClaim: jest.fn(),
  };
  const claimRepo = { findById: jest.fn().mockResolvedValue(claim) } as any;
  const notifications = { notifyPayment: jest.fn().mockResolvedValue(undefined) } as any;
  const audit = { log: jest.fn().mockResolvedValue(undefined) } as any;
  return { paymentRepo, claimRepo, notifications, audit };
}

function makeApprovedClaim(overrides: any = {}) {
  return { id: "claim_1", referenceId: "CLM-2026-X001", status: "APPROVED", estimate: 5000, payments: [], ...overrides };
}

describe("PaymentService.startCheckout", () => {
  it("rejects a claim that isn't APPROVED", async () => {
    const claim = makeApprovedClaim({ status: "PENDING" });
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await expect(service.startCheckout("claim_1", "GCASH", 500)).rejects.toThrow(ServiceError);
  });

  it("rejects a non-positive amount", async () => {
    const claim = makeApprovedClaim();
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await expect(service.startCheckout("claim_1", "GCASH", 0)).rejects.toThrow(ServiceError);
  });

  it("requires bank details for BANK_TRANSFER", async () => {
    const claim = makeApprovedClaim();
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await expect(service.startCheckout("claim_1", "BANK_TRANSFER", 500)).rejects.toThrow(/bank name/i);
  });

  it("succeeds for BANK_TRANSFER with complete bank details", async () => {
    const claim = makeApprovedClaim();
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    const result = await service.startCheckout("claim_1", "BANK_TRANSFER", 500, {
      bankName: "BDO Unibank",
      accountName: "Jane Dela Cruz",
      accountNumber: "1234567890",
    });
    expect(result.redirectUrl).toBe("https://pay.example/checkout");
    expect(paymentRepo.create).toHaveBeenCalledWith(
      expect.objectContaining({ bankName: "BDO Unibank", accountName: "Jane Dela Cruz", accountNumber: "1234567890" })
    );
  });
});

describe("PaymentService.getOrCreateCheckoutForClaim", () => {
  it("reuses an existing PENDING payment of the same provider instead of creating a new one", async () => {
    const existing = { id: "pay_existing", provider: "GCASH", status: "PENDING", amount: 500 };
    const claim = makeApprovedClaim({ payments: [existing] });
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    const result = await service.getOrCreateCheckoutForClaim("claim_1", "GCASH", 500);
    expect(paymentRepo.create).not.toHaveBeenCalled();
    expect(result.paymentId).toBe("pay_existing");
  });

  it("creates a new payment when none is pending for that provider", async () => {
    const claim = makeApprovedClaim({ payments: [] });
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await service.getOrCreateCheckoutForClaim("claim_1", "GCASH", 500);
    expect(paymentRepo.create).toHaveBeenCalledWith(expect.objectContaining({ claimId: "claim_1", provider: "GCASH" }));
  });

  it("works for a non-GCash provider too (e.g. the LOA locked in Maya)", async () => {
    const claim = makeApprovedClaim({ payments: [] });
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await service.getOrCreateCheckoutForClaim("claim_1", "MAYA", 500);
    expect(paymentRepo.create).toHaveBeenCalledWith(expect.objectContaining({ claimId: "claim_1", provider: "MAYA" }));
  });

  it("passes bank details through when creating a BANK_TRANSFER checkout", async () => {
    const claim = makeApprovedClaim({ payments: [] });
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await service.getOrCreateCheckoutForClaim("claim_1", "BANK_TRANSFER", 500, {
      bankName: "BDO Unibank",
      accountName: "Jane Dela Cruz",
      accountNumber: "1234567890",
    });
    expect(paymentRepo.create).toHaveBeenCalledWith(
      expect.objectContaining({ claimId: "claim_1", provider: "BANK_TRANSFER", bankName: "BDO Unibank" })
    );
  });
});

describe("PaymentService.confirmPayment", () => {
  it("lets a claimant self-confirm a GCash payment (stands in for a gateway webhook)", async () => {
    const payment = { id: "pay_1", provider: "GCASH", status: "PENDING", claimId: "claim_1", claim: { userId: "user_1", referenceId: "CLM-1" } };
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(null, payment);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    const result = await service.confirmPayment("pay_1", true, { role: "CLIENT" });
    expect(result.status).toBe("PAID");
    expect(notifications.notifyPayment).toHaveBeenCalled();
  });

  it("blocks a non-staff actor from confirming a BANK_TRANSFER payment", async () => {
    const payment = { id: "pay_1", provider: "BANK_TRANSFER", status: "PENDING", claimId: "claim_1", claim: { userId: "user_1", referenceId: "CLM-1" } };
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(null, payment);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await expect(service.confirmPayment("pay_1", true, { role: "CLIENT" })).rejects.toMatchObject({ statusCode: 403 });
    expect(paymentRepo.updateStatus).not.toHaveBeenCalled();
  });

  it("allows a PROCESSOR to confirm a BANK_TRANSFER payment", async () => {
    const payment = { id: "pay_1", provider: "BANK_TRANSFER", status: "PENDING", claimId: "claim_1", claim: { userId: "user_1", referenceId: "CLM-1" } };
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(null, payment);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    const result = await service.confirmPayment("pay_1", true, { role: "PROCESSOR" });
    expect(result.status).toBe("PAID");
  });

  it("is idempotent â€” confirming an already-PAID payment again doesn't re-notify", async () => {
    const payment = { id: "pay_1", provider: "GCASH", status: "PAID", claimId: "claim_1", claim: { userId: "user_1", referenceId: "CLM-1" } };
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(null, payment);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    const result = await service.confirmPayment("pay_1", true, { role: "CLIENT" });
    expect(result.status).toBe("PAID");
    expect(paymentRepo.updateStatus).not.toHaveBeenCalled();
    expect(notifications.notifyPayment).not.toHaveBeenCalled();
  });

  it("throws 404 for a payment that doesn't exist", async () => {
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(null, null);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await expect(service.confirmPayment("nope", true)).rejects.toMatchObject({ statusCode: 404 });
  });
});
