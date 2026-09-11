import { PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { IAuditLogRepository } from "./interfaces";

export class PrismaAuditLogRepository implements IAuditLogRepository {
  constructor(private readonly db: PrismaClient = prisma) {}

  async log(data: { actorId?: string; actorName: string; actorRole: string; action: string; detail?: string }) {
    await this.db.auditLog.create({ data });
  }

  list(limit = 100) {
    return this.db.auditLog.findMany({ orderBy: { createdAt: "desc" }, take: limit });
  }
}
