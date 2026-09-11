import { PaymentProvider } from "@prisma/client";
import { IPayoutPreferenceRepository } from "@/repositories/interfaces";
import { PrismaPayoutPreferenceRepository } from "@/repositories/payout-preference.repository";
import { ServiceError } from "./claim.service";

export interface PayoutPreferenceInput {
  provider: PaymentProvider;
  bankName?: string;
  accountName?: string;
  accountNumber?: string;
}

export class PayoutPreferenceService {
  constructor(private readonly preferences: IPayoutPreferenceRepository = new PrismaPayoutPreferenceRepository()) {}

  get(userId: string) {
    return this.preferences.findByUserId(userId);
  }

  async save(userId: string, input: PayoutPreferenceInput) {
    if (input.provider === "BANK_TRANSFER") {
      if (!input.bankName?.trim() || !input.accountName?.trim() || !input.accountNumber?.trim()) {
        throw new ServiceError("Bank name, account name, and account number are required for bank transfer.", 400);
      }
    }

    return this.preferences.upsert(userId, {
      provider: input.provider,
      // Explicit null (not undefined) when switching away from bank
      // transfer â€” Prisma treats `undefined` as "leave this field
      // untouched," so using it here would leave stale bank details
      // attached to a preference that's since been switched to
      // GCash/Maya/PayPal.
      bankName: input.provider === "BANK_TRANSFER" ? input.bankName!.trim() : null,
      accountName: input.provider === "BANK_TRANSFER" ? input.accountName!.trim() : null,
      accountNumber: input.provider === "BANK_TRANSFER" ? input.accountNumber!.trim() : null,
    });
  }
}
