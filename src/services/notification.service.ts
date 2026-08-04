import { INotificationRepository } from "@/repositories/interfaces";
import { PrismaNotificationRepository } from "@/repositories/notification.repository";

// Central place for creating and reading notifications. Called by ClaimService
// (status changes), LoaService (LOA ready), PaymentService (payment result),
// and the renewal-reminder endpoint (policy renewal nudges).
export class NotificationService {
  constructor(private readonly notifications: INotificationRepository = new PrismaNotificationRepository()) {}

  notifyStatusChange(userId: string, referenceId: string, status: string, claimId: string) {
    const messages: Record<string, string> = {
      VERIFIED: `Your claim ${referenceId} has been verified and is awaiting final approval.`,
      APPROVED: `Great news — claim ${referenceId} has been approved.`,
      REJECTED: `Claim ${referenceId} was not approved. You can view details in your claims history.`,
    };
    const message = messages[status] ?? `Claim ${referenceId} status changed to ${status}.`;
    return this.notifications.createForUser(userId, "STATUS_UPDATE", message, claimId);
  }

  notifyPayment(userId: string, referenceId: string, status: string, claimId: string) {
    const message =
      status === "PAID"
        ? `Your payout for claim ${referenceId} has been claimed successfully. 🎉`
        : `We couldn't complete your payout claim for ${referenceId}. Please try again.`;
    return this.notifications.createForUser(userId, "PAYMENT", message, claimId);
  }

  notifyRenewal(userId: string, message: string) {
    return this.notifications.createForUser(userId, "RENEWAL", message);
  }

  listForUser(userId: string) {
    return this.notifications.listForUser(userId);
  }

  markRead(id: string, userId: string) {
    return this.notifications.markRead(id, userId);
  }

  unreadCount(userId: string) {
    return this.notifications.unreadCount(userId);
  }
}
