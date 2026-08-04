import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { z } from "zod";
import { authOptions } from "@/lib/auth";
import { ClaimService, ServiceError } from "@/services/claim.service";

const claimService = new ClaimService();

const updateStatusSchema = z.object({
  status: z.enum(["VERIFIED", "APPROVED", "REJECTED"]),
});

// GET /api/claims/:id
export async function GET(_req: NextRequest, { params }: { params: { id: string } }) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const claim = await claimService.getClaim(params.id);
  if (!claim) return NextResponse.json({ error: "Not found" }, { status: 404 });

  if (session.user.role === "CLIENT" && claim.userId !== session.user.id) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  return NextResponse.json(claim);
}

// PATCH /api/claims/:id — advance claim status (PROCESSOR / ADMIN only)
export async function PATCH(req: NextRequest, { params }: { params: { id: string } }) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (session.user.role === "CLIENT") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const body = await req.json();
  const parsed = updateStatusSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  try {
    const claim = await claimService.transitionStatus(params.id, parsed.data.status, session.user.id);
    return NextResponse.json(claim);
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}
