import { PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { IDocumentRepository } from "./interfaces";

export class PrismaDocumentRepository implements IDocumentRepository {
  constructor(private readonly db: PrismaClient = prisma) {}

  createForClaim(data: { claimId: string; fileName: string; fileUrl: string; mimeType: string; sizeBytes: number }) {
    return this.db.document.create({ data });
  }

  listForClaim(claimId: string) {
    return this.db.document.findMany({ where: { claimId }, orderBy: { uploadedAt: "desc" } });
  }

  findById(id: string) {
    return this.db.document.findUnique({ where: { id } });
  }
}