import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { LoaService } from "@/services/loa.service";
import { ClaimService, ServiceError } from "@/services/claim.service";
import { PaymentService } from "@/services/payment.service";
import { generateQrDataUrl } from "@/lib/qrcode";

const loaService = new LoaService();
const claimService = new ClaimService();
const paymentService = new PaymentService();


export async function POST(_req: NextRequest, { params }: { params: { id: string } }) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const claim = await claimService.getClaim(params.id);
  if (!claim) return NextResponse.json({ error: "Claim not found." }, { status: 404 });
  if (session.user.role === "CLIENT" && claim.userId !== session.user.id) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  try {
    const loa = await loaService.generateForClaim(params.id, session.user.id);

    const { redirectUrl: payoutUrl } = await paymentService.getOrCreateGcashCheckout(params.id, Number(claim.estimate));
    const qrCodeDataUrl = await generateQrDataUrl(payoutUrl);

    return NextResponse.json({ ...loa, qrCodeDataUrl, payoutUrl }, { status: 201 });
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}