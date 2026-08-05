import { Claim, ClaimStatus, Document, Loa, Payment, PolicyCategory, Role, User } from "@prisma/client";

// Abstractions (DIP): services depend on these interfaces, not on Prisma directly.
// Swapping persistence (e.g. to a mock in tests, or a different DB) means writing
// a new class that satisfies the interface — the service layer never changes (OCP).

export type ClaimWithRelations = Claim & {
  user: Pick<User, "id" | "name" | "email">;
  documents: Document[];
  loa: Loa | null;
  payments: Payment[];
};

export interface IClaimRepository {
  findMany(filter: { userId?: string; status?: ClaimStatus }): Promise<ClaimWithRelations[]>;
  findById(id: string): Promise<ClaimWithRelations | null>;
  create(data: { userId: string; category: PolicyCategory; estimate: number; referenceId: string }): Promise<ClaimWithRelations>;
  updateStatus(id: string, status: ClaimStatus, processorId: string): Promise<ClaimWithRelations>;
  count(): Promise<number>;
  countByStatus(status: ClaimStatus): Promise<number>;
  countByCategory(): Promise<Record<PolicyCategory, number>>;
  countByUserAndStatus(userId: string): Promise<Record<ClaimStatus, number>>;
  countByProcessorAndStatus(processorId: string): Promise<Record<ClaimStatus, number>>;
}

export interface IUserRepository {
  findByEmail(email: string): Promise<User | null>;
  findById(id: string): Promise<User | null>;
  create(data: { name: string; email: string; passwordHash: string; role: Role }): Promise<User>;
  countAll(): Promise<number>;
}

export interface ILoaRepository {
  createForClaim(claimId: string, content: string, generatedById: string): Promise<Loa>;
  count(): Promise<number>;
}

export interface INotificationRepository {
  createForUser(userId: string, type: "STATUS_UPDATE" | "RENEWAL" | "PAYMENT", message: string, claimId?: string): Promise<any>;
  listForUser(userId: string): Promise<any[]>;
  markRead(id: string, userId: string): Promise<any>;
  unreadCount(userId: string): Promise<number>;
}

export interface IPaymentRepository {
  create(data: { claimId: string; provider: "GCASH" | "MAYA" | "PAYPAL"; amount: number; providerRef?: string }): Promise<any>;
  findById(id: string): Promise<any>;
  updateStatus(id: string, status: "PENDING" | "PAID" | "FAILED"): Promise<any>;
  listForClaim(claimId: string): Promise<any[]>;
}

export interface IDocumentRepository {
  createForClaim(data: { claimId: string; fileName: string; fileUrl: string; mimeType: string; sizeBytes: number }): Promise<Document>;
  listForClaim(claimId: string): Promise<Document[]>;
  findById(id: string): Promise<Document | null>;
}