import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { z } from "zod";
import { authOptions } from "@/lib/auth";
import { ClaimService, ServiceError, MIN_REASON_LENGTH, MAX_REASON_LENGTH } from "@/services/claim.service";

const claimService = new ClaimService();

const updateStatusSchema = z.object({
  status: z.enum(["VERIFIED", "APPROVED", "REJECTED"]),
  reason: z
    .string()
    .trim()
    .min(MIN_REASON_LENGTH, `Please state a reason (at least ${MIN_REASON_LENGTH} characters).`)
    .max(MAX_REASON_LENGTH, `The reason is too long (maximum ${MAX_REASON_LENGTH} characters).`),
});

// GET /api/claims/:id
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const claim = await claimService.getClaim(id);
  if (!claim) return NextResponse.json({ error: "Not found" }, { status: 404 });

  if (session.user.role === "CLIENT" && claim.userId !== session.user.id) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const issues = claimService.getValidationIssues(claim);
  const decisionRows = await claimService.listDecisions(id);
  const decisions = decisionRows.map((d) => ({
    id: d.id,
    status: d.status,
    reason: d.reason,
    decidedByName: d.decidedByName,
    decidedByRole: d.decidedByRole,
    createdAt: d.createdAt,
  }));
  return NextResponse.json({ ...claim, issues, decisions });
}

// PATCH /api/claims/:id â€” advance claim status with a stated reason (PROCESSOR / ADMIN only)
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (session.user.role === "CLIENT") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const body = await req.json().catch(() => ({}));
  const parsed = updateStatusSchema.safeParse(body);
  if (!parsed.success) {
    const first = parsed.error.issues[0];
    return NextResponse.json(
      { error: first?.path[0] === "reason" ? first.message : "Invalid request." },
      { status: 400 }
    );
  }

  try {
    const claim = await claimService.transitionStatus(id, parsed.data.status, session.user.id, parsed.data.reason, {
      name: session.user.name ?? session.user.email,
      role: session.user.role,
    });
    return NextResponse.json(claim);
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}
