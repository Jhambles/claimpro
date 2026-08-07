import { prisma } from "@/lib/prisma";
import { IClaimRepository } from "@/repositories/interfaces";
import { PrismaClaimRepository } from "@/repositories/claim.repository";
import { StatsService } from "./stats.service";
import { ILoaRepository } from "@/repositories/interfaces";
import { PrismaLoaRepository } from "@/repositories/loa.repository";
import { ServiceError } from "./claim.service";

export class LoaService {
  constructor(
    private readonly loas: ILoaRepository = new PrismaLoaRepository(),
    private readonly claims: IClaimRepository = new PrismaClaimRepository()
  ) {}
 
  async generateForClaim(claimId: string, generatedById: string) {
    const claim = await this.claims.findById(claimId);
    if (!claim) throw new ServiceError("Claim not found.", 404);
    if (claim.status !== "APPROVED") {
      throw new ServiceError("LOA can only be generated for approved claims.", 409);
    }
    if (claim.loa) return claim.loa;
 
    const content = this.buildLetter(claim.referenceId, claim.category, claim.user.name);
    return this.loas.createForClaim(claimId, content, generatedById);
  }
 
  private buildLetter(referenceId: string, category: string, claimantName: string): string {
    const date = new Date().toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric" });
    return [
      "CLAIMS PRO INSURANCE",
      `Date: ${date}`,
      "",
      "LETTER OF AUTHORIZATION",
      "",
      "To Whom It May Concern,",
      "",
      `This document serves as formal authorization for Record #${referenceId}, filed by ${claimantName}.`,
      `The claim regarding ${category.toLowerCase()} coverage has been verified and approved for disbursement.`,
      "",
      "Scan the QR code below to claim your payout via GCash.",
      "",
      "Signature: ________________",
      "Claims Administrator",
    ].join("\n");
  }
}

const SYSTEM_PROMPT = `You are Clai, the friendly support assistant for ClaimsPro, an insurance claims
platform. Help users understand how to submit claims, check claim status, generate a Letter of
Authorization once approved, and claim their payout via GCash, Maya, or PayPal once a claim is
approved for disbursement. Keep answers short (2-4 sentences), warm, and sprinkle in a relevant
emoji or two per message (not excessive). If asked something outside claims/insurance/the
platform, gently redirect. Never invent claim statuses or amounts — tell the user to check their
claims history for specifics.`;

type Role = "CLIENT" | "PROCESSOR" | "ADMIN";

// Rule-based fallback so the assistant still works with zero configuration
// (no ANTHROPIC_API_KEY set) — useful for local dev / demos. Broader keyword
// coverage per topic, plus role-aware entries so Processor/Admin questions
// get a real answer instead of falling through to the generic response.
const COMMON_FAQ: { keywords: string[]; answer: string }[] = [
  { keywords: ["hi", "hello", "hey", "good morning", "good afternoon"], answer: "Hey there! 👋 I'm Clai, your ClaimsPro assistant. Ask me about claims, statuses, documents, LOAs, or payments!" },
  { keywords: ["thank", "thanks", "thx"], answer: "You're welcome! 😊 Anything else I can help with?" },
  { keywords: ["bye", "goodbye", "see you"], answer: "Take care! 👋 Come back anytime you have a question." },
  { keywords: ["who are you", "what are you", "what can you do", "help me", "how do you work"], answer: "I'm Clai 🤖 — I can help explain how claims move through the system, and I can also look up your live counts — try asking 'how many claims do I have?' 📊" },
  { keywords: ["human", "agent", "real person", "representative"], answer: "I'm just a support bot for now, so I can't connect you to a live person 🙏 — for anything urgent, please reach out to your account contact directly." },
  { keywords: ["document", "upload", "evidence", "attach", "receipt", "file size"], answer: "You can attach evidence (PDF, PNG, or JPG, up to 10MB) when submitting a claim, or later from the claim's detail page 📎" },
  { keywords: ["notification", "notify", "bell", "alert"], answer: "The 🔔 bell (top-right) shows updates whenever a claim status changes or a payment goes through — click one to mark it read." },
  { keywords: ["renew", "renewal", "expire", "expiring"], answer: "Renewal reminders go out automatically as an approved policy nears its renewal window — keep an eye on your 🔔 notifications for that nudge." },
  { keywords: ["login", "log in", "password", "sign in", "account locked", "forgot password"], answer: "If you're having trouble signing in, double check your email and password — for a reset, please contact your administrator for now 🔑" },
  { keywords: ["medical", "hospitalization"], answer: "Medical Expense Coverage handles hospitalization and treatment-related costs — attach medical records or receipts when you submit 🏥" },
  { keywords: ["automotive", "car", "vehicle", "accident"], answer: "Automotive Damage claims cover accidental vehicle damage — photos and repair estimates make great supporting evidence 🚗" },
  { keywords: ["home", "homeowner", "property"], answer: "Homeowners Protection covers property damage claims — receipts, photos, and any assessor reports help speed up verification 🏠" },
];

const CLIENT_FAQ: { keywords: string[]; answer: string }[] = [
  { keywords: ["submit", "new claim", "file a claim", "how to claim"], answer: "To submit a claim, go to your Claimant dashboard, pick a policy category, enter your estimate, attach your documents, then hit Submit for Verification 📝✅" },
  { keywords: ["loa", "letter of authorization"], answer: "Once your claim is Approved, a View LOA button appears in your claims history — click it to generate your Letter of Authorization 📄✨" },
  { keywords: ["pay", "gcash", "maya", "paypal", "payment", "payout", "claim my money", "disbursement"], answer: "Once your claim is approved, head to its detail page to claim your payout via GCash, Maya, or PayPal — you can also scan the QR code on your LOA to jump straight there 💸" },
];

const PROCESSOR_FAQ: { keywords: string[]; answer: string }[] = [
  { keywords: ["queue"], answer: "Your Verification Queue lists every claim needing action, newest first — click a reference ID to see full details and documents 📋" },
];

const ADMIN_FAQ: { keywords: string[]; answer: string }[] = [
  { keywords: ["add user", "create user", "create account", "new account", "provision"], answer: "Head to Identity Manager and use the 'Provision New Account' form — set a name, email, temporary password, and role 👤" },
  { keywords: ["identity manager", "manage users", "user list"], answer: "Identity Manager (left sidebar) lists every account and lets you provision new Claimant, Processor, or Admin users 🗂️" },
];

// --- Dynamic, data-backed answers -------------------------------------------
// These run BEFORE the static FAQ pools above and query the database live, so
// "how many claims have I submitted" gets your actual numbers instead of a
// canned sentence. Each returns null if the message doesn't match, so the
// caller falls through to the static pools.

interface ChatContext {
  userId: string;
  role?: Role;
  claims: IClaimRepository;
}

type DynamicHandler = (message: string, ctx: ChatContext) => Promise<string | null>;

const STATUS_COUNT_WORDS = ["how many", "count", "number of", "status of my"];

function mentionsCounts(lower: string): boolean {
  return STATUS_COUNT_WORDS.some((w) => lower.includes(w));
}

const clientCountHandler: DynamicHandler = async (message, ctx) => {
  const lower = message.toLowerCase();
  const asksAboutClaims = lower.includes("claim") || lower.includes("submit") || lower.includes("status");
  if (!mentionsCounts(lower) && !(asksAboutClaims && (lower.includes("pending") || lower.includes("verified") || lower.includes("approved") || lower.includes("rejected")))) {
    return null;
  }

  const counts = await ctx.claims.countByUserAndStatus(ctx.userId);
  const total = counts.PENDING + counts.VERIFIED + counts.APPROVED + counts.REJECTED;

  if (total === 0) {
    return "You haven't submitted any claims yet 📝 — head to New Claim Request to file your first one!";
  }

  if (lower.includes("approved")) {
    return `You have ${counts.APPROVED} approved claim${counts.APPROVED === 1 ? "" : "s"} out of ${total} total ✅`;
  }
  if (lower.includes("rejected") || lower.includes("denied")) {
    return `${counts.REJECTED} of your ${total} claim${total === 1 ? "" : "s"} ${counts.REJECTED === 1 ? "was" : "were"} rejected.`;
  }
  if (lower.includes("verified")) {
    return `${counts.VERIFIED} of your claims are currently Verified and awaiting final approval 🔎`;
  }
  if (lower.includes("pending")) {
    return `You have ${counts.PENDING} claim${counts.PENDING === 1 ? "" : "s"} still Pending review.`;
  }

  return `Here's where your ${total} claim${total === 1 ? "" : "s"} stand: ${counts.PENDING} Pending, ${counts.VERIFIED} Verified, ${counts.APPROVED} Approved, ${counts.REJECTED} Rejected 📊`;
};

const processorCountHandler: DynamicHandler = async (message, ctx) => {
  const lower = message.toLowerCase();
  const asksAboutWork = lower.includes("verify") || lower.includes("verified") || lower.includes("approve") || lower.includes("approved") || lower.includes("decline") || lower.includes("reject");
  if (!mentionsCounts(lower) && !asksAboutWork) return null;

  const counts = await ctx.claims.countByProcessorAndStatus(ctx.userId);
  const pendingInQueue = await ctx.claims.countByStatus("PENDING");
  const handled = counts.VERIFIED + counts.APPROVED + counts.REJECTED;

  if (lower.includes("approve")) {
    return `You've approved ${counts.APPROVED} claim${counts.APPROVED === 1 ? "" : "s"} so far ✅`;
  }
  if (lower.includes("decline") || lower.includes("reject")) {
    return `You've rejected ${counts.REJECTED} claim${counts.REJECTED === 1 ? "" : "s"} so far.`;
  }
  if (lower.includes("verify") || lower.includes("verified")) {
    return `You currently have ${counts.VERIFIED} claim${counts.VERIFIED === 1 ? "" : "s"} you've verified and awaiting approval, out of ${handled} you've handled in total.`;
  }

  return `You've handled ${handled} claim${handled === 1 ? "" : "s"} total — ${counts.VERIFIED} Verified (awaiting approval), ${counts.APPROVED} Approved, ${counts.REJECTED} Rejected. There ${pendingInQueue === 1 ? "is" : "are"} also ${pendingInQueue} claim${pendingInQueue === 1 ? "" : "s"} still Pending in the shared queue 📋`;
};

const adminCountHandler: DynamicHandler = async (message, ctx) => {
  const lower = message.toLowerCase();
  if (!mentionsCounts(lower) && !lower.includes("stats") && !lower.includes("dashboard") && !lower.includes("system health")) return null;

  const stats = await new StatsService().getSystemStats();
  return `Live system numbers: ${stats.totalRequests} total claims, ${stats.approvalRate}% approval rate, ${stats.loaGenerationRate}% of approved claims have an LOA generated 📊`;
};

async function dynamicReply(message: string, ctx: ChatContext): Promise<string | null> {
  const handler = ctx.role === "PROCESSOR" ? processorCountHandler : ctx.role === "ADMIN" ? adminCountHandler : ctx.role === "CLIENT" ? clientCountHandler : null;
  if (!handler) return null;
  try {
    return await handler(message, ctx);
  } catch (err) {
    console.error("Dynamic chat handler failed:", err);
    return null;
  }
}

function staticFallbackReply(message: string, role?: Role): string {
  const lower = message.toLowerCase();
  const roleFaq = role === "PROCESSOR" ? PROCESSOR_FAQ : role === "ADMIN" ? ADMIN_FAQ : role === "CLIENT" ? CLIENT_FAQ : [];

  // Role-specific entries first (most relevant to whoever's asking), then the
  // shared ones, then fall back across every list in case someone asks about
  // another role's flow (e.g. a claimant curious how approval works).
  const pools = [roleFaq, COMMON_FAQ, CLIENT_FAQ, PROCESSOR_FAQ, ADMIN_FAQ];
  for (const pool of pools) {
    const match = pool.find((f) => f.keywords.some((k) => lower.includes(k)));
    if (match) return match.answer;
  }

  return "I'm not totally sure about that one 🤔 — try asking about submitting a claim, checking status, documents, LOAs, payments, or your live counts!";
}

export class ChatService {
  constructor(private readonly claims: IClaimRepository = new PrismaClaimRepository()) {}

  async reply(userId: string, message: string, role?: Role): Promise<string> {
    await prisma.chatMessage.create({ data: { userId, role: "user", content: message } });

    const apiKey = process.env.ANTHROPIC_API_KEY;
    let reply: string;

    if (apiKey) {
      try {
        const history = await prisma.chatMessage.findMany({
          where: { userId },
          orderBy: { createdAt: "desc" },
          take: 10,
        });
        const messages = history
          .reverse()
          .map((m) => ({ role: m.role as "user" | "assistant", content: m.content }));

        const res = await fetch("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
          },
          body: JSON.stringify({
            model: "claude-sonnet-5",
            max_tokens: 300,
            system: role ? `${SYSTEM_PROMPT}\n\nThe person you're talking to is signed in with the ${role} role.` : SYSTEM_PROMPT,
            messages,
          }),
        });

        if (!res.ok) throw new Error(`Anthropic API error: ${res.status}`);
        const data = await res.json();
        reply = data.content?.map((b: any) => b.text ?? "").join("") || (await this.fallback(message, userId, role));
      } catch (err) {
        console.error("Chat API call failed, using fallback:", err);
        reply = await this.fallback(message, userId, role);
      }
    } else {
      reply = await this.fallback(message, userId, role);
    }

    await prisma.chatMessage.create({ data: { userId, role: "assistant", content: reply } });
    return reply;
  }

  private async fallback(message: string, userId: string, role?: Role): Promise<string> {
    const dynamic = await dynamicReply(message, { userId, role, claims: this.claims });
    return dynamic ?? staticFallbackReply(message, role);
  }

  async history(userId: string) {
    return prisma.chatMessage.findMany({ where: { userId }, orderBy: { createdAt: "asc" }, take: 50 });
  }
}
