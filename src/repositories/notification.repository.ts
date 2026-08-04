import { NotificationType, PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { INotificationRepository } from "./interfaces";

export class PrismaNotificationRepository implements INotificationRepository {
  constructor(private readonly db: PrismaClient = prisma) {}

  createForUser(userId: string, type: NotificationType, message: string, claimId?: string) {
    return this.db.notification.create({ data: { userId, type, message, claimId } });
  }

  listForUser(userId: string) {
    return this.db.notification.findMany({
      where: { userId },
      orderBy: { createdAt: "desc" },
      take: 50,
    });
  }

  markRead(id: string, userId: string) {
    return this.db.notification.updateMany({ where: { id, userId }, data: { read: true } });
  }

  unreadCount(userId: string) {
    return this.db.notification.count({ where: { userId, read: false } });
  }
}
