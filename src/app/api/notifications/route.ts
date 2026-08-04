import { NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { NotificationService } from "@/services/notification.service";

const notificationService = new NotificationService();

// GET /api/notifications — my notifications (most recent 50)
export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  try {
    const [items, unread] = await Promise.all([
      notificationService.listForUser(session.user.id),
      notificationService.unreadCount(session.user.id),
    ]);
    return NextResponse.json({ items, unread });
  } catch (err) {
    console.error("Failed to load notifications:", err);
    return NextResponse.json({ error: "Could not load notifications." }, { status: 500 });
  }
}
