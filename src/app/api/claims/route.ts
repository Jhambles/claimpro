import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { z } from "zod";
import { authOptions } from "@/lib/auth";
import { ClaimService, ServiceError } from "@/services/claim.service";

const claimService = new ClaimService();

const createClaimSchema = z.object({
  category: z.enum(["MEDICAL", "AUTOMOTIVE", "HOMEOWNERS"]),
  estimate: z.number().positive(),
});

// GET /api/claims — list claims (own claims for CLIENT, full queue for staff)
export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const claims = await claimService.listClaimsFor(session.user);
  return NextResponse.json(claims);
}

// POST /api/claims — submit a new claim (CLIENT only)
export async function POST(req: NextRequest) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (session.user.role !== "CLIENT") {
    return NextResponse.json({ error: "Only claimants can submit claims." }, { status: 403 });
  }

  const body = await req.json();
  const parsed = createClaimSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  try {
    const claim = await claimService.createClaim(session.user.id, parsed.data);
    return NextResponse.json(claim, { status: 201 });
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}
