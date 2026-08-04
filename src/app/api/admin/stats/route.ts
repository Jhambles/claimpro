import { NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { StatsService } from "@/services/stats.service";

const statsService = new StatsService();

// GET /api/admin/stats — powers the Admin "System Health" dashboard
export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session || session.user.role !== "ADMIN") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  try {
    const stats = await statsService.getSystemStats();
    return NextResponse.json(stats);
  } catch (err) {
    console.error("Failed to load admin stats:", err);
    return NextResponse.json({ error: "Could not load system stats." }, { status: 500 });
  }
}
