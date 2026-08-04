import { PrismaClient, Role, PolicyCategory, ClaimStatus } from "@prisma/client";
import bcrypt from "bcryptjs";

const prisma = new PrismaClient();

async function main() {
  const password = await bcrypt.hash("Passw0rd!", 10);

  const admin = await prisma.user.upsert({
    where: { email: "admin@claimspro.dev" },
    update: {},
    create: { name: "System Admin", email: "admin@claimspro.dev", passwordHash: password, role: Role.ADMIN },
  });

  const processor = await prisma.user.upsert({
    where: { email: "processor@claimspro.dev" },
    update: {},
    create: { name: "Alex Santos", email: "processor@claimspro.dev", passwordHash: password, role: Role.PROCESSOR },
  });

  const client = await prisma.user.upsert({
    where: { email: "client@claimspro.dev" },
    update: {},
    create: { name: "John Dela Cruz", email: "client@claimspro.dev", passwordHash: password, role: Role.CLIENT },
  });

  await prisma.claim.upsert({
    where: { referenceId: "CLM-2026-X1" },
    update: {},
    create: {
      referenceId: "CLM-2026-X1",
      category: PolicyCategory.MEDICAL,
      estimate: 15400.0,
      status: ClaimStatus.APPROVED,
      userId: client.id,
      processorId: processor.id,
    },
  });

  await prisma.claim.upsert({
    where: { referenceId: "CLM-2026-X2" },
    update: {},
    create: {
      referenceId: "CLM-2026-X2",
      category: PolicyCategory.AUTOMOTIVE,
      estimate: 8200.0,
      status: ClaimStatus.PENDING,
      userId: client.id,
    },
  });

  console.log({ admin: admin.email, processor: processor.email, client: client.email, seededPassword: "Passw0rd!" });
}

main().finally(() => prisma.$disconnect());
