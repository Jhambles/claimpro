import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { DocumentService } from "@/services/document.service";
import { ServiceError } from "@/services/claim.service";

const documentService = new DocumentService();

// GET /api/claims/:id/documents/:docId — stream a private document (owner or staff only)
export async function GET(_req: NextRequest, { params }: { params: { id: string; docId: string } }) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  try {
    const { stream, contentType, fileName } = await documentService.downloadForClaim(
      params.id,
      params.docId,
      session.user.id,
      session.user.role
    );

    return new NextResponse(stream as unknown as ReadableStream, {
      headers: {
        "Content-Type": contentType ?? "application/octet-stream",
        "Content-Disposition": `inline; filename="${fileName}"`,
        "X-Content-Type-Options": "nosniff",
        "Cache-Control": "private, no-cache",
      },
    });
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}