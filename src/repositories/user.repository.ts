import { PrismaClient, Role } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { IUserRepository } from "./interfaces";

export class PrismaUserRepository implements IUserRepository {
  constructor(private readonly db: PrismaClient = prisma) {}

  findByEmail(email: string) {
    return this.db.user.findUnique({ where: { email } });
  }

  findById(id: string) {
    return this.db.user.findUnique({ where: { id } });
  }

  create(data: { name: string; email: string; passwordHash: string; role: Role }) {
    return this.db.user.create({ data });
  }

  countAll() {
    return this.db.user.count();
  }
}
