# ClaimsPro update v2 (PowerShell)
# Run from the ROOT of your ClaimsPro repo (same folder as package.json).
#
# Changes:
#  1. Landing page: removes "Get Started", "Watch Demo" and the "Access Portals"
#     section. The nav "Portal Login" button is the only way in.
#  2. Verify / Approve / Reject now open a confirmation pop-up that REQUIRES a
#     reason (5-500 characters). The reason is validated server-side too.
#  3. Every decision is stored (new claim_decisions table) and shown in a
#     "Decision History" card on the claim page for both staff and the claimant.
#     The claimant's notification bell also includes the reason, and a rejected
#     claim in Claims History links straight to it.
#  4. Approve is disabled while a claim has a red (blocking) flag.

$ErrorActionPreference = "Stop"
Write-Output "Updating ClaimsPro files (v2)..."
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Write-ProjectFile([string]$path, [string]$content) {
  $dir = Split-Path -Parent $path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $fullPath = [System.IO.Path]::GetFullPath($path)
  [System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
  Write-Output "  wrote $path"
}

# ---------------------------------------------------------------------------
# prisma/schema.prisma  (patched in place: adds ClaimDecision + relation)
# ---------------------------------------------------------------------------
$schemaPath = "prisma/schema.prisma"
$schema = [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath($schemaPath)) -replace "`r`n", "`n"
if ($schema -notmatch "model ClaimDecision") {
  $schema = $schema.Replace("  payments    Payment[]`n", "  payments    Payment[]`n  decisions   ClaimDecision[]`n")
  if ($schema -notmatch "decisions   ClaimDecision\[\]") {
    throw "Could not find the 'payments    Payment[]' line in the Claim model - add 'decisions   ClaimDecision[]' to model Claim by hand, then re-run."
  }
  $model = @'
// One row per staff decision (verify / approve / reject) on a claim, with the
// reason the staff member entered in the confirmation pop-up. Kept as history
// rather than a single column so a claim that was verified and later rejected
// shows both reasons.
model ClaimDecision {
  id            String      @id @default(cuid())
  claimId       String
  claim         Claim       @relation(fields: [claimId], references: [id], onDelete: Cascade)
  status        ClaimStatus
  reason        String      @db.Text
  decidedById   String?
  decidedByName String
  decidedByRole String
  createdAt     DateTime    @default(now())

  @@index([claimId, createdAt])
  @@map("claim_decisions")
}
'@
  $schema = $schema.TrimEnd() + "`n`n" + $model
  [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($schemaPath), $schema + "`n", $utf8NoBom)
  Write-Output "  patched prisma/schema.prisma (added ClaimDecision)"
} else {
  Write-Output "  prisma/schema.prisma already has ClaimDecision - skipped"
}

# ---------------------------------------------------------------------------
# Landing page: only the nav "Portal Login" remains
# ---------------------------------------------------------------------------
Write-ProjectFile "src/app/page.tsx" @'
import Image from "next/image";
import Link from "next/link";

export default function LandingPage() {
  return (
    <>
      <nav className="flex justify-between items-center px-12 py-6 border-b border-gray-100 sticky top-0 bg-white/80 backdrop-blur z-50">
        <div className="flex items-center space-x-2">
          <div className="w-8 h-8 bg-teal rounded-sm" />
          <span className="text-2xl font-bold tracking-tighter text-navy">
            CLAIMS<span className="text-teal">PRO</span>
          </span>
        </div>
        <Link
          href="/login"
          className="bg-navy text-white px-8 py-3 rounded-lg hover:bg-teal transition font-bold shadow-lg shadow-slate-200"
        >
          Portal Login
        </Link>
      </nav>

      <section className="relative h-[600px] flex items-center overflow-hidden">
        <div className="absolute inset-0 z-0">
          <Image
            src="https://images.unsplash.com/photo-1450101499163-c8848c66ca85?auto=format&fit=crop&q=80&w=1470"
            alt=""
            fill
            priority
            className="object-cover opacity-10"
          />
          <div className="absolute inset-0 bg-gradient-to-r from-white via-white/40 to-transparent" />
        </div>
        <div className="relative z-10 px-12 max-w-4xl">
          <span className="text-teal font-black tracking-[0.3em] text-sm uppercase mb-4 block">
            Next-Gen Insurance Platform
          </span>
          <h1 className="text-7xl font-black leading-tight text-navy mb-6">
            Efficiency in every <span className="text-teal">Claim.</span>
          </h1>
          <p className="text-xl text-slate-600 leading-relaxed max-w-2xl">
            A cloud-native solution for real-time document verification, automated LOA logic, and
            enterprise-grade claims lifecycle management.
          </p>
        </div>
      </section>

      <footer className="bg-navy py-8 px-12 text-center border-t border-white/10">
        <p className="text-slate-500 text-xs tracking-widest uppercase">
          System Core v3.1 | Protected by Enterprise Encryption
        </p>
      </footer>
    </>
  );
}
'@

# ---------------------------------------------------------------------------
# Decision storage (new repository)
# ---------------------------------------------------------------------------
Write-ProjectFile "src/repositories/claim-decision.repository.ts" @'
import { ClaimStatus, PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/prisma";

export interface DecisionRecord {
  id: string;
  claimId: string;
  status: ClaimStatus;
  reason: string;
  decidedById: string | null;
  decidedByName: string;
  decidedByRole: string;
  createdAt: Date;
}

export interface IClaimDecisionRepository {
  create(data: {
    claimId: string;
    status: ClaimStatus;
    reason: string;
    decidedById?: string;
    decidedByName: string;
    decidedByRole: string;
  }): Promise<DecisionRecord>;
  listForClaim(claimId: string): Promise<DecisionRecord[]>;
}

export class PrismaClaimDecisionRepository implements IClaimDecisionRepository {
  constructor(private readonly db: PrismaClient = prisma) {}

  create(data: {
    claimId: string;
    status: ClaimStatus;
    reason: string;
    decidedById?: string;
    decidedByName: string;
    decidedByRole: string;
  }) {
    return this.db.claimDecision.create({ data });
  }

  listForClaim(claimId: string) {
    return this.db.claimDecision.findMany({ where: { claimId }, orderBy: { createdAt: "asc" } });
  }
}
'@

# ---------------------------------------------------------------------------
# Services
# ---------------------------------------------------------------------------
Write-ProjectFile "src/services/claim.service.ts" @'
import { ClaimStatus, PolicyCategory, Role } from "@prisma/client";
import { IClaimRepository, ClaimWithRelations } from "@/repositories/interfaces";
import { PrismaClaimRepository } from "@/repositories/claim.repository";
import { IClaimDecisionRepository, PrismaClaimDecisionRepository } from "@/repositories/claim-decision.repository";
import { NotificationService } from "./notification.service";
import { AuditService } from "./audit.service";
import { ClaimValidationService } from "./claim-validation.service";

export const MIN_REASON_LENGTH = 5;
export const MAX_REASON_LENGTH = 500;

// Business rules live here (SRP). Route handlers stay thin "controllers" that
// only translate HTTP <-> service calls; the service never touches req/res.
export class ClaimService {
  constructor(
    private readonly claims: IClaimRepository = new PrismaClaimRepository(),
    private readonly notifications: NotificationService = new NotificationService(),
    private readonly audit: AuditService = new AuditService(),
    private readonly validation: ClaimValidationService = new ClaimValidationService(),
    private readonly decisions: IClaimDecisionRepository = new PrismaClaimDecisionRepository()
  ) {}

  private static readonly VALID_TRANSITIONS: Record<ClaimStatus, ClaimStatus[]> = {
    PENDING: ["VERIFIED", "REJECTED"],
    VERIFIED: ["APPROVED", "REJECTED"],
    APPROVED: [],
    REJECTED: [],
  };

  async listClaimsFor(user: { id: string; role: Role }) {
    if (user.role === "CLIENT") {
      return this.claims.findMany({ userId: user.id });
    }
    // Processors and admins see the full queue.
    return this.claims.findMany({});
  }

  getClaim(id: string) {
    return this.claims.findById(id);
  }

  listDecisions(claimId: string) {
    return this.decisions.listForClaim(claimId);
  }

  getValidationIssues(claim: ClaimWithRelations) {
    return this.validation.evaluate(claim);
  }

  async createClaim(userId: string, input: { category: PolicyCategory; estimate: number }) {
    // Number.isFinite rejects NaN and Infinity, unlike a bare `<= 0` check
    // (NaN <= 0 is false in JS, so a malformed estimate used to slip through).
    if (!Number.isFinite(input.estimate) || input.estimate <= 0) {
      throw new ServiceError("Claim estimate must be a valid number greater than zero.", 400);
    }

    // Reference IDs are derived from a count-based sequence, so two near-simultaneous
    // submissions can compute the same value. Retry a few times on the unique-constraint
    // collision instead of failing the request outright.
    const MAX_ATTEMPTS = 5;
    for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
      const referenceId = await this.generateReferenceId();
      try {
        return await this.claims.create({ userId, ...input, referenceId });
      } catch (err: any) {
        const isUniqueConflict = err?.code === "P2002";
        if (!isUniqueConflict || attempt === MAX_ATTEMPTS - 1) throw err;
      }
    }
    throw new ServiceError("Could not generate a unique reference ID. Please try again.", 500);
  }

  // `reason` is mandatory for every staff decision (verify / approve / reject).
  // It is enforced here, not just in the UI, so the API can't be used to skip it.
  async transitionStatus(
    claimId: string,
    nextStatus: ClaimStatus,
    processorId: string,
    reason: string,
    actor?: { name: string; role: string }
  ) {
    const trimmedReason = (reason ?? "").trim();
    if (trimmedReason.length < MIN_REASON_LENGTH) {
      throw new ServiceError(`Please state a reason (at least ${MIN_REASON_LENGTH} characters).`, 400);
    }
    if (trimmedReason.length > MAX_REASON_LENGTH) {
      throw new ServiceError(`The reason is too long (maximum ${MAX_REASON_LENGTH} characters).`, 400);
    }

    const claim = await this.claims.findById(claimId);
    if (!claim) throw new ServiceError("Claim not found.", 404);

    const allowed = ClaimService.VALID_TRANSITIONS[claim.status];
    if (!allowed.includes(nextStatus)) {
      throw new ServiceError(`Cannot move claim from ${claim.status} to ${nextStatus}.`, 409);
    }

    // Don't let a claim advance to APPROVED while it's still missing required
    // information (documents, a valid estimate) or has internally-inconsistent
    // data (e.g. corrupted uploads, a payout that already exceeds the
    // estimate) — this is the concrete enforcement behind "prevent outdated
    // or incorrect information from being used", not just an informational
    // display staff have to remember to check.
    if (nextStatus === "APPROVED") {
      const blocking = this.validation.evaluate(claim).filter((i) => i.severity === "blocking");
      if (blocking.length > 0) {
        throw new ServiceError(
          `Cannot approve this claim - unresolved issues: ${blocking.map((i) => i.message).join(" ")}`,
          422
        );
      }
    }

    const updated = await this.claims.updateStatus(claimId, nextStatus, processorId);

    try {
      await this.decisions.create({
        claimId,
        status: nextStatus,
        reason: trimmedReason,
        decidedById: processorId,
        decidedByName: actor?.name ?? "Staff",
        decidedByRole: actor?.role ?? "PROCESSOR",
      });
    } catch (err) {
      // The status change is already persisted; the reason still reaches the
      // claimant through the notification and the audit log below.
      console.error("Failed to record claim decision:", err);
    }

    try {
      // Awaited (not fire-and-forget): on a serverless runtime like Vercel, an
      // un-awaited promise can be cut off the instant the response is sent, so
      // a "best-effort" background write could silently never land.
      await this.notifications.notifyStatusChange(updated.userId, updated.referenceId, nextStatus, updated.id, trimmedReason);
    } catch (err) {
      // A notification failure still shouldn't fail the (already-persisted) status change.
      console.error("Failed to create status-change notification:", err);
    }

    if (actor) {
      await this.audit.log({
        actorId: processorId,
        actorName: actor.name,
        actorRole: actor.role,
        action: "CLAIM_STATUS_CHANGED",
        detail: `${updated.referenceId} moved from ${claim.status} to ${nextStatus}. Reason: ${trimmedReason}`,
      });
    }

    return updated;
  }

  private async generateReferenceId(): Promise<string> {
    const year = new Date().getFullYear();
    const count = await this.claims.count();
    // Mix in a short random suffix so two requests racing on the same `count`
    // don't produce the exact same reference ID (the retry loop above still
    // catches the rare remaining collision).
    const randomSuffix = Math.random().toString(36).slice(2, 5).toUpperCase();
    const sequence = (count + 1).toString(36).toUpperCase();
    return `CLM-${year}-X${sequence}${randomSuffix}`;
  }
}

export class ServiceError extends Error {
  constructor(message: string, public readonly statusCode: number) {
    super(message);
    this.name = "ServiceError";
  }
}
'@

Write-ProjectFile "src/services/notification.service.ts" @'
import { INotificationRepository } from "@/repositories/interfaces";
import { PrismaNotificationRepository } from "@/repositories/notification.repository";

// Central place for creating and reading notifications. Called by ClaimService
// (status changes), LoaService (LOA ready), PaymentService (payment result),
// and the renewal-reminder endpoint (policy renewal nudges).
export class NotificationService {
  constructor(private readonly notifications: INotificationRepository = new PrismaNotificationRepository()) {}

  notifyStatusChange(userId: string, referenceId: string, status: string, claimId: string, reason?: string) {
    const messages: Record<string, string> = {
      VERIFIED: `Your claim ${referenceId} has been verified and is awaiting final approval.`,
      APPROVED: `Great news - claim ${referenceId} has been approved.`,
      REJECTED: `Claim ${referenceId} was not approved. You can view details in your claims history.`,
    };
    const base = messages[status] ?? `Claim ${referenceId} status changed to ${status}.`;
    const message = reason ? `${base} Reason: ${reason}` : base;
    return this.notifications.createForUser(userId, "STATUS_UPDATE", message, claimId);
  }

  notifyPayment(userId: string, referenceId: string, status: string, claimId: string) {
    const message =
      status === "PAID"
        ? `Your payout for claim ${referenceId} has been claimed successfully. 🎉`
        : `We couldn't complete your payout claim for ${referenceId}. Please try again.`;
    return this.notifications.createForUser(userId, "PAYMENT", message, claimId);
  }

  notifyRenewal(userId: string, message: string) {
    return this.notifications.createForUser(userId, "RENEWAL", message);
  }

  listForUser(userId: string) {
    return this.notifications.listForUser(userId);
  }

  markRead(id: string, userId: string) {
    return this.notifications.markRead(id, userId);
  }

  unreadCount(userId: string) {
    return this.notifications.unreadCount(userId);
  }
}
'@

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------
Write-ProjectFile "src/app/api/claims/[id]/route.ts" @'
import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { z } from "zod";
import { authOptions } from "@/lib/auth";
import { ClaimService, ServiceError, MIN_REASON_LENGTH, MAX_REASON_LENGTH } from "@/services/claim.service";

const claimService = new ClaimService();

const updateStatusSchema = z.object({
  status: z.enum(["VERIFIED", "APPROVED", "REJECTED"]),
  reason: z
    .string()
    .trim()
    .min(MIN_REASON_LENGTH, `Please state a reason (at least ${MIN_REASON_LENGTH} characters).`)
    .max(MAX_REASON_LENGTH, `The reason is too long (maximum ${MAX_REASON_LENGTH} characters).`),
});

// GET /api/claims/:id
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const claim = await claimService.getClaim(id);
  if (!claim) return NextResponse.json({ error: "Not found" }, { status: 404 });

  if (session.user.role === "CLIENT" && claim.userId !== session.user.id) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const issues = claimService.getValidationIssues(claim);
  const decisionRows = await claimService.listDecisions(id);
  const decisions = decisionRows.map((d) => ({
    id: d.id,
    status: d.status,
    reason: d.reason,
    decidedByName: d.decidedByName,
    decidedByRole: d.decidedByRole,
    createdAt: d.createdAt,
  }));
  return NextResponse.json({ ...claim, issues, decisions });
}

// PATCH /api/claims/:id — advance claim status with a stated reason (PROCESSOR / ADMIN only)
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (session.user.role === "CLIENT") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const body = await req.json().catch(() => ({}));
  const parsed = updateStatusSchema.safeParse(body);
  if (!parsed.success) {
    const first = parsed.error.issues[0];
    return NextResponse.json(
      { error: first?.path[0] === "reason" ? first.message : "Invalid request." },
      { status: 400 }
    );
  }

  try {
    const claim = await claimService.transitionStatus(id, parsed.data.status, session.user.id, parsed.data.reason, {
      name: session.user.name ?? session.user.email,
      role: session.user.role,
    });
    return NextResponse.json(claim);
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}
'@

Write-ProjectFile "src/types/index.ts" @'
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
  provider: "GCASH" | "MAYA" | "PAYPAL" | "BANK_TRANSFER";
  amount: string;
  status: "PENDING" | "PAID" | "FAILED";
  bankName?: string | null;
  accountName?: string | null;
  accountNumber?: string | null;
  createdAt: string;
}

export interface LoaDTO {
  id: string;
  content: string;
  generatedAt: string;
  provider?: "GCASH" | "MAYA" | "PAYPAL" | "BANK_TRANSFER";
  providerLabel?: string;
  qrCodeDataUrl?: string;
  payoutUrl?: string;
}

export interface ClaimIssue {
  code: string;
  severity: "blocking" | "warning";
  message: string;
}

export interface DecisionDTO {
  id: string;
  status: ClaimStatus;
  reason: string;
  decidedByName: string;
  decidedByRole: string;
  createdAt: string;
}

export interface ClaimDTO {
  id: string;
  referenceId: string;
  category: PolicyCategory;
  estimate: string;
  status: ClaimStatus;
  createdAt: string;
  updatedAt: string;
  processorId?: string | null;
  user: { id: string; name: string; email: string };
  documents?: DocumentDTO[];
  payments?: PaymentDTO[];
  loa?: LoaDTO | null;
  issues?: ClaimIssue[];
  decisions?: DecisionDTO[];
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
  reason: string;
}

export interface SystemStats {
  totalRequests: number;
  approvalRate: number;
  loaGenerationRate: number;
  claimsByCategory: Record<PolicyCategory, number>;
}
'@

# ---------------------------------------------------------------------------
# UI: reason pop-up
# ---------------------------------------------------------------------------
Write-ProjectFile "src/components/ui/DecisionModal.tsx" @'
"use client";
import { useState } from "react";

export type DecisionStatus = "VERIFIED" | "APPROVED" | "REJECTED";

const MIN_REASON_LENGTH = 5;
const MAX_REASON_LENGTH = 500;

const COPY: Record<DecisionStatus, { title: string; prompt: string; button: string; buttonClass: string }> = {
  VERIFIED: {
    title: "Verify this claim",
    prompt: "Why are you verifying this claim?",
    button: "Confirm Verify",
    buttonClass: "bg-navy hover:bg-teal",
  },
  APPROVED: {
    title: "Approve this claim",
    prompt: "Why are you approving this claim?",
    button: "Confirm Approve",
    buttonClass: "bg-teal hover:opacity-90",
  },
  REJECTED: {
    title: "Reject this claim",
    prompt: "Why are you rejecting this claim?",
    button: "Confirm Reject",
    buttonClass: "bg-red-500 hover:bg-red-600",
  },
};

// Rendered only while a decision is pending (parent mounts it on click and
// unmounts it on cancel/success), so its state always starts fresh.
// onConfirm should throw an Error with a readable message to keep the pop-up
// open and show that message (e.g. the server's "unresolved issues" text).
export function DecisionModal({
  status,
  referenceId,
  onCancel,
  onConfirm,
}: {
  status: DecisionStatus;
  referenceId?: string;
  onCancel: () => void;
  onConfirm: (reason: string) => Promise<void>;
}) {
  const [reason, setReason] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const copy = COPY[status];
  const trimmed = reason.trim();
  const tooShort = trimmed.length < MIN_REASON_LENGTH;

  async function confirm() {
    if (tooShort) {
      setError(`Please state a reason (at least ${MIN_REASON_LENGTH} characters).`);
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      await onConfirm(trimmed);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong. Please try again.");
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-[60] bg-black/50 flex items-center justify-center p-6" role="dialog" aria-modal="true">
      <div className="bg-white rounded-3xl shadow-2xl w-full max-w-lg p-8 text-slate-800">
        <h2 className="text-2xl font-black text-navy">{copy.title}</h2>
        {referenceId && <p className="font-mono text-xs text-slate-400 mt-1">{referenceId}</p>}

        <label className="text-[10px] font-black text-slate-400 uppercase block mt-6 mb-2">{copy.prompt}</label>
        <textarea
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          maxLength={MAX_REASON_LENGTH}
          rows={4}
          autoFocus
          placeholder="State your reason - the claimant will be able to see this."
          className="w-full p-4 border border-slate-200 rounded-xl bg-slate-50 outline-none focus:border-teal text-sm resize-none"
        />
        <div className="text-right text-[10px] text-slate-400 mt-1">
          {reason.length}/{MAX_REASON_LENGTH}
        </div>

        {error && <p className="text-red-500 text-xs font-bold mt-3">{error}</p>}

        <div className="flex justify-end gap-3 mt-6">
          <button
            onClick={onCancel}
            disabled={submitting}
            className="px-6 py-3 rounded-xl border border-slate-200 text-slate-500 font-bold text-sm hover:bg-slate-50 transition disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            onClick={confirm}
            disabled={submitting || tooShort}
            className={`${copy.buttonClass} text-white px-6 py-3 rounded-xl font-bold text-sm transition disabled:opacity-40 disabled:cursor-not-allowed`}
          >
            {submitting ? "Saving…" : copy.button}
          </button>
        </div>
      </div>
    </div>
  );
}
'@

# ---------------------------------------------------------------------------
# UI: Verification Queue (admin / processor)
# ---------------------------------------------------------------------------
Write-ProjectFile "src/app/(portal)/admin/queue/page.tsx" @'
"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useSession } from "next-auth/react";
import { Sidebar } from "@/components/ui/Sidebar";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DecisionModal, DecisionStatus } from "@/components/ui/DecisionModal";
import { getAdminNav } from "@/lib/adminNav";
import { ClaimDTO } from "@/types";

const hasBlocking = (c: ClaimDTO) => !!c.issues?.some((i) => i.severity === "blocking");

export default function VerificationQueuePage() {
  const { data: session } = useSession();
  const [claims, setClaims] = useState<ClaimDTO[]>([]);
  const [loading, setLoading] = useState(true);
  const [pending, setPending] = useState<{ id: string; referenceId: string; status: DecisionStatus } | null>(null);

  async function load() {
    setLoading(true);
    const res = await fetch("/api/claims");
    setClaims(res.ok ? await res.json() : []);
    setLoading(false);
  }

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, []);

  async function submitDecision(reason: string) {
    if (!pending) return;
    const res = await fetch(`/api/claims/${pending.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: pending.status, reason }),
    });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error(typeof body.error === "string" ? body.error : "Update failed.");
    }
    setPending(null);
    load();
  }

  return (
    <div className="bg-navy min-h-screen text-white flex">
      <Sidebar brand="ADMIN CORE" items={getAdminNav(session?.user?.role)} active="Verification Queue" />

      <main className="flex-1 p-16">
        <h1 className="text-5xl font-black mb-2 tracking-tighter">Verification Queue</h1>
        <p className="text-slate-400 uppercase text-[10px] tracking-[0.5em] mb-12">Claim Review &amp; Approval</p>

        <div className="bg-white/5 rounded-[2rem] border border-white/10 overflow-hidden">
          <table className="w-full text-left">
            <thead className="text-[10px] text-slate-400 uppercase tracking-widest">
              <tr>
                <th className="p-6">Submission Date</th>
                <th className="p-6">Claimant</th>
                <th className="p-6">Reference</th>
                <th className="p-6">Status</th>
                <th className="p-6">Flags</th>
                <th className="p-6 text-center">Action</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {claims.map((c) => (
                <tr key={c.id}>
                  <td className="p-6 text-slate-400 text-sm">{new Date(c.createdAt).toLocaleDateString("en-US", { year: "numeric", month: "long", day: "2-digit" })}</td>
                  <td className="p-6 font-bold">{c.user?.name}</td>
                  <td className="p-6 font-mono text-sm"><Link href={`/claims/${c.id}`} className="text-teal-400 hover:underline">{c.referenceId}</Link></td>
                  <td className="p-6"><StatusBadge status={c.status} /></td>
                  <td className="p-6">
                    {c.issues && c.issues.length > 0 ? (
                      <span
                        className={`text-[10px] font-black uppercase px-2 py-1 rounded-full ${
                          hasBlocking(c) ? "bg-red-500/20 text-red-400" : "bg-amber-500/20 text-amber-400"
                        }`}
                        title={c.issues.map((i) => i.message).join("\n")}
                      >
                        {c.issues.length} flag{c.issues.length > 1 ? "s" : ""}
                      </span>
                    ) : (
                      <span className="text-slate-600 text-xs">N/A</span>
                    )}
                  </td>
                  <td className="p-6 text-center space-x-2">
                    {c.status === "PENDING" && (
                      <>
                        <button onClick={() => setPending({ id: c.id, referenceId: c.referenceId, status: "VERIFIED" })} className="bg-teal-500/20 text-teal-400 px-4 py-1.5 rounded-full text-xs font-black uppercase hover:bg-teal-500/30 transition">Verify</button>
                        <button onClick={() => setPending({ id: c.id, referenceId: c.referenceId, status: "REJECTED" })} className="bg-red-500/20 text-red-400 px-4 py-1.5 rounded-full text-xs font-black uppercase hover:bg-red-500/30 transition">Reject</button>
                      </>
                    )}
                    {c.status === "VERIFIED" && (
                      <>
                        <button
                          onClick={() => setPending({ id: c.id, referenceId: c.referenceId, status: "APPROVED" })}
                          disabled={hasBlocking(c)}
                          title={hasBlocking(c) ? "Resolve the red flags on this claim before approving." : undefined}
                          className="bg-teal-500/20 text-teal-400 px-4 py-1.5 rounded-full text-xs font-black uppercase hover:bg-teal-500/30 transition disabled:opacity-40 disabled:cursor-not-allowed"
                        >
                          Approve
                        </button>
                        <button onClick={() => setPending({ id: c.id, referenceId: c.referenceId, status: "REJECTED" })} className="bg-red-500/20 text-red-400 px-4 py-1.5 rounded-full text-xs font-black uppercase hover:bg-red-500/30 transition">Reject</button>
                      </>
                    )}
                    {(c.status === "APPROVED" || c.status === "REJECTED") && (
                      <span className="text-slate-500 text-xs italic">Closed</span>
                    )}
                  </td>
                </tr>
              ))}
              {!loading && claims.length === 0 && (
                <tr><td colSpan={6} className="p-10 text-center text-slate-400 font-bold">Queue is empty.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </main>

      {pending && (
        <DecisionModal
          status={pending.status}
          referenceId={pending.referenceId}
          onCancel={() => setPending(null)}
          onConfirm={submitDecision}
        />
      )}
    </div>
  );
}
'@

# ---------------------------------------------------------------------------
# UI: Claimant claims history (rejected claims link to the reason)
# ---------------------------------------------------------------------------
Write-ProjectFile "src/app/(portal)/claimant/claims/page.tsx" @'
"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { Sidebar } from "@/components/ui/Sidebar";
import { CLAIMANT_NAV } from "@/lib/claimantNav";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { buildLoaHtml } from "@/lib/loaDocument";
import { ClaimDTO } from "@/types";

export default function ClaimsHistoryPage() {
  const [claims, setClaims] = useState<ClaimDTO[]>([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch("/api/claims")
      .then((r) => (r.ok ? r.json() : []))
      .then((data) => setClaims(data))
      .finally(() => setLoading(false));
  }, []);

  async function viewLoa(claimId: string) {
    // Open the window synchronously, in direct response to the click, before
    // any await — otherwise browsers treat the later window.open() as a
    // non-user-initiated popup and silently block it. Also: pass NO features
    // string here — even "noopener" as the 3rd arg makes Chrome/Firefox treat
    // this as a popup-style window request instead of a plain tab, which
    // triggers much stricter blocking. Sever window.opener via the property
    // instead, right after opening, for the same protection without that cost.
    const w = window.open("", "_blank");
    if (w) {
      w.opener = null;
      w.document.write("<p style='font-family:sans-serif;padding:40px;color:#64748b;'>Generating your Letter of Authorization…</p>");
    }

    const res = await fetch(`/api/claims/${claimId}/loa`, { method: "POST" });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      w?.close();
      alert(body.error ?? "Unable to generate LOA.");
      return;
    }
    const loa = await res.json();
    if (!w) {
      alert("Your browser blocked the popup. Please allow popups for this site and try again.");
      return;
    }
    w.document.open();
    w.document.write(buildLoaHtml(loa.content, loa.qrCodeDataUrl, loa.payoutUrl, loa.providerLabel));
    w.document.close();
  }

  const filtered = claims.filter((c) => `${c.referenceId} ${c.category} ${c.status}`.toUpperCase().includes(search.toUpperCase()));

  return (
    <div className="flex bg-slate-50 min-h-screen">
      <Sidebar brand="CLAIMS PRO" items={CLAIMANT_NAV} active="My Claims" dark={false} />

      <main className="flex-1 p-12">
        <header className="flex justify-between items-end mb-12">
          <div>
            <Link href="/claimant" className="text-teal text-xs font-black uppercase tracking-widest hover:underline block mb-2">
              <i className="fa-solid fa-arrow-left mr-2" /> Return to Portal
            </Link>
            <h1 className="text-5xl font-black text-navy tracking-tighter">Claims History</h1>
          </div>
          <div className="relative w-80">
            <i className="fa-solid fa-search absolute left-4 top-4 text-slate-300" />
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search Reference ID..."
              className="w-full pl-12 pr-4 py-4 rounded-2xl border-none shadow-sm focus:ring-2 focus:ring-teal outline-none"
            />
          </div>
        </header>

        <div className="bg-white rounded-[2rem] shadow-sm border border-slate-100 overflow-hidden">
          <table className="w-full text-left">
            <thead className="bg-slate-50/50">
              <tr className="text-[10px] font-black text-slate-400 uppercase tracking-widest">
                <th className="p-8 border-b">Record Identifier</th>
                <th className="p-8 border-b">Classification</th>
                <th className="p-8 border-b">Date Logs</th>
                <th className="p-8 border-b">Lifecycle Status</th>
                <th className="p-8 border-b text-center">Outcome</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-50">
              {filtered.map((claim) => (
                <tr key={claim.id} className="hover:bg-slate-50 transition">
                  <td className="p-8 font-mono text-sm font-bold text-slate-600">
                    <Link href={`/claims/${claim.id}`} className="hover:text-teal hover:underline">{claim.referenceId}</Link>
                  </td>
                  <td className="p-8 text-slate-800 font-medium">{formatCategory(claim.category)}</td>
                  <td className="p-8 text-sm text-slate-400">{new Date(claim.createdAt).toLocaleDateString("en-US", { year: "numeric", month: "long", day: "2-digit" })}</td>
                  <td className="p-8"><StatusBadge status={claim.status} /></td>
                  <td className="p-8 text-center">
                    {claim.status === "APPROVED" ? (
                      <button onClick={() => viewLoa(claim.id)} className="text-teal-600 font-bold text-xs underline decoration-teal-200">
                        View LOA
                      </button>
                    ) : claim.status === "REJECTED" ? (
                      <Link href={`/claims/${claim.id}`} className="text-red-400 font-bold text-xs underline decoration-red-200">
                        Not approved - view reason
                      </Link>
                    ) : (
                      <span className="text-slate-300 font-bold text-xs italic">Awaiting...</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          {!loading && filtered.length === 0 && (
            <div className="p-20 text-center">
              <i className="fa-solid fa-magnifying-glass text-5xl text-slate-100 mb-4" />
              <p className="text-slate-400 font-bold">No matching records found.</p>
            </div>
          )}
        </div>
      </main>
    </div>
  );
}

function formatCategory(category: string) {
  return { MEDICAL: "Hospitalization Coverage", AUTOMOTIVE: "Accidental Damage", HOMEOWNERS: "Homeowners Protection" }[category] ?? category;
}
'@

# ---------------------------------------------------------------------------
# UI: Claim detail (staff decisions + decision history for everyone)
# ---------------------------------------------------------------------------
Write-ProjectFile "src/app/(portal)/claims/[id]/page.tsx" @'
"use client";
import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { useSession } from "next-auth/react";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DecisionModal, DecisionStatus } from "@/components/ui/DecisionModal";
import { buildLoaHtml } from "@/lib/loaDocument";
import { ClaimDTO } from "@/types";

const CATEGORY_LABEL: Record<string, string> = {
  MEDICAL: "Hospitalization Coverage",
  AUTOMOTIVE: "Accidental Damage",
  HOMEOWNERS: "Homeowners Protection",
};

const DECISION_LABEL: Record<string, { label: string; className: string }> = {
  VERIFIED: { label: "Verified", className: "bg-blue-100 text-blue-700" },
  APPROVED: { label: "Approved", className: "bg-teal-100 text-teal-700" },
  REJECTED: { label: "Rejected", className: "bg-red-100 text-red-600" },
};

const ROLE_LABEL: Record<string, string> = { PROCESSOR: "Processor", ADMIN: "Admin" };

const PROVIDERS: { key: "GCASH" | "MAYA" | "PAYPAL" | "BANK_TRANSFER"; label: string; color: string }[] = [
  { key: "GCASH", label: "GCash", color: "bg-[#007cff]" },
  { key: "MAYA", label: "Maya", color: "bg-[#00c56d]" },
  { key: "PAYPAL", label: "PayPal", color: "bg-[#003087]" },
  { key: "BANK_TRANSFER", label: "Bank Transfer", color: "bg-slate-700" },
];

const PH_BANKS = [
  "BDO Unibank",
  "Bank of the Philippine Islands (BPI)",
  "Metrobank",
  "Landbank",
  "Philippine National Bank (PNB)",
  "Security Bank",
  "UnionBank",
  "RCBC",
  "China Bank",
  "EastWest Bank",
  "Other Bank",
];

const PROVIDER_LABEL: Record<string, string> = {
  GCASH: "GCash",
  MAYA: "Maya",
  PAYPAL: "PayPal",
  BANK_TRANSFER: "Bank Transfer",
};

export default function ClaimDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { data: session } = useSession();
  const [claim, setClaim] = useState<ClaimDTO | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [pendingDecision, setPendingDecision] = useState<DecisionStatus | null>(null);
  const [payoutAmount, setPayoutAmount] = useState("500");
  const [showBankForm, setShowBankForm] = useState(false);
  const [bankChoice, setBankChoice] = useState(PH_BANKS[0]);
  const [otherBankName, setOtherBankName] = useState("");
  const [accountName, setAccountName] = useState("");
  const [accountNumber, setAccountNumber] = useState("");
  const [submittingBank, setSubmittingBank] = useState(false);

  async function load() {
    setLoading(true);
    const res = await fetch(`/api/claims/${id}`);
    if (res.ok) {
      const data = await res.json();
      setClaim(data);
      setPayoutAmount((prev) => (prev === "500" ? data.estimate : prev));
    } else if (res.status === 403) {
      setLoadError("You don't have access to this claim.");
    } else {
      setLoadError("Claim not found.");
    }
    setLoading(false);
  }

  useEffect(() => {
    // Same as above: fetching this claim's data can only happen after mount.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  useEffect(() => {
    // Only claimants have a saved payout preference (set from Settings) —
    // staff viewing someone else's claim have nothing to pre-fill from.
    // This is a convenience pre-fill, not critical, so failures are silent.
    if (session?.user?.role !== "CLIENT") return;
    fetch("/api/settings/payout-preference")
      .then((r) => (r.ok ? r.json() : null))
      .then((pref) => {
        if (pref?.provider === "BANK_TRANSFER" && pref.bankName) {
          const isKnownBank = PH_BANKS.slice(0, -1).includes(pref.bankName);
          setBankChoice(isKnownBank ? pref.bankName : "Other Bank");
          if (!isKnownBank) setOtherBankName(pref.bankName);
          setAccountName(pref.accountName ?? "");
          setAccountNumber(pref.accountNumber ?? "");
        }
      })
      .catch(() => {});
  }, [session?.user?.role]);

  async function handleUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    setError(null);
    const form = new FormData();
    form.append("file", file);
    const res = await fetch(`/api/claims/${id}/documents`, { method: "POST", body: form });
    setUploading(false);
    if (!res.ok) {
      const body = await res.json();
      setError(typeof body.error === "string" ? body.error : "Upload failed.");
      return;
    }
    load();
  }

  // Called by the reason pop-up. Throwing keeps the pop-up open and shows the
  // message inside it (e.g. the server's "unresolved issues" explanation).
  async function submitDecision(reason: string) {
    if (!pendingDecision) return;
    const res = await fetch(`/api/claims/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: pendingDecision, reason }),
    });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error(typeof body.error === "string" ? body.error : "Update failed.");
    }
    setPendingDecision(null);
    load();
  }

  async function claimPayout(provider: "GCASH" | "MAYA" | "PAYPAL" | "BANK_TRANSFER", bankDetails?: { bankName: string; accountName: string; accountNumber: string }) {
    const amount = parseFloat(payoutAmount);
    if (!Number.isFinite(amount) || amount <= 0) {
      setError("Enter a valid payout amount before claiming.");
      return;
    }
    const res = await fetch(`/api/claims/${id}/payments`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ provider, amount, ...bankDetails }),
    });
    if (!res.ok) {
      const body = await res.json();
      setError(body.error ?? "Could not start checkout.");
      return;
    }
    const { redirectUrl } = await res.json();
    // This is a page navigation via the browser's Location API, not a
    // mutation of a captured variable — the rule's static analysis can't
    // distinguish the two.
    // eslint-disable-next-line react-hooks/immutability
    window.location.href = redirectUrl;
  }

  async function submitBankTransfer() {
    const bankName = bankChoice === "Other Bank" ? otherBankName.trim() : bankChoice;
    if (!bankName || !accountName.trim() || !accountNumber.trim()) {
      setError("Please fill in the bank name, account name, and account number.");
      return;
    }
    setSubmittingBank(true);
    setError(null);
    await claimPayout("BANK_TRANSFER", { bankName, accountName: accountName.trim(), accountNumber: accountNumber.trim() });
    setSubmittingBank(false);
  }

  async function viewLoa() {
    // Open the window synchronously, in direct response to the click, before
    // any await — otherwise browsers treat the later window.open() as a
    // non-user-initiated popup and silently block it. Also: pass NO features
    // string here — even "noopener" as the 3rd arg makes Chrome/Firefox treat
    // this as a popup-style window request instead of a plain tab, which
    // triggers much stricter blocking. Sever window.opener via the property
    // instead, right after opening, for the same protection without that cost.
    const w = window.open("", "_blank");
    if (w) {
      w.opener = null;
      w.document.write("<p style='font-family:sans-serif;padding:40px;color:#64748b;'>Generating your Letter of Authorization…</p>");
    }

    const res = await fetch(`/api/claims/${id}/loa`, { method: "POST" });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      w?.close();
      alert(body.error ?? "Unable to generate LOA.");
      return;
    }
    const loa = await res.json();
    if (!w) {
      alert("Your browser blocked the popup. Please allow popups for this site and try again.");
      return;
    }
    w.document.open();
    w.document.write(buildLoaHtml(loa.content, loa.qrCodeDataUrl, loa.payoutUrl, loa.providerLabel));
    w.document.close();
  }

  if (loading && !claim) return <div className="p-12 text-slate-400">Loading claim…</div>;
  if (!claim) return <div className="p-12 text-slate-400">{loadError ?? "Claim not found."}</div>;

  const role = session?.user?.role;
  const isOwner = role === "CLIENT" && claim.user.id === session?.user?.id;
  const isStaff = role === "PROCESSOR" || role === "ADMIN";
  const hasBlockingIssue = !!claim.issues?.some((i) => i.severity === "blocking");

  return (
    <div className="min-h-screen bg-slate-50 p-12">
      <div className="max-w-4xl mx-auto">
        <button onClick={() => router.back()} className="text-teal text-xs font-black uppercase tracking-widest hover:underline mb-6 block">
          <i className="fa-solid fa-arrow-left mr-2" /> Back
        </button>

        <div className="bg-white rounded-[2rem] shadow-sm border border-slate-100 p-10 mb-8">
          <div className="flex justify-between items-start mb-8">
            <div>
              <p className="font-mono text-sm text-slate-400">{claim.referenceId}</p>
              <h1 className="text-3xl font-black text-navy">{CATEGORY_LABEL[claim.category] ?? claim.category}</h1>
              <p className="text-slate-500 mt-1">Filed by {claim.user.name} &middot; {claim.user.email}</p>
            </div>
            <StatusBadge status={claim.status} />
          </div>

          <div className="grid grid-cols-2 gap-6 text-sm mb-8">
            <div>
              <p className="text-[10px] font-black text-slate-400 uppercase mb-1">Estimate</p>
              <p className="font-bold text-navy">PHP {parseFloat(claim.estimate).toLocaleString()}</p>
            </div>
            <div>
              <p className="text-[10px] font-black text-slate-400 uppercase mb-1">Filed On</p>
              <p className="font-bold text-navy">{new Date(claim.createdAt).toLocaleDateString("en-US", { year: "numeric", month: "long", day: "2-digit" })}</p>
            </div>
          </div>

          {claim.issues && claim.issues.length > 0 && (
            <div className="mb-8 space-y-2">
              {claim.issues.map((issue) => (
                <div
                  key={issue.code}
                  className={`flex items-start gap-3 p-4 rounded-xl text-sm ${
                    issue.severity === "blocking" ? "bg-red-50 text-red-700" : "bg-amber-50 text-amber-700"
                  }`}
                >
                  <i className={`fa-solid ${issue.severity === "blocking" ? "fa-circle-exclamation" : "fa-triangle-exclamation"} mt-0.5`} />
                  <span>{issue.message}</span>
                </div>
              ))}
            </div>
          )}

          {isStaff && (
            <div className="flex gap-3 mb-8">
              {claim.status === "PENDING" && (
                <>
                  <button onClick={() => setPendingDecision("VERIFIED")} className="bg-navy text-white px-6 py-2 rounded-lg text-sm font-bold">Verify</button>
                  <button onClick={() => setPendingDecision("REJECTED")} className="bg-red-500 text-white px-6 py-2 rounded-lg text-sm font-bold">Reject</button>
                </>
              )}
              {claim.status === "VERIFIED" && (
                <>
                  <button
                    onClick={() => setPendingDecision("APPROVED")}
                    disabled={hasBlockingIssue}
                    title={hasBlockingIssue ? "Resolve the red flags above before approving." : undefined}
                    className="bg-teal text-white px-6 py-2 rounded-lg text-sm font-bold disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    Approve
                  </button>
                  <button onClick={() => setPendingDecision("REJECTED")} className="bg-red-500 text-white px-6 py-2 rounded-lg text-sm font-bold">Reject</button>
                </>
              )}
            </div>
          )}

          {claim.status === "APPROVED" && (
            <button onClick={viewLoa} className="text-teal-600 font-bold text-sm underline decoration-teal-200 mb-4 block">
              View / Generate Letter of Authorization
            </button>
          )}
        </div>

        {claim.decisions && claim.decisions.length > 0 && (
          <div className="bg-white rounded-[2rem] shadow-sm border border-slate-100 p-10 mb-8">
            <h2 className="text-xl font-bold text-navy mb-6">Decision History</h2>
            <ul className="space-y-5">
              {claim.decisions.map((d) => {
                const meta = DECISION_LABEL[d.status] ?? { label: d.status, className: "bg-slate-100 text-slate-600" };
                return (
                  <li key={d.id} className="border-l-4 border-slate-100 pl-5">
                    <div className="flex items-center gap-3 mb-1">
                      <span className={`text-[10px] font-black uppercase px-3 py-1 rounded-full ${meta.className}`}>{meta.label}</span>
                      <span className="text-xs text-slate-400">
                        {d.decidedByName} ({ROLE_LABEL[d.decidedByRole] ?? d.decidedByRole}) &middot; {new Date(d.createdAt).toLocaleString()}
                      </span>
                    </div>
                    <p className="text-sm text-slate-700 whitespace-pre-wrap">{d.reason}</p>
                  </li>
                );
              })}
            </ul>
          </div>
        )}

        <div className="bg-white rounded-[2rem] shadow-sm border border-slate-100 p-10 mb-8">
          <h2 className="text-xl font-bold text-navy mb-6">Supporting Documents</h2>
          <ul className="space-y-2 mb-6">
            {claim.documents?.map((d) => (
              <li key={d.id} className="flex justify-between text-sm border-b border-slate-50 pb-2">
                <a href={`/api/claims/${id}/documents/${d.id}`} target="_blank" rel="noreferrer" className="text-teal-600 underline">{d.fileName}</a>
                <span className="text-slate-400">{(d.sizeBytes / 1024).toFixed(0)} KB</span>
              </li>
            ))}
            {(!claim.documents || claim.documents.length === 0) && <p className="text-slate-400 text-sm italic">No documents uploaded yet.</p>}
          </ul>

          {isOwner && (
            <label className="border-2 border-dashed border-slate-200 rounded-2xl py-10 flex flex-col items-center justify-center text-slate-400 bg-slate-50 hover:bg-white hover:border-teal cursor-pointer transition-all">
              <i className="fa-solid fa-cloud-arrow-up text-3xl mb-2" />
              <p className="text-sm font-bold">{uploading ? "Uploading…" : "Click to upload a document"}</p>
              <p className="text-xs mt-1 italic">Maximum file size: 10MB (PDF, PNG, JPG)</p>
              <input type="file" accept=".pdf,.png,.jpg,.jpeg" className="hidden" onChange={handleUpload} disabled={uploading} />
            </label>
          )}
        </div>

        {isOwner && claim.status === "APPROVED" && (
          <div className="bg-white rounded-[2rem] shadow-sm border border-slate-100 p-10">
            <h2 className="text-xl font-bold text-navy mb-2">Claim Your Payout</h2>
            <p className="text-slate-500 text-sm mb-6">Your claim was approved for disbursement - choose how you&apos;d like to receive it.</p>

            <div className="mb-6 max-w-xs">
              <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Amount (PHP)</label>
              <input
                type="number"
                value={payoutAmount}
                onChange={(e) => setPayoutAmount(e.target.value)}
                className="w-full p-3 border border-slate-100 rounded-xl bg-slate-50 outline-none focus:border-teal"
              />
            </div>

            <div className="flex gap-4 flex-wrap">
              {PROVIDERS.map((p) => (
                <button
                  key={p.key}
                  onClick={() => (p.key === "BANK_TRANSFER" ? setShowBankForm((v) => !v) : claimPayout(p.key))}
                  className={`${p.color} text-white px-6 py-3 rounded-xl font-bold text-sm hover:opacity-90 transition`}
                >
                  Claim via {p.label}
                </button>
              ))}
            </div>

            {showBankForm && (
              <div className="mt-6 max-w-md bg-slate-50 border border-slate-100 rounded-2xl p-6">
                <p className="text-[10px] font-black text-slate-400 uppercase mb-4">Bank Details</p>
                <div className="space-y-4">
                  <div>
                    <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Bank</label>
                    <select
                      value={bankChoice}
                      onChange={(e) => setBankChoice(e.target.value)}
                      className="w-full p-3 border border-slate-200 rounded-xl bg-white outline-none focus:border-teal"
                    >
                      {PH_BANKS.map((b) => (
                        <option key={b} value={b}>{b}</option>
                      ))}
                    </select>
                  </div>
                  {bankChoice === "Other Bank" && (
                    <div>
                      <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Bank Name</label>
                      <input
                        type="text"
                        value={otherBankName}
                        onChange={(e) => setOtherBankName(e.target.value)}
                        placeholder="Enter your bank's name"
                        className="w-full p-3 border border-slate-200 rounded-xl bg-white outline-none focus:border-teal"
                      />
                    </div>
                  )}
                  <div>
                    <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Account Name</label>
                    <input
                      type="text"
                      value={accountName}
                      onChange={(e) => setAccountName(e.target.value)}
                      placeholder="Full name on the account"
                      className="w-full p-3 border border-slate-200 rounded-xl bg-white outline-none focus:border-teal"
                    />
                  </div>
                  <div>
                    <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Account Number</label>
                    <input
                      type="text"
                      value={accountNumber}
                      onChange={(e) => setAccountNumber(e.target.value)}
                      placeholder="Bank account number"
                      className="w-full p-3 border border-slate-200 rounded-xl bg-white outline-none focus:border-teal"
                    />
                  </div>
                  <button
                    onClick={submitBankTransfer}
                    disabled={submittingBank}
                    className="w-full bg-navy text-white py-3 rounded-xl font-bold text-sm hover:bg-teal transition disabled:opacity-50"
                  >
                    {submittingBank ? "Submitting…" : "Submit Bank Transfer Request"}
                  </button>
                  <p className="text-slate-400 text-xs italic">Payouts by bank transfer are verified manually by our team and may take 1–3 business days.</p>
                </div>
              </div>
            )}

            {claim.payments && claim.payments.length > 0 && (
              <div className="mt-8">
                <h3 className="text-[10px] font-black text-slate-400 uppercase mb-3">Payout History</h3>
                <ul className="space-y-2">
                  {claim.payments.map((p) => (
                    <li key={p.id} className="flex justify-between text-sm border-b border-slate-50 pb-2">
                      <span>
                        {PROVIDER_LABEL[p.provider] ?? p.provider} &middot; PHP {parseFloat(p.amount).toLocaleString()}
                        {p.provider === "BANK_TRANSFER" && p.bankName && (
                          <span className="text-slate-400"> ({p.bankName} - {p.accountNumber})</span>
                        )}
                      </span>
                      <StatusBadge status={p.status} />
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        )}

        {error && <p className="text-red-500 text-sm font-bold text-center mt-6">{error}</p>}
      </div>

      {pendingDecision && (
        <DecisionModal
          status={pendingDecision}
          referenceId={claim.referenceId}
          onCancel={() => setPendingDecision(null)}
          onConfirm={submitDecision}
        />
      )}
    </div>
  );
}
'@

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
Write-ProjectFile "src/services/__tests__/claim.service.test.ts" @'
import { ClaimService, ServiceError } from "@/services/claim.service";
import { ClaimValidationService } from "@/services/claim-validation.service";

function makeClaim(overrides: any = {}) {
  return {
    id: "claim_1",
    referenceId: "CLM-2026-X001",
    category: "HOMEOWNERS",
    estimate: 5000,
    status: "PENDING",
    userId: "user_1",
    processorId: null,
    createdAt: new Date(),
    updatedAt: new Date(),
    user: { id: "user_1", name: "Jane", email: "jane@example.com" },
    documents: [{ mimeType: "image/jpeg", sizeBytes: 1024, fileUrl: "x" }],
    loa: null,
    payments: [],
    ...overrides,
  };
}

function makeMocks(claim: any) {
  const claimRepo = {
    findById: jest.fn().mockResolvedValue(claim),
    updateStatus: jest.fn().mockImplementation((id, status, processorId) =>
      Promise.resolve({ ...claim, status, processorId })
    ),
    findMany: jest.fn(),
    create: jest.fn(),
    count: jest.fn(),
    countByStatus: jest.fn(),
    countByCategory: jest.fn(),
    countByUserAndStatus: jest.fn(),
    countByProcessorAndStatus: jest.fn(),
  };
  const notifications = { notifyStatusChange: jest.fn().mockResolvedValue(undefined) } as any;
  const audit = { log: jest.fn().mockResolvedValue(undefined) } as any;
  const decisions = { create: jest.fn().mockResolvedValue({}), listForClaim: jest.fn().mockResolvedValue([]) } as any;
  return { claimRepo, notifications, audit, decisions };
}

function build(claim: any) {
  const m = makeMocks(claim);
  const service = new ClaimService(m.claimRepo as any, m.notifications, m.audit, new ClaimValidationService(), m.decisions);
  return { service, ...m };
}

const REASON = "Documents reviewed and match the claim details.";

describe("ClaimService.transitionStatus", () => {
  it("allows PENDING -> VERIFIED", async () => {
    const { service, claimRepo } = build(makeClaim({ status: "PENDING" }));

    const result = await service.transitionStatus("claim_1", "VERIFIED", "staff_1", REASON);
    expect(result.status).toBe("VERIFIED");
    expect(claimRepo.updateStatus).toHaveBeenCalledWith("claim_1", "VERIFIED", "staff_1");
  });

  it("requires a reason - a missing or too-short reason is rejected before anything changes", async () => {
    const { service, claimRepo, decisions } = build(makeClaim({ status: "PENDING" }));

    await expect(service.transitionStatus("claim_1", "VERIFIED", "staff_1", "")).rejects.toMatchObject({ statusCode: 400 });
    await expect(service.transitionStatus("claim_1", "VERIFIED", "staff_1", "   ")).rejects.toMatchObject({ statusCode: 400 });
    await expect(service.transitionStatus("claim_1", "VERIFIED", "staff_1", "ok")).rejects.toMatchObject({ statusCode: 400 });
    expect(claimRepo.updateStatus).not.toHaveBeenCalled();
    expect(decisions.create).not.toHaveBeenCalled();
  });

  it("rejects an over-long reason", async () => {
    const { service, claimRepo } = build(makeClaim({ status: "PENDING" }));

    await expect(service.transitionStatus("claim_1", "REJECTED", "staff_1", "x".repeat(501))).rejects.toMatchObject({ statusCode: 400 });
    expect(claimRepo.updateStatus).not.toHaveBeenCalled();
  });

  it("records the decision with the trimmed reason and who made it", async () => {
    const { service, decisions } = build(makeClaim({ status: "PENDING" }));

    await service.transitionStatus("claim_1", "REJECTED", "staff_1", "  Photos do not match the report.  ", { name: "Staff", role: "PROCESSOR" });
    expect(decisions.create).toHaveBeenCalledWith(
      expect.objectContaining({
        claimId: "claim_1",
        status: "REJECTED",
        reason: "Photos do not match the report.",
        decidedById: "staff_1",
        decidedByName: "Staff",
        decidedByRole: "PROCESSOR",
      })
    );
  });

  it("passes the reason to the claimant's notification and the audit log", async () => {
    const { service, notifications, audit } = build(makeClaim({ status: "PENDING" }));

    await service.transitionStatus("claim_1", "REJECTED", "staff_1", "Policy had lapsed.", { name: "Staff", role: "PROCESSOR" });
    expect(notifications.notifyStatusChange).toHaveBeenCalledWith("user_1", "CLM-2026-X001", "REJECTED", "claim_1", "Policy had lapsed.");
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ detail: expect.stringContaining("Policy had lapsed.") }));
  });

  it("rejects an invalid transition (PENDING -> APPROVED, skipping VERIFIED)", async () => {
    const { service, claimRepo } = build(makeClaim({ status: "PENDING" }));

    await expect(service.transitionStatus("claim_1", "APPROVED", "staff_1", REASON)).rejects.toThrow(ServiceError);
    expect(claimRepo.updateStatus).not.toHaveBeenCalled();
  });

  it("blocks VERIFIED -> APPROVED when the claim has no documents", async () => {
    const { service, claimRepo } = build(makeClaim({ status: "VERIFIED", processorId: "staff_1", documents: [] }));

    await expect(service.transitionStatus("claim_1", "APPROVED", "staff_1", REASON)).rejects.toThrow(/unresolved issues/i);
    expect(claimRepo.updateStatus).not.toHaveBeenCalled();
  });

  it("allows VERIFIED -> APPROVED when the claim is complete", async () => {
    const { service, audit } = build(makeClaim({ status: "VERIFIED", processorId: "staff_1" }));

    const result = await service.transitionStatus("claim_1", "APPROVED", "staff_1", REASON, { name: "Staff", role: "PROCESSOR" });
    expect(result.status).toBe("APPROVED");
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: "CLAIM_STATUS_CHANGED" }));
  });

  it("still updates status even if the notification write fails", async () => {
    const { service, notifications } = build(makeClaim({ status: "PENDING" }));
    notifications.notifyStatusChange.mockRejectedValue(new Error("db down"));

    const result = await service.transitionStatus("claim_1", "VERIFIED", "staff_1", REASON);
    expect(result.status).toBe("VERIFIED");
  });

  it("still updates status even if recording the decision fails", async () => {
    const { service, decisions } = build(makeClaim({ status: "PENDING" }));
    decisions.create.mockRejectedValue(new Error("db down"));

    const result = await service.transitionStatus("claim_1", "VERIFIED", "staff_1", REASON);
    expect(result.status).toBe("VERIFIED");
  });

  it("throws 404 for a claim that doesn't exist", async () => {
    const { service, claimRepo } = build(null);
    claimRepo.findById.mockResolvedValue(null);

    await expect(service.transitionStatus("nope", "VERIFIED", "staff_1", REASON)).rejects.toMatchObject({ statusCode: 404 });
  });
});

describe("ClaimService.createClaim", () => {
  it("rejects a non-positive estimate", async () => {
    const { service } = build(null);

    await expect(service.createClaim("user_1", { category: "HOMEOWNERS" as any, estimate: 0 })).rejects.toThrow(ServiceError);
    await expect(service.createClaim("user_1", { category: "HOMEOWNERS" as any, estimate: NaN })).rejects.toThrow(ServiceError);
  });
});
'@

Write-Output ""
Write-Output "Done. Next steps:"
Write-Output "  1. npx prisma migrate dev --name add_claim_decisions"
Write-Output "     (on Vercel/production: npx prisma migrate deploy)"
Write-Output "  2. npx tsc --noEmit -p tsconfig.json"
Write-Output "  3. npm test"
Write-Output "  4. npm run build"
