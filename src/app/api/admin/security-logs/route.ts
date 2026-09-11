import { NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { AuditService } from "@/services/audit.service";

const auditService = new AuditService();

// GET /api/admin/security-logs â€” powers the Admin "Security Logs" module
export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session || session.user.role !== "ADMIN") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  try {
    const logs = await auditService.list(200);
    return NextResponse.json(logs);
  } catch (err) {
    console.error("Failed to load audit logs:", err);
    return NextResponse.json({ error: "Could not load security logs." }, { status: 500 });
  }
}
