import { put, get } from "@vercel/blob";
import { IDocumentRepository, IClaimRepository } from "@/repositories/interfaces";
import { PrismaDocumentRepository } from "@/repositories/document.repository";
import { PrismaClaimRepository } from "@/repositories/claim.repository";
import { ServiceError } from "./claim.service";

const MAX_SIZE_BYTES = 10 * 1024 * 1024; // 10MB, matches the dropzone copy
const ALLOWED_TYPES = ["application/pdf", "image/png", "image/jpeg"];

export class DocumentService {
  constructor(
    private readonly documents: IDocumentRepository = new PrismaDocumentRepository(),
    private readonly claims: IClaimRepository = new PrismaClaimRepository()
  ) {}

  async uploadForClaim(claimId: string, requesterId: string, file: File) {
    const claim = await this.claims.findById(claimId);
    if (!claim) throw new ServiceError("Claim not found.", 404);
    if (claim.userId !== requesterId) throw new ServiceError("You can only upload documents to your own claims.", 403);

    if (file.size > MAX_SIZE_BYTES) throw new ServiceError("File exceeds the 10MB limit.", 400);
    if (!ALLOWED_TYPES.includes(file.type)) throw new ServiceError("Only PDF, PNG, and JPG files are accepted.", 400);

    if (!process.env.BLOB_READ_WRITE_TOKEN) {
      throw new ServiceError(
        "File storage isn't configured yet. Set BLOB_READ_WRITE_TOKEN (Vercel Blob) to enable uploads.",
        503
      );
    }

    const blob = await put(`claims/${claimId}/${Date.now()}-${file.name}`, file, { access: "private" });

    return this.documents.createForClaim({
      claimId,
      fileName: file.name,
      fileUrl: blob.url,
      mimeType: file.type,
      sizeBytes: file.size,
    });
  }

  listForClaim(claimId: string) {
    return this.documents.listForClaim(claimId);
  }

  async downloadForClaim(claimId: string, docId: string, requesterId: string, requesterRole: string) {
    const claim = await this.claims.findById(claimId);
    if (!claim) throw new ServiceError("Claim not found.", 404);

    const isOwner = claim.userId === requesterId;
    const isStaff = requesterRole === "PROCESSOR" || requesterRole === "ADMIN";
    if (!isOwner && !isStaff) throw new ServiceError("Forbidden.", 403);

    const doc = await this.documents.findById(docId);
    if (!doc || doc.claimId !== claimId) throw new ServiceError("Document not found.", 404);

    const result = await get(doc.fileUrl, { access: "private" });
    if (!result) throw new ServiceError("File content unavailable.", 404);

    return { stream: result.stream, contentType: result.blob.contentType, fileName: doc.fileName };
  }
}