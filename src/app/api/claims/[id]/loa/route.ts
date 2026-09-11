import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { LoaService } from "@/services/loa.service";
import { ClaimService, ServiceError } from "@/services/claim.service";
import { PaymentService } from "@/services/payment.service";
import { PayoutPreferenceService } from "@/services/payout-preference.service";
import { generateQrDataUrl } from "@/lib/qrcode";

const loaService = new LoaService();
const claimService = new ClaimService();
const paymentService = new PaymentService();
const payoutPreferenceService = new PayoutPreferenceService();

const PROVIDER_LABEL: Record<string, string> = {
  GCASH: "GCash",
  MAYA: "Maya",
  PAYPAL: "PayPal",
  BANK_TRANSFER: "Bank Transfer",
};

// POST /api/claims/:id/loa â€” generate (or fetch, if already generated) the
// Letter of Authorization for an approved claim, plus a QR code that takes
// the claimant straight into a checkout for whichever provider they've set
// as their default in Settings (GCash if they haven't set one) â€” not to a
// page inside the app, since that requires a session and a phone scanning
// the printed/emailed LOA usually won't have one. Staff can act on any
// claim; a claimant can only act on their own claim.
export async function POST(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const claim = await claimService.getClaim(id);
  if (!claim) return NextResponse.json({ error: "Claim not found." }, { status: 404 });
  if (session.user.role === "CLIENT" && claim.userId !== session.user.id) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  try {
    const loa = await loaService.generateForClaim(id, session.user.id);

    // The LOA's own `provider` field is authoritative â€” it's what the
    // letter's printed text actually names, locked in at first generation.
    // Bank details, if needed, come from the claimant's *current* saved
    // preference: if a pending bank-transfer payment already exists for
    // this claim it's simply reused (see getOrCreateCheckoutForClaim), so
    // this only matters the first time a bank-transfer checkout is created.
    let bankDetails: { bankName: string; accountName: string; accountNumber: string } | undefined;
    if (loa.provider === "BANK_TRANSFER") {
      const preference = await payoutPreferenceService.get(claim.userId);
      if (preference?.bankName && preference.accountName && preference.accountNumber) {
        bankDetails = { bankName: preference.bankName, accountName: preference.accountName, accountNumber: preference.accountNumber };
      }
    }

    const { redirectUrl: payoutUrl } = await paymentService.getOrCreateCheckoutForClaim(
      id,
      loa.provider as any,
      Number(claim.estimate),
      bankDetails
    );
    const qrCodeDataUrl = await generateQrDataUrl(payoutUrl);

    return NextResponse.json({ ...loa, qrCodeDataUrl, payoutUrl, providerLabel: PROVIDER_LABEL[loa.provider] ?? loa.provider }, { status: 201 });
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}
