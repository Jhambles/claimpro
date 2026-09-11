import { PrismaClient, PaymentProvider } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { IPayoutPreferenceRepository } from "./interfaces";

export class PrismaPayoutPreferenceRepository implements IPayoutPreferenceRepository {
  constructor(private readonly db: PrismaClient = prisma) {}

  findByUserId(userId: string) {
    return this.db.payoutPreference.findUnique({ where: { userId } });
  }

  upsert(userId: string, data: { provider: PaymentProvider; bankName?: string | null; accountName?: string | null; accountNumber?: string | null }) {
    return this.db.payoutPreference.upsert({
      where: { userId },
      update: data,
      create: { userId, ...data },
    });
  }
}
