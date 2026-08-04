import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { z } from "zod";
import { authOptions } from "@/lib/auth";
import { PaymentService } from "@/services/payment.service";
import { ServiceError } from "@/services/claim.service";

const paymentService = new PaymentService();

const checkoutSchema = z.object({
  provider: z.enum(["GCASH", "MAYA", "PAYPAL"]),
  amount: z.number().positive(),
});

// POST /api/claims/:id/payments — start a checkout for an approved claim's fee
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const body = await req.json();
  const parsed = checkoutSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  try {
    const result = await paymentService.startCheckout(params.id, parsed.data.provider, parsed.data.amount);
    return NextResponse.json(result, { status: 201 });
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}
