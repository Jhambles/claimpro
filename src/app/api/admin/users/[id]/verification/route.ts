import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { z } from "zod";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { AuditService } from "@/services/audit.service";

const auditService = new AuditService();
const reviewSchema = z.object({ status: z.enum(["APPROVED", "REJECTED"]) });

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getServerSession(authOptions);
  if (!session || session.user.role !== "ADMIN") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const { id } = await params;
  const parsed = reviewSchema.safeParse(await request.json());
  if (!parsed.success) return NextResponse.json({ error: "Choose approve or reject." }, { status: 400 });

  const user = await prisma.user.findUnique({ where: { id } });
  if (!user) return NextResponse.json({ error: "User not found." }, { status: 404 });
  if (user.verificationStatus !== "PENDING" || !user.idDocumentUrl) {
    return NextResponse.json({ error: "This account is not awaiting ID review." }, { status: 409 });
  }

  const updated = await prisma.user.updateMany({
    where: { id, verificationStatus: "PENDING", idDocumentUrl: { not: null } },
    data: { verificationStatus: parsed.data.status },
  });
  if (updated.count !== 1) {
    return NextResponse.json({ error: "This account has already been reviewed." }, { status: 409 });
  }

  await auditService.log({
    actorId: session.user.id,
    actorName: session.user.name ?? session.user.email,
    actorRole: session.user.role,
    action: parsed.data.status === "APPROVED" ? "USER_ID_APPROVED" : "USER_ID_REJECTED",
    detail: `${parsed.data.status === "APPROVED" ? "Approved" : "Rejected"} ID verification for ${user.email}`,
  });
  return NextResponse.json({ id, verificationStatus: parsed.data.status });
}
