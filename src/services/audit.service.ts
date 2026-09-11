import { IAuditLogRepository } from "@/repositories/interfaces";
import { PrismaAuditLogRepository } from "@/repositories/audit-log.repository";

// Backs the Admin â†’ Security Logs module. Called from the services that
// perform security-relevant actions (user provisioning, claim decisions,
// payouts) rather than from routes directly, so the log stays consistent
// regardless of which route triggered the action.
export class AuditService {
  constructor(private readonly logs: IAuditLogRepository = new PrismaAuditLogRepository()) {}

  async log(entry: { actorId?: string; actorName: string; actorRole: string; action: string; detail?: string }) {
    try {
      await this.logs.log(entry);
    } catch (err) {
      // Never let audit logging break the action it's describing.
      console.error("Failed to write audit log:", err);
    }
  }

  list(limit?: number) {
    return this.logs.list(limit);
  }
}
