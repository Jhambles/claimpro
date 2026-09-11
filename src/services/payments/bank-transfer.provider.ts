import { IPaymentProvider, CheckoutResult } from "./provider.interface";

// Unlike GCash/Maya/PayPal, a bank transfer has no gateway to hand off to â€”
// the claimant deposits to the bank details they submitted, and staff verify
// the deposit manually before marking the payment PAID. There's no live vs.
// mock split here (no external API to call either way); this always lands
// the claimant on a confirmation screen explaining the payout is pending
// manual verification.
export class BankTransferProvider implements IPaymentProvider {
  readonly name = "BANK_TRANSFER" as const;

  async createCheckout(input: { paymentId: string; amount: number; description: string }): Promise<CheckoutResult> {
    const appUrl = process.env.NEXTAUTH_URL ?? "http://localhost:3000";
    return {
      redirectUrl: `${appUrl}/pay/${input.paymentId}?provider=BANK_TRANSFER`,
      providerRef: `MANUAL-${input.paymentId}`,
    };
  }
}
