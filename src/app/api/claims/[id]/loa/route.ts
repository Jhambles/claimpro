import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { LoaService } from "@/services/loa.service";
import { ClaimService, ServiceError } from "@/services/claim.service";
import { generateQrDataUrl } from "@/lib/qrcode";

const loaService = new LoaService();
const claimService = new ClaimService();

// POST /api/claims/:id/loa — generate (or fetch, if already generated) the
// Letter of Authorization for an approved claim, plus a QR code the claimant
// can scan to go straight to the claim's payout page. Staff can act on any
// claim; a claimant can only act on their own claim.
export async function POST(_req: NextRequest, { params }: { params: { id: string } }) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  if (session.user.role === "CLIENT") {
    const claim = await claimService.getClaim(params.id);
    if (!claim || claim.userId !== session.user.id) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }
  }

  try {
    const loa = await loaService.generateForClaim(params.id, session.user.id);

    const appUrl = process.env.NEXTAUTH_URL ?? "http://localhost:3000";
    const payoutUrl = `${appUrl}/claims/${params.id}`;
    const qrCodeDataUrl = await generateQrDataUrl(payoutUrl);

    return NextResponse.json({ ...loa, qrCodeDataUrl, payoutUrl }, { status: 201 });
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}
