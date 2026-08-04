import { PaymentProvider } from "@prisma/client";
import { IPaymentRepository, IClaimRepository } from "@/repositories/interfaces";
import { PrismaPaymentRepository } from "@/repositories/payment.repository";
import { PrismaClaimRepository } from "@/repositories/claim.repository";
import { getPaymentProvider } from "./payments/provider.factory";
import { NotificationService } from "./notification.service";
import { ServiceError } from "./claim.service";

export class PaymentService {
  constructor(
    private readonly payments: IPaymentRepository = new PrismaPaymentRepository(),
    private readonly claims: IClaimRepository = new PrismaClaimRepository(),
    private readonly notifications: NotificationService = new NotificationService()
  ) {}

  async startCheckout(claimId: string, provider: PaymentProvider, amount: number) {
    const claim = await this.claims.findById(claimId);
    if (!claim) throw new ServiceError("Claim not found.", 404);
    if (claim.status !== "APPROVED") {
      throw new ServiceError("Payouts can only be claimed on approved claims.", 409);
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new ServiceError("Payout amount must be greater than zero.", 400);
    }

    const payment = await this.payments.create({ claimId, provider, amount });

    const strategy = getPaymentProvider(provider);
    const checkout = await strategy.createCheckout({
      paymentId: payment.id,
      amount,
      description: `ClaimsPro — ${claim.referenceId}`,
    });

    return { paymentId: payment.id, redirectUrl: checkout.redirectUrl };
  }

  async confirmPayment(paymentId: string, success: boolean) {
    const payment = await this.payments.findById(paymentId);
    if (!payment) throw new ServiceError("Payment not found.", 404);

    const status = success ? "PAID" : "FAILED";

    // Idempotency guard: this can legitimately be called more than once for the
    // same outcome — the mock checkout page confirms once, then the /return
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
