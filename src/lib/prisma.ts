import { PrismaClient } from "@prisma/client";

// Singleton pattern: prevents exhausting DB connections from hot-reloaded
// serverless functions in dev, and keeps one client per Lambda instance in prod.
const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

export const prisma = globalForPrisma.prisma ?? new PrismaClient();

if (process.env.NODE_ENV !== "production") globalForPrisma.prisma = prisma;
