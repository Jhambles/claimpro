import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { z } from "zod";
import { authOptions } from "@/lib/auth";
import { ChatService } from "@/services/chat.service";

const chatService = new ChatService();
const messageSchema = z.object({ message: z.string().min(1).max(2000) });

// GET /api/chat — conversation history for the widget
export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const history = await chatService.history(session.user.id);
  return NextResponse.json(history);
}

// POST /api/chat — send a message to Clai, the support assistant
export async function POST(req: NextRequest) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const body = await req.json();
  const parsed = messageSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  try {
    const reply = await chatService.reply(session.user.id, parsed.data.message, session.user.role);
    return NextResponse.json({ reply });
  } catch (err) {
    console.error("Chat request failed:", err);
    return NextResponse.json({ error: "Clai couldn't respond just now. Please try again." }, { status: 500 });
  }
}
