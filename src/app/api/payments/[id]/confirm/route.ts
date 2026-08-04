import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { PaymentService } from "@/services/payment.service";
import { ServiceError } from "@/services/claim.service";

const paymentService = new PaymentService();

// POST /api/payments/:id/confirm — used by the mock checkout page in dev/demo
// mode. In production this responsibility moves to a signed webhook from the
// real gateway (PayMongo/PayPal) instead of a client-callable route.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const { success } = await req.json();

  try {
    const payment = await paymentService.confirmPayment(params.id, !!success);
    return NextResponse.json(payment);
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}
