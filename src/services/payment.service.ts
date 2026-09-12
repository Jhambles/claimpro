import { PaymentProvider } from "@prisma/client";
import { IPaymentRepository, IClaimRepository } from "@/repositories/interfaces";
import { PrismaPaymentRepository } from "@/repositories/payment.repository";
import { PrismaClaimRepository } from "@/repositories/claim.repository";
import { getPaymentProvider } from "./payments/provider.factory";
import { NotificationService } from "./notification.service";
import { AuditService } from "./audit.service";
import { ServiceError } from "./claim.service";

export interface BankDetails {
  bankName: string;
  accountName: string;
  accountNumber: string;
}

export class PaymentService {
  constructor(
    private readonly payments: IPaymentRepository = new PrismaPaymentRepository(),
    private readonly claims: IClaimRepository = new PrismaClaimRepository(),
    private readonly notifications: NotificationService = new NotificationService(),
    private readonly audit: AuditService = new AuditService()
  ) {}

  async startCheckout(
    claimId: string,
    provider: PaymentProvider,
    amount: number,
    bankDetails?: BankDetails,
    actor?: { id: string; name: string; role: string }
  ) {
    const claim = await this.claims.findById(claimId);
    if (!claim) throw new ServiceError("Claim not found.", 404);
    if (claim.status !== "APPROVED") {
      throw new ServiceError("Payouts can only be claimed on approved claims.", 409);
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new ServiceError("Payout amount must be greater than zero.", 400);
    }
    if (provider === "BANK_TRANSFER") {
      if (!bankDetails?.bankName?.trim() || !bankDetails?.accountName?.trim() || !bankDetails?.accountNumber?.trim()) {
        throw new ServiceError("Bank name, account name, and account number are required for bank transfer.", 400);
      }
    }

    const payment = await this.payments.create({
      claimId,
      provider,
      amount,
      ...(provider === "BANK_TRANSFER" ? bankDetails : {}),
    });

    const checkout = await this.createCheckoutSafely(provider, payment.id, amount, claim.referenceId);

    if (actor) {
      await this.audit.log({
        actorId: actor.id,
        actorName: actor.name,
        actorRole: actor.role,
        action: "PAYOUT_INITIATED",
        detail: `${provider} payout of PHP ${amount.toLocaleString()} started for claim ${claim.referenceId}`,
      });
    }

    return { paymentId: payment.id, redirectUrl: checkout.redirectUrl };
  }

  // Used by the LOA/QR flow: the QR needs to land the claimant straight on a
  // checkout for whichever provider their LOA was generated for, not a page
  // they have to be logged in to see. Reuses an already-pending payment of
  // that same provider for the claim if one exists (so re-viewing the LOA
  // doesn't spawn a new "Pending" row in the payout history every time) but
  // always re-mints the checkout redirect, since real gateway checkout
  // sessions are short-lived and shouldn't be persisted/reused.
  async getOrCreateCheckoutForClaim(claimId: string, provider: PaymentProvider, amount: number, bankDetails?: BankDetails) {
    const claim = await this.claims.findById(claimId);
    if (!claim) throw new ServiceError("Claim not found.", 404);
    if (claim.status !== "APPROVED") {
      throw new ServiceError("Payouts can only be claimed on approved claims.", 409);
    }

    const existing = claim.payments.find((p: any) => p.provider === provider && p.status === "PENDING");
    const payment =
      existing ??
      (await this.payments.create({
        claimId,
        provider,
        amount,
        ...(provider === "BANK_TRANSFER" && bankDetails ? bankDetails : {}),
      }));

    const checkout = await this.createCheckoutSafely(provider, payment.id, Number(payment.amount), claim.referenceId);

    return { paymentId: payment.id, redirectUrl: checkout.redirectUrl };
  }

  // Wraps a gateway's createCheckout call so a failure (invalid/expired API
  // key, network error, gateway rejecting the request) becomes a clean,
  // actionable ServiceError instead of an unhandled exception that crashes
  // the request into an opaque 500 with no useful message for the caller.
  private async createCheckoutSafely(provider: PaymentProvider, paymentId: string, amount: number, referenceId: string) {
    const strategy = getPaymentProvider(provider);
    try {
      return await strategy.createCheckout({
        paymentId,
        amount,
        description: `ClaimsPro - ${referenceId}`,
      });
    } catch (err) {
      console.error(`Checkout creation failed for provider ${provider}:`, err);
      throw new ServiceError(
        `Could not start a ${provider} checkout right now. This usually means the payment gateway credentials in .env are invalid or misconfigured - check PAYMONGO_SECRET_KEY / PAYPAL_CLIENT_ID, or remove them to use the sandbox mock checkout instead.`,
        502
      );
    }
  }

  async confirmPayment(paymentId: string, success: boolean, actor?: { role: string }) {
    const payment = await this.payments.findById(paymentId);
    if (!payment) throw new ServiceError("Payment not found.", 404);

    // A GCash/Maya/PayPal "confirm" here stands in for a gateway webhook â€”
    // the claimant genuinely paid through that provider's own app, so letting
    // them trigger this is fine. A bank transfer has no such gateway: nothing
    // outside this app verifies the deposit actually happened, so only staff
    // (who can check the bank statement) may confirm one.
    if (payment.provider === "BANK_TRANSFER" && actor?.role !== "PROCESSOR" && actor?.role !== "ADMIN") {
      throw new ServiceError("Bank transfer payouts can only be verified by staff.", 403);
    }

    const status = success ? "PAID" : "FAILED";

    // Idempotency guard: this can legitimately be called more than once for the
    // same outcome â€” the mock checkout page confirms once, then the /return
    // page confirms again for parity with real gateways that redirect straight
    // there; real webhook providers also commonly redeliver. Skip the update
    // and (critically) the notification if the status has already landed.
    if (payment.status === status) {
      return payment;
    }

    const updated = await this.payments.updateStatus(paymentId, status);

    try {
      await this.notifications.notifyPayment(payment.claim.userId, payment.claim.referenceId, status, payment.claimId);
    } catch (err) {
      console.error("Failed to create payment notification:", err);
    }

    return updated;
  }

  listForClaim(claimId: string) {
    return this.payments.listForClaim(claimId);
  }
}
