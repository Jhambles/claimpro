import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { z } from "zod";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { PrismaUserRepository } from "@/repositories/user.repository";
import { hashPassword } from "@/lib/password";

const userRepo = new PrismaUserRepository();

const createUserSchema = z.object({
  name: z.string().min(1),
  email: z.string().email(),
  password: z.string().min(8),
  role: z.enum(["CLIENT", "PROCESSOR", "ADMIN"]),
});

// GET /api/admin/users — list all users (ADMIN only)
export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session || session.user.role !== "ADMIN") return NextResponse.json({ error: "Forbidden" }, { status: 403 });

  const users = await prisma.user.findMany({
    select: { id: true, name: true, email: true, role: true, createdAt: true },
    orderBy: { createdAt: "desc" },
  });
  return NextResponse.json(users);
}

// POST /api/admin/users — provision a new user account (ADMIN only)
export async function POST(req: NextRequest) {
  const session = await getServerSession(authOptions);
  if (!session || session.user.role !== "ADMIN") return NextResponse.json({ error: "Forbidden" }, { status: 403 });

  const body = await req.json();
  const parsed = createUserSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  try {
    const existing = await userRepo.findByEmail(parsed.data.email);
    if (existing) return NextResponse.json({ error: "A user with that email already exists." }, { status: 409 });

    // Only passwordHash goes to Prisma — the User model has no `password`
    // column, so passing the raw plaintext field through (previously done via
    // `...parsed.data`) caused Prisma to reject the whole insert.
    const { password, ...rest } = parsed.data;
    const passwordHash = await hashPassword(password);
    const user = await userRepo.create({ ...rest, passwordHash });
    return NextResponse.json({ id: user.id, name: user.name, email: user.email, role: user.role }, { status: 201 });
  } catch (err) {
    console.error("Failed to create user:", err);
    return NextResponse.json({ error: "Could not create the account. Please try again." }, { status: 500 });
  }
}
