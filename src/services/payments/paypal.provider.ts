import { IPaymentProvider, CheckoutResult } from "./provider.interface";

export class PaypalProvider implements IPaymentProvider {
  readonly name = "PAYPAL" as const;

  async createCheckout(input: { paymentId: string; amount: number; description: string }): Promise<CheckoutResult> {
    const clientId = process.env.PAYPAL_CLIENT_ID;
    const clientSecret = process.env.PAYPAL_CLIENT_SECRET;
    const appUrl = process.env.NEXTAUTH_URL ?? "http://localhost:3000";

    if (!clientId || !clientSecret) {
      return { redirectUrl: `${appUrl}/pay/${input.paymentId}?provider=PAYPAL`, providerRef: `MOCK-${input.paymentId}` };
    }

    const base = process.env.PAYPAL_ENV === "live" ? "https://api-m.paypal.com" : "https://api-m.sandbox.paypal.com";

    const tokenRes = await fetch(`${base}/v1/oauth2/token`, {
      method: "POST",
      headers: {
        Authorization: `Basic ${Buffer.from(`${clientId}:${clientSecret}`).toString("base64")}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: "grant_type=client_credentials",
    });
    const { access_token } = await tokenRes.json();

    const orderRes = await fetch(`${base}/v2/checkout/orders`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${access_token}` },
      body: JSON.stringify({
        intent: "CAPTURE",
        purchase_units: [{ description: input.description, amount: { currency_code: "USD", value: input.amount.toFixed(2) } }],
        application_context: {
          return_url: `${appUrl}/pay/${input.paymentId}/return?status=success`,
          cancel_url: `${appUrl}/pay/${input.paymentId}/return?status=failed`,
        },
      }),
    });

    if (!orderRes.ok) throw new Error(`PayPal order creation failed: ${orderRes.status} ${await orderRes.text()}`);
    const order = await orderRes.json();
    const approveLink = order.links.find((l: any) => l.rel === "approve")?.href;
    return { redirectUrl: approveLink, providerRef: order.id };
  }
}
