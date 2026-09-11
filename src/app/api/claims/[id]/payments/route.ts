import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { z } from "zod";
import { authOptions } from "@/lib/auth";
import { PaymentService } from "@/services/payment.service";
import { ServiceError } from "@/services/claim.service";

const paymentService = new PaymentService();

const checkoutSchema = z.object({
  provider: z.enum(["GCASH", "MAYA", "PAYPAL", "BANK_TRANSFER"]),
  amount: z.number().positive(),
  bankName: z.string().min(1).optional(),
  accountName: z.string().min(1).optional(),
  accountNumber: z.string().min(1).optional(),
});

// POST /api/claims/:id/payments â€” start a checkout for an approved claim's fee
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const body = await req.json();
  const parsed = checkoutSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const { provider, amount, bankName, accountName, accountNumber } = parsed.data;

  try {
    const result = await paymentService.startCheckout(
      id,
      provider,
      amount,
      provider === "BANK_TRANSFER" && bankName && accountName && accountNumber
        ? { bankName, accountName, accountNumber }
        : undefined,
      { id: session.user.id, name: session.user.name ?? session.user.email, role: session.user.role }
    );
    return NextResponse.json(result, { status: 201 });
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}
