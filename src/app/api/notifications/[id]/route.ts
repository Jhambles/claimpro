import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { NotificationService } from "@/services/notification.service";

const notificationService = new NotificationService();

// PATCH /api/notifications/:id — mark as read
export async function PATCH(_req: NextRequest, { params }: { params: { id: string } }) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  try {
    await notificationService.markRead(params.id, session.user.id);
    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error("Failed to mark notification read:", err);
    return NextResponse.json({ error: "Could not update notification." }, { status: 500 });
  }
}
