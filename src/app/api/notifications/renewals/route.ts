import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { NotificationService } from "@/services/notification.service";

const notificationService = new NotificationService();
const RENEWAL_WINDOW_DAYS = 30;

// GET /api/notifications/renewals — scheduled job that nudges claimants whose
// approved claims are approaching a policy renewal window. Triggered by Vercel
// Cron (see vercel.json), which only issues GET requests and auto-attaches
// `Authorization: Bearer <CRON_SECRET>` when the CRON_SECRET env var is set.
export async function GET(req: NextRequest) {
  const auth = req.headers.get("authorization");
  if (!process.env.CRON_SECRET || auth !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - (365 - RENEWAL_WINDOW_DAYS));

  const dueForRenewal = await prisma.claim.findMany({
    where: { status: "APPROVED", createdAt: { lte: cutoff } },
    select: { id: true, referenceId: true, userId: true },
  });

  await Promise.all(
    dueForRenewal.map((c) =>
      notificationService.notifyRenewal(c.userId, `Your policy tied to claim ${c.referenceId} is approaching its renewal window. Renew soon to stay covered.`)
    )
  );

  return NextResponse.json({ notified: dueForRenewal.length });
}
