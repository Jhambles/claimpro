// Strategy pattern: every payment provider (GCash, Maya, PayPal) implements
// this same contract. PaymentService depends only on this interface (OCP) —
// adding a new provider (e.g. GrabPay) means writing one new class and
// registering it in the factory, with no changes to PaymentService itself.
export interface CheckoutResult {
  redirectUrl: string;
  providerRef: string;
}

export interface IPaymentProvider {
  readonly name: "GCASH" | "MAYA" | "PAYPAL";
  createCheckout(input: { paymentId: string; amount: number; description: string }): Promise<CheckoutResult>;
}
