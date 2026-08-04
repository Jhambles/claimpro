import { PaymentProvider } from "@prisma/client";
import { IPaymentProvider } from "./provider.interface";
import { GcashProvider, MayaProvider } from "./paymongo.provider";
import { PaypalProvider } from "./paypal.provider";

// Factory Method: isolates the mapping of "provider name" -> concrete class.
// PaymentService never instantiates a provider class directly, so adding a
// new gateway only ever touches this file plus the new provider class.
export function getPaymentProvider(name: PaymentProvider): IPaymentProvider {
  switch (name) {
    case "GCASH":
      return new GcashProvider();
    case "MAYA":
      return new MayaProvider();
    case "PAYPAL":
      return new PaypalProvider();
    default:
      throw new Error(`Unsupported payment provider: ${name}`);
  }
}
