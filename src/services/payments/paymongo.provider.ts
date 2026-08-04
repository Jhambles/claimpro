import { IPaymentProvider, CheckoutResult } from "./provider.interface";

// GCash and Maya are both offered in the Philippines through PayMongo's
// "sources" API — same request shape, different `type`. Each still gets its
// own class so the factory/strategy pattern stays honest (one class per
// provider "name" the rest of the app depends on).
abstract class PayMongoProvider implements IPaymentProvider {
  abstract readonly name: "GCASH" | "MAYA";
  protected abstract readonly sourceType: "gcash" | "grab_pay" | "paymaya";

  async createCheckout(input: { paymentId: string; amount: number; description: string }): Promise<CheckoutResult> {
    const secretKey = process.env.PAYMONGO_SECRET_KEY;
    const appUrl = process.env.NEXTAUTH_URL ?? "http://localhost:3000";

    // No PayMongo key configured (e.g. local dev without sandbox credentials) —
    // fall back to an in-app mock checkout so the flow is still testable end to end.
    if (!secretKey) {
      return { redirectUrl: `${appUrl}/pay/${input.paymentId}?provider=${this.name}`, providerRef: `MOCK-${input.paymentId}` };
    }

    const res = await fetch("https://api.paymongo.com/v1/sources", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Basic ${Buffer.from(`${secretKey}:`).toString("base64")}`,
      },
      body: JSON.stringify({
        data: {
          attributes: {
            amount: Math.round(input.amount * 100), // PayMongo expects centavos
            currency: "PHP",
            type: this.sourceType,
            description: input.description,
            redirect: {
              success: `${appUrl}/pay/${input.paymentId}/return?status=success`,
              failed: `${appUrl}/pay/${input.paymentId}/return?status=failed`,
            },
          },
        },
      }),
    });

    if (!res.ok) throw new Error(`PayMongo checkout failed: ${res.status} ${await res.text()}`);
    const json = await res.json();
    return { redirectUrl: json.data.attributes.redirect.checkout_url, providerRef: json.data.id };
  }
}

export class GcashProvider extends PayMongoProvider {
  readonly name = "GCASH" as const;
  protected readonly sourceType = "gcash" as const;
}

export class MayaProvider extends PayMongoProvider {
  readonly name = "MAYA" as const;
  protected readonly sourceType = "paymaya" as const;
}
