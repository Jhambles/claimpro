import { PaymentProvider, PaymentStatus, PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { IPaymentRepository } from "./interfaces";

export class PrismaPaymentRepository implements IPaymentRepository {
  constructor(private readonly db: PrismaClient = prisma) {}

  create(data: { claimId: string; provider: PaymentProvider; amount: number; providerRef?: string }) {
    return this.db.payment.create({ data });
  }

  findById(id: string) {
    return this.db.payment.findUnique({ where: { id }, include: { claim: true } });
  }

  updateStatus(id: string, status: PaymentStatus) {
    return this.db.payment.update({ where: { id }, data: { status } });
  }

  listForClaim(claimId: string) {
    return this.db.payment.findMany({ where: { claimId }, orderBy: { createdAt: "desc" } });
  }
}
