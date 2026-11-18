import { get } from "@vercel/blob";
import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export async function GET(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getServerSession(authOptions);
  if (!session || session.user.role !== "ADMIN") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const { id } = await params;
  const user = await prisma.user.findUnique({
    where: { id },
    select: { idDocumentUrl: true, idDocumentName: true },
  });
  if (!user?.idDocumentUrl) return NextResponse.json({ error: "ID photo not found." }, { status: 404 });

  const result = await get(user.idDocumentUrl, { access: "private" });
  if (!result) return NextResponse.json({ error: "ID photo is unavailable." }, { status: 404 });

  const contentType = result.blob.contentType === "image/png" ? "image/png" : "image/jpeg";
  return new NextResponse(result.stream as unknown as ReadableStream, {
    headers: {
      "Content-Type": contentType,
      "Content-Disposition": `inline; filename="${(user.idDocumentName ?? "identity-document").replace(/["\\\r\n]/g, "_")}"`,
      "X-Content-Type-Options": "nosniff",
      "Cache-Control": "private, no-store",
    },
  });
}
