import { randomUUID } from "crypto";
import { del, put } from "@vercel/blob";
import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/prisma";
import { hashPassword } from "@/lib/password";

const MAX_FILE_SIZE = 4 * 1024 * 1024;
const signupSchema = z.object({
  name: z.string().trim().min(1).max(120),
  email: z.string().trim().email().max(254),
  password: z.string().min(8).max(128),
});

function isValidImage(type: string, bytes: Uint8Array) {
  if (type === "image/png") {
    return bytes.length >= 8 && [137, 80, 78, 71, 13, 10, 26, 10].every((byte, i) => bytes[i] === byte);
  }
  return type === "image/jpeg" && bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
}

export async function POST(request: NextRequest) {
  let uploadedUrl: string | undefined;

  try {
    const form = await request.formData();
    const formEmail = form.get("email");
    const parsed = signupSchema.safeParse({
      name: form.get("name"),
      email: typeof formEmail === "string" ? formEmail.toLowerCase() : formEmail,
      password: form.get("password"),
    });
    const idPhoto = form.get("idPhoto");
    if (!parsed.success) {
      return NextResponse.json({ error: "Enter a valid name, email, and password (at least 8 characters)." }, { status: 400 });
    }
    if (!(idPhoto instanceof File) || idPhoto.size === 0) {
      return NextResponse.json({ error: "A photo of a valid ID is required." }, { status: 400 });
    }
    if (idPhoto.size > MAX_FILE_SIZE) {
      return NextResponse.json({ error: "ID photo must be 4 MB or smaller." }, { status: 400 });
    }

    const bytes = new Uint8Array(await idPhoto.arrayBuffer());
    if (!isValidImage(idPhoto.type, bytes)) {
      return NextResponse.json({ error: "ID photo must be a valid JPG or PNG image." }, { status: 400 });
    }
    if (!process.env.BLOB_READ_WRITE_TOKEN) {
      return NextResponse.json({ error: "ID photo storage is not configured. Please try again later." }, { status: 503 });
    }
    if (await prisma.user.findUnique({ where: { email: parsed.data.email }, select: { id: true } })) {
      return NextResponse.json({ error: "An account with that email already exists." }, { status: 409 });
    }

    const extension = idPhoto.type === "image/png" ? "png" : "jpg";
    const blob = await put(`user-ids/${randomUUID()}.${extension}`, idPhoto, { access: "private" });
    uploadedUrl = blob.url;

    const user = await prisma.user.create({
      data: {
        name: parsed.data.name,
        email: parsed.data.email,
        passwordHash: await hashPassword(parsed.data.password),
        role: "CLIENT",
        verificationStatus: "PENDING",
        idDocumentUrl: blob.url,
        idDocumentName: idPhoto.name.slice(0, 120),
      },
      select: { id: true },
    });
    return NextResponse.json({ id: user.id }, { status: 201 });
  } catch (error) {
    if (uploadedUrl) {
      try {
        await del(uploadedUrl);
      } catch (cleanupError) {
        console.error("Failed to remove ID photo after registration error:", cleanupError);
      }
    }
    if (error && typeof error === "object" && "code" in error && error.code === "P2002") {
      return NextResponse.json({ error: "An account with that email already exists." }, { status: 409 });
    }
    console.error("Account registration failed:", error);
    return NextResponse.json({ error: "Could not create your account. Please try again." }, { status: 500 });
  }
}
