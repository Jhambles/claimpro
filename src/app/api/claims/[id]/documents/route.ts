import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { DocumentService } from "@/services/document.service";
import { ServiceError } from "@/services/claim.service";

const documentService = new DocumentService();

// POST /api/claims/:id/documents — upload supporting evidence (multipart/form-data, field "file")
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const form = await req.formData();
  const file = form.get("file");
  if (!(file instanceof File)) return NextResponse.json({ error: "No file provided." }, { status: 400 });

  try {
    const doc = await documentService.uploadForClaim(params.id, session.user.id, file);
    return NextResponse.json(doc, { status: 201 });
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}

// GET /api/claims/:id/documents — list evidence for a claim
export async function GET(_req: NextRequest, { params }: { params: { id: string } }) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const docs = await documentService.listForClaim(params.id);
  return NextResponse.json(docs);
}
