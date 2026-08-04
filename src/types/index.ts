export type Role = "CLIENT" | "PROCESSOR" | "ADMIN";
export type PolicyCategory = "MEDICAL" | "AUTOMOTIVE" | "HOMEOWNERS";
export type ClaimStatus = "PENDING" | "VERIFIED" | "APPROVED" | "REJECTED";

export interface DocumentDTO {
  id: string;
  fileName: string;
  fileUrl: string;
  mimeType: string;
  sizeBytes: number;
  uploadedAt: string;
}

export interface PaymentDTO {
  id: string;
  provider: "GCASH" | "MAYA" | "PAYPAL";
  amount: string;
  status: "PENDING" | "PAID" | "FAILED";
  createdAt: string;
}

export interface LoaDTO {
  id: string;
  content: string;
  generatedAt: string;
  qrCodeDataUrl?: string;
  payoutUrl?: string;
}

export interface ClaimDTO {
  id: string;
  referenceId: string;
  category: PolicyCategory;
  estimate: string;
  status: ClaimStatus;
  createdAt: string;
  user: { id: string; name: string; email: string };
  documents?: DocumentDTO[];
  payments?: PaymentDTO[];
  loa?: LoaDTO | null;
}

export interface NotificationDTO {
  id: string;
  type: "STATUS_UPDATE" | "RENEWAL" | "PAYMENT";
  message: string;
  read: boolean;
  createdAt: string;
}

export interface CreateClaimInput {
  category: PolicyCategory;
  estimate: number;
}

export interface UpdateClaimStatusInput {
  status: ClaimStatus;
}

export interface SystemStats {
  totalRequests: number;
  approvalRate: number;
  loaGenerationRate: number;
  claimsByCategory: Record<PolicyCategory, number>;
}
