import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { z } from "zod";
import { authOptions } from "@/lib/auth";
import { PayoutPreferenceService } from "@/services/payout-preference.service";
import { ServiceError } from "@/services/claim.service";

const preferenceService = new PayoutPreferenceService();

const preferenceSchema = z.object({
  provider: z.enum(["GCASH", "MAYA", "PAYPAL", "BANK_TRANSFER"]),
  bankName: z.string().min(1).optional(),
  accountName: z.string().min(1).optional(),
  accountNumber: z.string().min(1).optional(),
});

// GET /api/settings/payout-preference â€” the caller's saved default payout method
export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const preference = await preferenceService.get(session.user.id);
  return NextResponse.json(preference);
}

// PUT /api/settings/payout-preference â€” save/update the caller's default payout method
export async function PUT(req: NextRequest) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const body = await req.json();
  const parsed = preferenceSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  try {
    const preference = await preferenceService.save(session.user.id, parsed.data);
    return NextResponse.json(preference);
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}
