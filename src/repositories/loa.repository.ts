import { PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { ILoaRepository } from "./interfaces";

export class PrismaLoaRepository implements ILoaRepository {
  constructor(private readonly db: PrismaClient = prisma) {}

  createForClaim(claimId: string, content: string, generatedById: string) {
    return this.db.loa.create({ data: { claimId, content, generatedById } });
  }

  count() {
    return this.db.loa.count();
  }
}
