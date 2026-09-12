# ClaimsPro bulk update script (PowerShell)
# Run this from the ROOT of your ClaimsPro repo (same folder as package.json)
# in a PowerShell terminal. Works in both Windows PowerShell 5.1 and PowerShell 7+.
#
# Writes files via .NET's File.WriteAllText with an explicit no-BOM UTF8
# encoding (Windows PowerShell 5.1's Set-Content -Encoding utf8 silently adds a
# byte-order-mark, which breaks strict JSON parsers like Prisma's config loader).
#
# Uses -Path (not -LiteralPath, which New-Item doesn't support) for directory
# creation, and -LiteralPath for Test-Path/Remove-Item, since several paths here
# contain literal square brackets (Next.js's [id]/[docId] dynamic route folders)
# that PowerShell would otherwise misinterpret as a wildcard character class.
#
# Also removes the old standalone /processor page, which was merged into /admin.

$ErrorActionPreference = "Stop"
Write-Output "Updating ClaimsPro files..."
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

if (Test-Path -LiteralPath "src/app/(portal)/processor/page.tsx") { Remove-Item -LiteralPath "src/app/(portal)/processor/page.tsx" -Force }
Write-Output "  removed src/app/(portal)/processor/page.tsx (merged into /admin)"

$path = ".gitignore"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
node_modules
.next
.env
.env*.local
*.log
.vercel
/prisma/dev.db
*.tsbuildinfo
coverage
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote .gitignore"

$path = "middleware.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { withAuth } from "next-auth/middleware";
import { NextResponse } from "next/server";

// Route-level guard: redirects unauthenticated users to /login and blocks
// users from areas that don't match their role.
//
// /admin and /admin/queue are the single shared dashboard for both ADMIN and
// PROCESSOR — one login, one URL space, one visual shell, not two separate
// portals. Account provisioning (/admin/users), the security audit trail
// (/admin/security-logs), and internal API docs (/admin/api-endpoints)
// stay ADMIN-only, since those are administrative concerns rather than
// day-to-day claims work.
export default withAuth(
  function middleware(req) {
    const { pathname } = req.nextUrl;
    const role = req.nextauth.token?.role;

    const isAdminOnlySubpage =
      pathname.startsWith("/admin/users") ||
      pathname.startsWith("/admin/security-logs") ||
      pathname.startsWith("/admin/api-endpoints");

    const isSharedDashboard =
      pathname === "/admin" ||
      pathname.startsWith("/admin/queue");

    const isClaimant = pathname.startsWith("/claimant");

    const hasAccess =
      (isAdminOnlySubpage && role === "ADMIN") ||
      (isSharedDashboard && (role === "ADMIN" || role === "PROCESSOR")) ||
      (isClaimant && role === "CLIENT") ||
      (!isAdminOnlySubpage && !isSharedDashboard && !isClaimant); // /claims/[id] etc. — handled by page-level checks

    if (!hasAccess) {
      // Already authenticated, just somewhere they can't go — send them to
      // the dashboard their role actually owns instead of bouncing to
      // /login (which, for an already-logged-in user, previously looked
      // like a silent loop).
      const ownPortal: Record<string, string> = { CLIENT: "/claimant", PROCESSOR: "/admin", ADMIN: "/admin" };
      const destination = ownPortal[role as string] ?? "/login";
      return NextResponse.redirect(new URL(destination, req.url));
    }
    return NextResponse.next();
  },
  { callbacks: { authorized: ({ token }) => !!token } }
);

export const config = {
  matcher: ["/admin/:path*", "/claimant/:path*", "/claims/:path*"],
};
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote middleware.ts"

$path = "next.config.mjs"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
/** @type {import('next').NextConfig} */

// Font Awesome (layout.tsx) is the only cross-origin resource this app
// loads in the browser — everything else (images, uploaded documents) is
// proxied through our own /api routes, so 'self' covers it.
// Next.js's dev server needs 'unsafe-eval' (React Fast Refresh) and a
// websocket connection (HMR) that production doesn't — kept dev-only so
// the shipped policy is as strict as it can be without breaking local dev.
const isDev = process.env.NODE_ENV !== "production";
const csp = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ""}`,
  "style-src 'self' 'unsafe-inline' https://cdnjs.cloudflare.com",
  "font-src 'self' https://cdnjs.cloudflare.com data:",
  "img-src 'self' data: https://images.unsplash.com",
  `connect-src 'self'${isDev ? " ws://localhost:* http://localhost:*" : ""}`,
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "object-src 'none'",
].join("; ");

const nextConfig = {
  images: {
    remotePatterns: [{ protocol: "https", hostname: "images.unsplash.com" }],
  },
  // Baseline hardening headers. Not a substitute for a real security review,
  // but these close off a few common, cheap-to-fix issues: clickjacking via
  // iframe embedding, MIME-sniffing, and leaking the full referrer URL
  // (which can contain claim IDs) to third-party sites linked from the app.
  //
  // ⚠️ The CSP below is untested against a live browser render (this was
  // written without one available) — script-src 'unsafe-inline' is kept in
  // production too because Next.js's App Router injects inline hydration
  // <script> tags; removing it would need a nonce-based setup wired through
  // middleware, which is a bigger change worth testing locally first. Load
  // the app after deploying this and check the browser console for any CSP
  // violation warnings before relying on it.
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Frame-Options", value: "DENY" },
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
          { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains" },
          { key: "Content-Security-Policy", value: csp },
        ],
      },
    ];
  },
};
export default nextConfig;
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote next.config.mjs"

$path = "package.json"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
{
  "name": "claimspro",
  "version": "1.0.0",
  "private": true,
  "engines": {
    "node": ">=20.9.0"
  },
  "prisma": {
    "seed": "tsx prisma/seed.ts"
  },
  "scripts": {
    "dev": "next dev",
    "build": "prisma generate && next build",
    "start": "next start",
    "lint": "eslint src",
    "test": "jest",
    "test:watch": "jest --watch",
    "prisma:generate": "prisma generate",
    "prisma:migrate": "prisma migrate dev",
    "prisma:deploy": "prisma migrate deploy",
    "prisma:seed": "tsx prisma/seed.ts",
    "prisma:studio": "prisma studio"
  },
  "dependencies": {
    "@prisma/client": "5.18.0",
    "@vercel/blob": "^2.6.1",
    "bcryptjs": "2.4.3",
    "next": "^16.3.4",
    "next-auth": "^4.24.15",
    "qrcode": "1.5.3",
    "react": "^19.2.8",
    "react-dom": "^19.2.8",
    "zod": "3.23.8"
  },
  "devDependencies": {
    "@types/bcryptjs": "2.4.6",
    "@types/jest": "^29.5.14",
    "@types/node": "20.14.15",
    "@types/qrcode": "1.5.5",
    "@types/react": "^19.2.18",
    "@types/react-dom": "^19.2.7",
    "autoprefixer": "10.4.19",
    "eslint": "^9.39.5",
    "eslint-config-next": "^16.3.4",
    "jest": "^29.7.0",
    "postcss": "^8.5.28",
    "prisma": "5.18.0",
    "tailwindcss": "3.4.7",
    "ts-jest": "^29.4.12",
    "tsx": "^4.23.13",
    "typescript": "5.5.4"
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote package.json"

$path = "prisma/schema.prisma"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
// ClaimsPro data model — cloud PostgreSQL (Neon / Supabase) via Prisma ORM

datasource db {
  provider  = "postgresql"
  url       = env("DATABASE_URL")
  directUrl = env("DIRECT_URL")
}

generator client {
  provider = "prisma-client-js"
}

enum Role {
  CLIENT
  PROCESSOR
  ADMIN
}

enum PolicyCategory {
  MEDICAL
  AUTOMOTIVE
  HOMEOWNERS
}

enum ClaimStatus {
  PENDING
  VERIFIED
  APPROVED
  REJECTED
}

model User {
  id            String   @id @default(cuid())
  name          String
  email         String   @unique
  passwordHash  String
  role          Role     @default(CLIENT)
  createdAt     DateTime @default(now())

  claims        Claim[]        @relation("ClaimOwner")
  processed     Claim[]        @relation("ClaimProcessor")
  loasGenerated Loa[]          @relation("LoaGeneratedBy")
  notifications Notification[]
  chatMessages  ChatMessage[]
  payoutPreference PayoutPreference?

  @@map("users")
}

model Claim {
  id          String         @id @default(cuid())
  referenceId String         @unique
  category    PolicyCategory
  estimate    Decimal        @db.Decimal(12, 2)
  status      ClaimStatus    @default(PENDING)

  userId      String
  user        User           @relation("ClaimOwner", fields: [userId], references: [id])

  processorId String?
  processor   User?          @relation("ClaimProcessor", fields: [processorId], references: [id])

  documents   Document[]
  loa         Loa?
  payments    Payment[]

  createdAt   DateTime       @default(now())
  updatedAt   DateTime       @updatedAt

  @@map("claims")
}

model Document {
  id         String   @id @default(cuid())
  claimId    String
  claim      Claim    @relation(fields: [claimId], references: [id], onDelete: Cascade)
  fileName   String
  fileUrl    String
  mimeType   String
  sizeBytes  Int
  uploadedAt DateTime @default(now())

  @@map("documents")
}

model Loa {
  id          String   @id @default(cuid())
  claimId     String   @unique
  claim       Claim    @relation(fields: [claimId], references: [id], onDelete: Cascade)
  content     String   @db.Text
  // Locked in at generation time — the letter's printed text names this
  // provider, so every later QR/checkout regeneration for this claim must
  // keep using it too, even if the claimant's Settings preference changes
  // afterward. Without this, the letter could say "via GCash" while the QR
  // silently started pointing somewhere else.
  provider    PaymentProvider @default(GCASH)
  generatedAt DateTime @default(now())

  generatedById String
  generatedBy   User   @relation("LoaGeneratedBy", fields: [generatedById], references: [id])

  @@map("letters_of_authorization")
}

enum NotificationType {
  STATUS_UPDATE
  RENEWAL
  PAYMENT
}

model Notification {
  id        String           @id @default(cuid())
  userId    String
  user      User             @relation(fields: [userId], references: [id], onDelete: Cascade)
  type      NotificationType
  message   String
  read      Boolean          @default(false)
  claimId   String?
  createdAt DateTime         @default(now())

  @@index([userId, read])
  @@map("notifications")
}

enum PaymentProvider {
  GCASH
  MAYA
  PAYPAL
  BANK_TRANSFER
}

enum PaymentStatus {
  PENDING
  PAID
  FAILED
}

model Payment {
  id          String          @id @default(cuid())
  claimId     String
  claim       Claim           @relation(fields: [claimId], references: [id], onDelete: Cascade)
  provider    PaymentProvider
  amount      Decimal         @db.Decimal(12, 2)
  status      PaymentStatus   @default(PENDING)
  providerRef String?

  // Only populated when provider = BANK_TRANSFER. Bank transfers aren't
  // processed through a gateway like GCash/Maya are — staff verify the
  // deposit manually against these details, so there's no redirect checkout.
  bankName      String?
  accountName   String?
  accountNumber String?

  createdAt   DateTime        @default(now())
  updatedAt   DateTime        @updatedAt

  @@map("payments")
}

model ChatMessage {
  id        String   @id @default(cuid())
  userId    String
  user      User     @relation(fields: [userId], references: [id], onDelete: Cascade)
  role      String   // "user" | "assistant"
  content   String   @db.Text
  createdAt DateTime @default(now())

  @@index([userId, createdAt])
  @@map("chat_messages")
}

model AuditLog {
  id        String   @id @default(cuid())
  actorId   String?
  actorName String
  actorRole String
  action    String
  detail    String?
  createdAt DateTime @default(now())

  @@index([createdAt])
  @@map("audit_logs")
}

// A claimant's saved default payout method — set once from the claimant
// Settings page, so they don't have to re-enter bank/provider details on
// every single claim. Purely a convenience default: the claim payout flow
// itself still lets them pick a different provider per claim if they want.
model PayoutPreference {
  id            String          @id @default(cuid())
  userId        String          @unique
  user          User            @relation(fields: [userId], references: [id], onDelete: Cascade)
  provider      PaymentProvider
  bankName      String?
  accountName   String?
  accountNumber String?
  updatedAt     DateTime        @updatedAt

  @@map("payout_preferences")
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote prisma/schema.prisma"

$path = "src/app/(portal)/admin/page.tsx"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
"use client";
import { useEffect, useState } from "react";
import { useSession } from "next-auth/react";
import { Sidebar } from "@/components/ui/Sidebar";
import { StatCard } from "@/components/ui/StatCard";
import { getAdminNav } from "@/lib/adminNav";
import { SystemStats } from "@/types";

export default function AdminDashboardPage() {
  const { data: session } = useSession();
  const [stats, setStats] = useState<SystemStats | null>(null);

  useEffect(() => {
    fetch("/api/admin/stats")
      .then((r) => (r.ok ? r.json() : null))
      .then(setStats)
      .catch(() => setStats(null));
  }, []);

  const categoryBars = stats
    ? Object.entries(stats.claimsByCategory)
    : [];
  const maxCategoryCount = Math.max(1, ...categoryBars.map(([, v]) => v));

  return (
    <div className="bg-navy min-h-screen text-white flex">
      <Sidebar brand="ADMIN CORE" items={getAdminNav(session?.user?.role)} active="Analytics Engine" />

      <main className="flex-1 p-16">
        <div className="flex justify-between items-start mb-16">
          <div>
            <h1 className="text-5xl font-black mb-2 tracking-tighter">System Health</h1>
            <p className="text-slate-400 uppercase text-[10px] tracking-[0.5em]">Real-Time Operational Monitoring</p>
          </div>
          <div className="bg-white/5 px-6 py-4 rounded-2xl border border-white/10 flex items-center space-x-4">
            <div className="w-3 h-3 bg-green-500 rounded-full animate-pulse" />
            <span className="text-sm font-bold uppercase tracking-widest">Server: Online</span>
          </div>
        </div>

        <div className="grid grid-cols-3 gap-8 mb-16">
          <StatCard label="Total Requests" value={stats ? stats.totalRequests.toLocaleString() : "N/A"} />
          <StatCard label="Approval Rate" value={stats ? `${stats.approvalRate}%` : "N/A"} sub="Of all submitted claims" />
          <StatCard label="LOA Gen Rate" value={stats ? `${stats.loaGenerationRate}%` : "N/A"} sub="Of approved claims" subClass="text-green-500" />
        </div>

        <div className="bg-white/5 p-12 rounded-[3rem] border border-white/10">
          <h3 className="text-2xl font-bold mb-8">Claims by Policy Category</h3>
          <div className="flex items-end space-x-4 h-40">
            {categoryBars.map(([category, count]) => (
              <div key={category} className="flex-1 flex flex-col items-center justify-end h-full">
                <div
                  className="bg-teal-600/20 border-t-4 border-teal-500 w-full hover:bg-teal-600 transition duration-500 rounded-t-xl"
                  style={{ height: `${Math.max(6, (count / maxCategoryCount) * 100)}%` }}
                />
                <span className="text-[10px] mt-2 text-slate-400 uppercase font-black">{category}</span>
              </div>
            ))}
          </div>
        </div>
      </main>
    </div>
  );
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/(portal)/admin/page.tsx"

$path = "src/app/(portal)/admin/users/page.tsx"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
"use client";
import { useEffect, useState } from "react";
import { useSession } from "next-auth/react";
import { Sidebar } from "@/components/ui/Sidebar";
import { getAdminNav } from "@/lib/adminNav";

interface AdminUser {
  id: string;
  name: string;
  email: string;
  role: "CLIENT" | "PROCESSOR" | "ADMIN";
  createdAt: string;
}

export default function IdentityManagerPage() {
  const { data: session } = useSession();
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [form, setForm] = useState({ name: "", email: "", password: "", role: "CLIENT" as AdminUser["role"] });
  const [error, setError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);

  async function load() {
    setLoading(true);
    const res = await fetch("/api/admin/users");
    setUsers(res.ok ? await res.json() : []);
    setLoading(false);
  }

  useEffect(() => {
    // Standard client-side data fetch on mount — this rule targets state
    // that could be computed synchronously during render instead; there's
    // no way to have this data (a server response) at render time, so an
    // effect + setState is the correct, unavoidable pattern here.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, []);

  async function createUser() {
    setError(null);
    setCreating(true);
    const res = await fetch("/api/admin/users", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(form),
    });
    setCreating(false);
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      setError(typeof body.error === "string" ? body.error : "Could not create user.");
      return;
    }
    setForm({ name: "", email: "", password: "", role: "CLIENT" });
    load();
  }

  return (
    <div className="bg-navy min-h-screen text-white flex">
      <Sidebar brand="ADMIN CORE" items={getAdminNav(session?.user?.role)} active="Identity Manager" />

      <main className="flex-1 p-16">
        <h1 className="text-5xl font-black mb-2 tracking-tighter">Identity Manager</h1>
        <p className="text-slate-400 uppercase text-[10px] tracking-[0.5em] mb-12">User Provisioning &amp; Roles</p>

        <div className="bg-white/5 p-8 rounded-[2rem] border border-white/10 mb-10 max-w-3xl">
          <h3 className="text-lg font-bold mb-6">Provision New Account</h3>
          <div className="grid grid-cols-2 gap-4 mb-4">
            <input
              placeholder="Full name"
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
              className="bg-white/5 border border-white/10 rounded-xl px-4 py-3 outline-none focus:border-teal placeholder:text-slate-500"
            />
            <input
              placeholder="Email"
              value={form.email}
              onChange={(e) => setForm({ ...form, email: e.target.value })}
              className="bg-white/5 border border-white/10 rounded-xl px-4 py-3 outline-none focus:border-teal placeholder:text-slate-500"
            />
            <input
              placeholder="Temporary password"
              type="password"
              value={form.password}
              onChange={(e) => setForm({ ...form, password: e.target.value })}
              className="bg-white/5 border border-white/10 rounded-xl px-4 py-3 outline-none focus:border-teal placeholder:text-slate-500"
            />
            <select
              value={form.role}
              onChange={(e) => setForm({ ...form, role: e.target.value as AdminUser["role"] })}
              className="bg-white/5 border border-white/10 rounded-xl px-4 py-3 outline-none focus:border-teal"
            >
              <option value="CLIENT" className="text-black">Claimant</option>
              <option value="PROCESSOR" className="text-black">Processor</option>
              <option value="ADMIN" className="text-black">Admin</option>
            </select>
          </div>
          {error && <p className="text-red-400 text-xs font-bold mb-3">{error}</p>}
          <button
            onClick={createUser}
            disabled={creating}
            className="bg-teal text-white px-6 py-3 rounded-xl font-bold hover:opacity-90 transition disabled:opacity-50"
          >
            {creating ? "Creating…" : "Create Account"}
          </button>
        </div>

        <div className="bg-white/5 rounded-[2rem] border border-white/10 overflow-hidden max-w-3xl">
          <table className="w-full text-left">
            <thead className="text-[10px] text-slate-400 uppercase tracking-widest">
              <tr>
                <th className="p-6">Name</th>
                <th className="p-6">Email</th>
                <th className="p-6">Role</th>
                <th className="p-6">Joined</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {users.map((u) => (
                <tr key={u.id}>
                  <td className="p-6 font-bold">{u.name}</td>
                  <td className="p-6 text-slate-400">{u.email}</td>
                  <td className="p-6"><span className="text-[10px] bg-teal-500/20 text-teal-400 px-3 py-1 rounded-full font-black uppercase">{u.role}</span></td>
                  <td className="p-6 text-slate-400 text-sm">{new Date(u.createdAt).toLocaleDateString()}</td>
                </tr>
              ))}
              {!loading && users.length === 0 && (
                <tr><td colSpan={4} className="p-10 text-center text-slate-400">No users yet.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </main>
    </div>
  );
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/(portal)/admin/users/page.tsx"

$path = "src/app/(portal)/claimant/page.tsx"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
"use client";
import { useState } from "react";
import Link from "next/link";
import { Sidebar } from "@/components/ui/Sidebar";
import { CLAIMANT_NAV } from "@/lib/claimantNav";
import { Toast } from "@/components/ui/Toast";

export default function NewClaimPage() {
  const [category, setCategory] = useState("MEDICAL");
  const [estimate, setEstimate] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [showToast, setShowToast] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  function handleFileSelect(e: React.ChangeEvent<HTMLInputElement>) {
    setFile(e.target.files?.[0] ?? null);
  }

  async function handleSubmit() {
    setError(null);
    setSubmitting(true);
    try {
      const res = await fetch("/api/claims", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ category, estimate: parseFloat(estimate) || 0 }),
      });
      if (!res.ok) {
        const body = await res.json();
        throw new Error(typeof body.error === "string" ? body.error : "Submission failed.");
      }
      const claim = await res.json();

      // Claim exists now — attach the selected evidence file, if any. A failed
      // upload here shouldn't be reported as a failed submission (the claim
      // itself is already saved); surface it as a distinct warning instead.
      if (file) {
        const form = new FormData();
        form.append("file", file);
        const uploadRes = await fetch(`/api/claims/${claim.id}/documents`, { method: "POST", body: form });
        if (!uploadRes.ok) {
          const body = await uploadRes.json();
          setError(
            `Claim ${claim.referenceId} was submitted, but the attached file didn't upload: ${
              typeof body.error === "string" ? body.error : "unknown error"
            }. You can attach it later from the claim's detail page.`
          );
        }
      }

      setShowToast(true);
      setEstimate("");
      setFile(null);
      setTimeout(() => setShowToast(false), 4000);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="flex bg-slate-50 min-h-screen">
      <Sidebar brand="CLAIMS PRO" items={CLAIMANT_NAV} active="Dashboard" dark={false} />

      <main className="flex-1 p-12">
        <header className="mb-12">
          <h1 className="text-4xl font-black text-navy">New Claim Request</h1>
          <p className="text-slate-400 mt-2 italic">Submit a claim for verification</p>
        </header>

        <div className="mb-12 max-w-4xl">
          <div className="flex items-center justify-between relative px-2">
            <div className="absolute top-1/2 left-0 w-full h-0.5 bg-slate-200 -z-10" />
            <Step n={1} label="INTAKE" active />
            <Step n={2} label="VERIFICATION" />
            <Step n={3} label="APPROVAL" />
          </div>
        </div>

        <div className="bg-white p-10 rounded-3xl shadow-sm border border-slate-100 max-w-4xl">
          <div className="grid md:grid-cols-2 gap-8 mb-8">
            <div>
              <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Policy Category</label>
              <select
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                className="w-full p-4 border border-slate-100 rounded-xl bg-slate-50 outline-none focus:border-teal"
              >
                <option value="MEDICAL">Medical Expense Coverage</option>
                <option value="AUTOMOTIVE">Automotive Damage</option>
                <option value="HOMEOWNERS">Homeowners Protection</option>
              </select>
            </div>
            <div>
              <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Claim Estimate (PHP)</label>
              <input
                type="number"
                value={estimate}
                onChange={(e) => setEstimate(e.target.value)}
                placeholder="5,000.00"
                className="w-full p-4 border border-slate-100 rounded-xl bg-slate-50 outline-none focus:border-teal"
              />
            </div>
          </div>

          <div className="mb-10">
            <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">
              Supporting Evidence (Medical Records/Receipts)
            </label>
            <label className="border-2 border-dashed border-slate-200 rounded-2xl py-16 flex flex-col items-center justify-center text-slate-400 bg-slate-50 hover:bg-white hover:border-teal cursor-pointer transition-all">
              <i className="fa-solid fa-cloud-arrow-up text-4xl mb-4" />
              <p className="text-sm font-bold">{file ? file.name : "Click to attach a document"}</p>
              <p className="text-xs mt-1 italic">Maximum file size: 10MB (PDF, PNG, JPG)</p>
              <input type="file" accept=".pdf,.png,.jpg,.jpeg" className="hidden" onChange={handleFileSelect} />
            </label>
          </div>

          {error && <p className="text-red-500 text-xs font-bold text-center mb-4">{error}</p>}

          <button
            onClick={handleSubmit}
            disabled={submitting}
            className="w-full bg-navy text-white py-5 rounded-2xl font-bold hover:bg-teal transition-all shadow-xl shadow-slate-100 disabled:opacity-50"
          >
            {submitting ? "Submitting..." : "Submit for Verification"}
          </button>
          <Link href="/claimant/claims" className="block text-center text-xs text-teal font-bold mt-6 hover:underline">
            View my claims history &rarr;
          </Link>
        </div>
      </main>

      <Toast show={showToast} title="Submission Successful" message="Your claim has been assigned to a processor." />
    </div>
  );
}

function Step({ n, label, active = false }: { n: number; label: string; active?: boolean }) {
  return (
    <div className="flex flex-col items-center">
      <div
        className={`w-10 h-10 rounded-full flex items-center justify-center font-bold ring-4 ring-white ${
          active ? "bg-teal text-white shadow-lg shadow-teal-100" : "bg-white border-2 border-slate-200 text-slate-400"
        }`}
      >
        {n}
      </div>
      <span className={`text-[10px] font-bold mt-2 uppercase ${active ? "text-navy" : "text-slate-400"}`}>{label}</span>
    </div>
  );
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/(portal)/claimant/page.tsx"

$path = "src/app/(portal)/claimant/claims/page.tsx"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
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
                      <span className="text-red-400 font-bold text-xs italic">Not approved</span>
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
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/(portal)/claimant/claims/page.tsx"

$path = "src/app/(portal)/claims/[id]/page.tsx"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
"use client";
import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { useSession } from "next-auth/react";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { buildLoaHtml } from "@/lib/loaDocument";
import { ClaimDTO } from "@/types";

const CATEGORY_LABEL: Record<string, string> = {
  MEDICAL: "Hospitalization Coverage",
  AUTOMOTIVE: "Accidental Damage",
  HOMEOWNERS: "Homeowners Protection",
};

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

  async function transition(status: string) {
    const res = await fetch(`/api/claims/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status }),
    });
    if (!res.ok) {
      const body = await res.json();
      alert(body.error ?? "Update failed.");
      return;
    }
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

  if (loading) return <div className="p-12 text-slate-400">Loading claim…</div>;
  if (!claim) return <div className="p-12 text-slate-400">{loadError ?? "Claim not found."}</div>;

  const role = session?.user?.role;
  const isOwner = role === "CLIENT" && claim.user.id === session?.user?.id;
  const isStaff = role === "PROCESSOR" || role === "ADMIN";

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
                  <button onClick={() => transition("VERIFIED")} className="bg-navy text-white px-6 py-2 rounded-lg text-sm font-bold">Verify</button>
                  <button onClick={() => transition("REJECTED")} className="bg-red-500 text-white px-6 py-2 rounded-lg text-sm font-bold">Reject</button>
                </>
              )}
              {claim.status === "VERIFIED" && (
                <>
                  <button onClick={() => transition("APPROVED")} className="bg-teal text-white px-6 py-2 rounded-lg text-sm font-bold">Approve</button>
                  <button onClick={() => transition("REJECTED")} className="bg-red-500 text-white px-6 py-2 rounded-lg text-sm font-bold">Reject</button>
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
    </div>
  );
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/(portal)/claims/[id]/page.tsx"

$path = "src/app/api/admin/stats/route.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { StatsService } from "@/services/stats.service";

const statsService = new StatsService();

// GET /api/admin/stats — powers the shared Admin/Processor dashboard's "System Health" view
export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session || (session.user.role !== "ADMIN" && session.user.role !== "PROCESSOR")) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  try {
    const stats = await statsService.getSystemStats();
    return NextResponse.json(stats);
  } catch (err) {
    console.error("Failed to load admin stats:", err);
    return NextResponse.json({ error: "Could not load system stats." }, { status: 500 });
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/api/admin/stats/route.ts"

$path = "src/app/api/admin/users/route.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { z } from "zod";
import { authOptions } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { PrismaUserRepository } from "@/repositories/user.repository";
import { hashPassword } from "@/lib/password";
import { AuditService } from "@/services/audit.service";

const userRepo = new PrismaUserRepository();
const auditService = new AuditService();

const createUserSchema = z.object({
  name: z.string().min(1),
  email: z.string().email(),
  password: z.string().min(8),
  role: z.enum(["CLIENT", "PROCESSOR", "ADMIN"]),
});

// GET /api/admin/users — list all users (ADMIN only)
export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session || session.user.role !== "ADMIN") return NextResponse.json({ error: "Forbidden" }, { status: 403 });

  const users = await prisma.user.findMany({
    select: { id: true, name: true, email: true, role: true, createdAt: true },
    orderBy: { createdAt: "desc" },
  });
  return NextResponse.json(users);
}

// POST /api/admin/users — provision a new user account (ADMIN only)
export async function POST(req: NextRequest) {
  const session = await getServerSession(authOptions);
  if (!session || session.user.role !== "ADMIN") return NextResponse.json({ error: "Forbidden" }, { status: 403 });

  const body = await req.json();
  const parsed = createUserSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  try {
    const existing = await userRepo.findByEmail(parsed.data.email);
    if (existing) return NextResponse.json({ error: "A user with that email already exists." }, { status: 409 });

    // Only passwordHash goes to Prisma — the User model has no `password`
    // column, so passing the raw plaintext field through (previously done via
    // `...parsed.data`) caused Prisma to reject the whole insert.
    const { password, ...rest } = parsed.data;
    const passwordHash = await hashPassword(password);
    const user = await userRepo.create({ ...rest, passwordHash });
    await auditService.log({
      actorId: session.user.id,
      actorName: session.user.name ?? session.user.email,
      actorRole: session.user.role,
      action: "USER_PROVISIONED",
      detail: `Created ${user.role} account for ${user.email}`,
    });
    return NextResponse.json({ id: user.id, name: user.name, email: user.email, role: user.role }, { status: 201 });
  } catch (err) {
    console.error("Failed to create user:", err);
    return NextResponse.json({ error: "Could not create the account. Please try again." }, { status: 500 });
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/api/admin/users/route.ts"

$path = "src/app/api/claims/[id]/documents/[docId]/route.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { DocumentService } from "@/services/document.service";
import { ServiceError } from "@/services/claim.service";

const documentService = new DocumentService();

// GET /api/claims/:id/documents/:docId — stream a private document (owner or staff only)
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string; docId: string }> }) {
  const { id, docId } = await params;
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  try {
    const { stream, contentType, fileName } = await documentService.downloadForClaim(
      id,
      docId,
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
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/api/claims/[id]/documents/[docId]/route.ts"

$path = "src/app/api/claims/[id]/documents/route.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { DocumentService } from "@/services/document.service";
import { ServiceError } from "@/services/claim.service";

const documentService = new DocumentService();

// POST /api/claims/:id/documents — upload supporting evidence (multipart/form-data, field "file")
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const form = await req.formData();
  const file = form.get("file");
  if (!(file instanceof File)) return NextResponse.json({ error: "No file provided." }, { status: 400 });

  try {
    const doc = await documentService.uploadForClaim(id, session.user.id, file);
    return NextResponse.json(doc, { status: 201 });
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}

// GET /api/claims/:id/documents — list evidence for a claim
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const docs = await documentService.listForClaim(id);
  return NextResponse.json(docs);
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/api/claims/[id]/documents/route.ts"

$path = "src/app/api/claims/[id]/loa/route.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { LoaService } from "@/services/loa.service";
import { ClaimService, ServiceError } from "@/services/claim.service";
import { PaymentService } from "@/services/payment.service";
import { PayoutPreferenceService } from "@/services/payout-preference.service";
import { generateQrDataUrl } from "@/lib/qrcode";

const loaService = new LoaService();
const claimService = new ClaimService();
const paymentService = new PaymentService();
const payoutPreferenceService = new PayoutPreferenceService();

const PROVIDER_LABEL: Record<string, string> = {
  GCASH: "GCash",
  MAYA: "Maya",
  PAYPAL: "PayPal",
  BANK_TRANSFER: "Bank Transfer",
};

// POST /api/claims/:id/loa — generate (or fetch, if already generated) the
// Letter of Authorization for an approved claim, plus a QR code that takes
// the claimant straight into a checkout for whichever provider they've set
// as their default in Settings (GCash if they haven't set one) — not to a
// page inside the app, since that requires a session and a phone scanning
// the printed/emailed LOA usually won't have one. Staff can act on any
// claim; a claimant can only act on their own claim.
export async function POST(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const claim = await claimService.getClaim(id);
  if (!claim) return NextResponse.json({ error: "Claim not found." }, { status: 404 });
  if (session.user.role === "CLIENT" && claim.userId !== session.user.id) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  try {
    const loa = await loaService.generateForClaim(id, session.user.id);

    // The LOA's own `provider` field is authoritative — it's what the
    // letter's printed text actually names, locked in at first generation.
    // Bank details, if needed, come from the claimant's *current* saved
    // preference: if a pending bank-transfer payment already exists for
    // this claim it's simply reused (see getOrCreateCheckoutForClaim), so
    // this only matters the first time a bank-transfer checkout is created.
    let bankDetails: { bankName: string; accountName: string; accountNumber: string } | undefined;
    if (loa.provider === "BANK_TRANSFER") {
      const preference = await payoutPreferenceService.get(claim.userId);
      if (preference?.bankName && preference.accountName && preference.accountNumber) {
        bankDetails = { bankName: preference.bankName, accountName: preference.accountName, accountNumber: preference.accountNumber };
      }
    }

    const { redirectUrl: payoutUrl } = await paymentService.getOrCreateCheckoutForClaim(
      id,
      loa.provider as any,
      Number(claim.estimate),
      bankDetails
    );
    const qrCodeDataUrl = await generateQrDataUrl(payoutUrl);

    return NextResponse.json({ ...loa, qrCodeDataUrl, payoutUrl, providerLabel: PROVIDER_LABEL[loa.provider] ?? loa.provider }, { status: 201 });
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/api/claims/[id]/loa/route.ts"

$path = "src/app/api/claims/[id]/payments/route.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { z } from "zod";
import { authOptions } from "@/lib/auth";
import { PaymentService } from "@/services/payment.service";
import { ServiceError } from "@/services/claim.service";

const paymentService = new PaymentService();

const checkoutSchema = z.object({
  provider: z.enum(["GCASH", "MAYA", "PAYPAL", "BANK_TRANSFER"]),
  amount: z.number().positive(),
  bankName: z.string().min(1).optional(),
  accountName: z.string().min(1).optional(),
  accountNumber: z.string().min(1).optional(),
});

// POST /api/claims/:id/payments — start a checkout for an approved claim's fee
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const body = await req.json();
  const parsed = checkoutSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const { provider, amount, bankName, accountName, accountNumber } = parsed.data;

  try {
    const result = await paymentService.startCheckout(
      id,
      provider,
      amount,
      provider === "BANK_TRANSFER" && bankName && accountName && accountNumber
        ? { bankName, accountName, accountNumber }
        : undefined,
      { id: session.user.id, name: session.user.name ?? session.user.email, role: session.user.role }
    );
    return NextResponse.json(result, { status: 201 });
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/api/claims/[id]/payments/route.ts"

$path = "src/app/api/claims/[id]/route.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { z } from "zod";
import { authOptions } from "@/lib/auth";
import { ClaimService, ServiceError } from "@/services/claim.service";

const claimService = new ClaimService();

const updateStatusSchema = z.object({
  status: z.enum(["VERIFIED", "APPROVED", "REJECTED"]),
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
  return NextResponse.json({ ...claim, issues });
}

// PATCH /api/claims/:id — advance claim status (PROCESSOR / ADMIN only)
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (session.user.role === "CLIENT") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const body = await req.json();
  const parsed = updateStatusSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  try {
    const claim = await claimService.transitionStatus(id, parsed.data.status, session.user.id, {
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
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/api/claims/[id]/route.ts"

$path = "src/app/api/claims/route.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { z } from "zod";
import { authOptions } from "@/lib/auth";
import { ClaimService, ServiceError } from "@/services/claim.service";

const claimService = new ClaimService();

const createClaimSchema = z.object({
  category: z.enum(["MEDICAL", "AUTOMOTIVE", "HOMEOWNERS"]),
  estimate: z.number().positive(),
});

// GET /api/claims — list claims (own claims for CLIENT, full queue for staff)
export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const claims = await claimService.listClaimsFor(session.user);
  const withIssues = claims.map((c) => ({ ...c, issues: claimService.getValidationIssues(c) }));
  return NextResponse.json(withIssues);
}

// POST /api/claims — submit a new claim (CLIENT only)
export async function POST(req: NextRequest) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (session.user.role !== "CLIENT") {
    return NextResponse.json({ error: "Only claimants can submit claims." }, { status: 403 });
  }

  const body = await req.json();
  const parsed = createClaimSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  try {
    const claim = await claimService.createClaim(session.user.id, parsed.data);
    return NextResponse.json(claim, { status: 201 });
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/api/claims/route.ts"

$path = "src/app/api/notifications/[id]/route.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { NotificationService } from "@/services/notification.service";

const notificationService = new NotificationService();

// PATCH /api/notifications/:id — mark as read
export async function PATCH(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  try {
    await notificationService.markRead(id, session.user.id);
    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error("Failed to mark notification read:", err);
    return NextResponse.json({ error: "Could not update notification." }, { status: 500 });
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/api/notifications/[id]/route.ts"

$path = "src/app/api/payments/[id]/confirm/route.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { PaymentService } from "@/services/payment.service";
import { ServiceError } from "@/services/claim.service";

const paymentService = new PaymentService();

// POST /api/payments/:id/confirm — used by the mock checkout page in dev/demo
// mode. In production this responsibility moves to a signed webhook from the
// real gateway (PayMongo/PayPal) instead of a client-callable route.
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const { success } = await req.json();

  try {
    const payment = await paymentService.confirmPayment(id, !!success, { role: session.user.role });
    return NextResponse.json(payment);
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/api/payments/[id]/confirm/route.ts"

$path = "src/app/login/page.tsx"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
"use client";

import { useState, Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { signIn } from "next-auth/react";
import Link from "next/link";

const ROLE_LABEL: Record<string, string> = {
  client: "claimant environment",
  processor: "processor environment",
  admin: "admin environment",
};

const ROLE_REDIRECT: Record<string, string> = {
  client: "/claimant",
  processor: "/admin",
  admin: "/admin",
};

function LoginForm() {
  const router = useRouter();
  const params = useSearchParams();
  const role = params.get("role") || "client";

  const [email, setEmail] = useState(`${role}@claimspro.dev`);
  const [password, setPassword] = useState("Passw0rd!");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleLogin() {
    setLoading(true);
    setError(null);
    const res = await signIn("credentials", { email, password, redirect: false });
    setLoading(false);

    if (res?.error) {
      setError("Invalid credentials. Please check your email and password.");
      return;
    }
    // If we got here via the middleware bouncing an unauthenticated request
    // (e.g. someone scanning the LOA's QR code on a device without a
    // session), honor that original destination instead of always sending
    // the user to their role's default portal.
    const callbackUrl = params.get("callbackUrl");
    router.push(callbackUrl && callbackUrl.startsWith("/") ? callbackUrl : ROLE_REDIRECT[role] ?? "/claimant");
  }

  return (
    <div className="bg-white p-12 rounded-3xl shadow-2xl w-full max-w-md relative overflow-hidden">
      <div className="absolute top-0 left-0 w-full h-2 bg-teal" />
      <div className="text-center mb-10">
        <h2 className="inline-block px-3 py-1 bg-teal-50 text-teal text-[10px] font-black uppercase tracking-widest rounded-full mb-4">
          {ROLE_LABEL[role] ?? "secure access"}
        </h2>
        <h1 className="text-3xl font-bold text-slate-800">Welcome Back</h1>
      </div>

      <div className="space-y-6">
        <div>
          <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Email</label>
          <div className="relative mt-1">
            <i className="fa-solid fa-user absolute left-4 top-4 text-slate-300" />
            <input
              type="text"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full pl-12 pr-4 py-4 border border-slate-100 rounded-xl outline-none focus:border-teal bg-slate-50"
            />
          </div>
        </div>
        <div>
          <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Password</label>
          <div className="relative mt-1">
            <i className="fa-solid fa-lock absolute left-4 top-4 text-slate-300" />
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full pl-12 pr-4 py-4 border border-slate-100 rounded-xl outline-none focus:border-teal bg-slate-50"
            />
          </div>
        </div>

        {error && <p className="text-red-500 text-xs font-bold text-center">{error}</p>}

        <button
          onClick={handleLogin}
          disabled={loading}
          className="w-full bg-navy text-white py-4 rounded-xl font-bold hover:bg-teal transition duration-300 shadow-xl shadow-slate-200 disabled:opacity-50"
        >
          {loading ? "Authenticating..." : "Authenticate System"}
        </button>
        <Link href="/" className="block text-center text-xs text-slate-400 hover:text-teal transition mt-4">
          Return to Gateway
        </Link>
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <div className="bg-navy flex items-center justify-center min-h-screen">
      <Suspense fallback={null}>
        <LoginForm />
      </Suspense>
    </div>
  );
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/login/page.tsx"

$path = "src/app/page.tsx"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import Image from "next/image";
import Link from "next/link";

// Converted 1:1 from the original index.html hero + role-select sections.
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
          <p className="text-xl text-slate-600 mb-10 leading-relaxed max-w-2xl">
            A cloud-native solution for real-time document verification, automated LOA logic, and
            enterprise-grade claims lifecycle management.
          </p>
          <div className="flex space-x-4">
            <a
              href="#roles"
              className="bg-teal text-white px-10 py-5 rounded-xl font-bold hover:scale-105 transition shadow-xl shadow-teal-100"
            >
              Get Started
            </a>
            <button className="border border-slate-300 px-10 py-5 rounded-xl font-bold hover:bg-slate-50 transition">
              Watch Demo
            </button>
          </div>
        </div>
      </section>

      <section id="roles" className="py-24 px-12 bg-slate-50">
        <div className="text-center mb-20">
          <h2 className="text-4xl font-black text-navy">Access Portals</h2>
          <p className="text-slate-500 mt-2">Select your designated interface to manage the claims lifecycle.</p>
        </div>

        <div className="grid md:grid-cols-2 gap-10 max-w-5xl mx-auto">
          <RoleCard
            icon="fa-user-tag"
            title="Claimant"
            desc="Submit claims, upload medical/property evidence, and track approval status."
            href="/login?role=client"
            cta="Enter Portal"
          />
          <RoleCard
            icon="fa-gears"
            title="Admin"
            desc="Configure system parameters, manage users, verify claims, and monitor LOA analytics."
            href="/login?role=admin"
            cta="Staff / Admin Panel"
          />
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

function RoleCard({ icon, title, desc, href, cta }: { icon: string; title: string; desc: string; href: string; cta: string }) {
  return (
    <div className="group bg-white p-12 rounded-3xl shadow-sm border border-slate-100 hover:shadow-2xl transition-all">
      <div className="w-16 h-16 bg-slate-50 rounded-2xl flex items-center justify-center mb-8 group-hover:bg-teal-50 transition">
        <i className={`fa-solid ${icon} text-3xl text-slate-300 group-hover:text-teal`} />
      </div>
      <h3 className="text-2xl font-bold mb-3 text-navy">{title}</h3>
      <p className="text-slate-500 mb-8 text-sm leading-relaxed">{desc}</p>
      <Link href={href} className="text-teal font-bold flex items-center group-hover:translate-x-2 transition">
        {cta} <i className="fa-solid fa-arrow-right ml-2" />
      </Link>
    </div>
  );
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/page.tsx"

$path = "src/app/pay/[id]/page.tsx"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
"use client";
import { useState } from "react";
import { useParams, useRouter, useSearchParams } from "next/navigation";
import { useSession } from "next-auth/react";

// In-app mock checkout screen. Used automatically when no real gateway
// credentials (PAYMONGO_SECRET_KEY / PAYPAL_CLIENT_ID) are configured, so the
// full payout flow — including notifications — is testable without a live
// merchant account. Swap in the real gateway's hosted checkout by configuring
// the env vars documented in README.md; this page then simply isn't reached.
// BANK_TRANSFER is the one exception: it never has a "live gateway" mode —
// there's no gateway for a bank deposit, so staff verify it here for real.
const PROVIDER_LABEL: Record<string, string> = { GCASH: "GCash", MAYA: "Maya", PAYPAL: "PayPal", BANK_TRANSFER: "Bank Transfer" };

export default function MockCheckoutPage() {
  const { id } = useParams<{ id: string }>();
  const params = useSearchParams();
  const router = useRouter();
  const { data: session, status: sessionStatus } = useSession();
  const provider = params.get("provider") ?? "GCASH";
  const isBankTransfer = provider === "BANK_TRANSFER";
  const isStaff = session?.user?.role === "PROCESSOR" || session?.user?.role === "ADMIN";
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function resolve(success: boolean) {
    setLoading(true);
    setError(null);
    const res = await fetch(`/api/payments/${id}/confirm`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ success }),
    });
    setLoading(false);
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      setError(body.error ?? "Could not update this payment.");
      return;
    }
    router.push(`/pay/${id}/return?status=${success ? "success" : "failed"}`);
  }

  // A claimant landing here for their own bank transfer can't self-confirm
  // it (see payment.service.ts) — show them what's actually happening
  // instead of buttons that would just fail with a permissions error.
  if (isBankTransfer && sessionStatus !== "loading" && !isStaff) {
    return (
      <div className="bg-navy min-h-screen flex items-center justify-center">
        <div className="bg-white rounded-3xl shadow-2xl p-12 max-w-md w-full text-center">
          <span className="inline-block px-3 py-1 bg-amber-50 text-amber-600 text-[10px] font-black uppercase tracking-widest rounded-full mb-4">
            Pending Verification
          </span>
          <h1 className="text-2xl font-bold text-slate-800 mb-2">Bank Transfer Submitted</h1>
          <p className="text-slate-400 text-sm">
            Your bank details have been recorded. Our team will verify the deposit and update your claim - you&apos;ll get a notification once it&apos;s processed.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-navy min-h-screen flex items-center justify-center">
      <div className="bg-white rounded-3xl shadow-2xl p-12 max-w-md w-full text-center">
        <span className="inline-block px-3 py-1 bg-teal-50 text-teal text-[10px] font-black uppercase tracking-widest rounded-full mb-4">
          {isBankTransfer ? "Staff Verification" : "Sandbox Checkout"}
        </span>
        <h1 className="text-2xl font-bold text-slate-800 mb-2">Claim via {PROVIDER_LABEL[provider] ?? provider}</h1>
        <p className="text-slate-400 text-sm mb-10">
          {isBankTransfer
            ? "Confirm whether the deposit for this claim has cleared."
            : "This is a local sandbox screen shown because no live gateway credentials are configured."}
        </p>
        {error && <p className="text-red-500 text-xs font-bold mb-4">{error}</p>}
        <div className="space-y-3">
          <button
            onClick={() => resolve(true)}
            disabled={loading}
            className="w-full bg-navy text-white py-4 rounded-xl font-bold hover:bg-teal transition disabled:opacity-50"
          >
            {loading ? "Processing…" : isBankTransfer ? "Confirm Deposit Received" : "Simulate Successful Payout"}
          </button>
          <button
            onClick={() => resolve(false)}
            disabled={loading}
            className="w-full border border-slate-200 text-slate-500 py-4 rounded-xl font-bold hover:bg-slate-50 transition disabled:opacity-50"
          >
            {isBankTransfer ? "Reject - No Deposit Found" : "Simulate Failed Payout"}
          </button>
        </div>
      </div>
    </div>
  );
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/pay/[id]/page.tsx"

$path = "src/components/chat/ChatWidget.tsx"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
"use client";
import { useEffect, useRef, useState } from "react";

interface Message {
  id?: string;
  role: "user" | "assistant";
  content: string;
}

// Floating support chatbot ("Clai") available across every authenticated
// portal page. Calls /api/chat, which uses the Claude API when configured
// and otherwise falls back to a friendly rule-based FAQ responder — either
// way, replies use a light touch of emoji as requested.
//
// Rendered with key={userId} by PortalChrome so that switching logged-in
// accounts fully remounts this component (resetting messages, open state,
// everything) rather than leaving a previous account's chat history in
// memory — /api/chat itself is correctly scoped per-user server-side, but
// this component can otherwise stay mounted across a login switch.
export function ChatWidget() {
  const [open, setOpen] = useState(false);
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [sending, setSending] = useState(false);
  const endRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (open && messages.length === 0) {
      fetch("/api/chat")
        .then((r) => (r.ok ? r.json() : Promise.reject(new Error(`History fetch failed: ${r.status}`))))
        .then((history) => {
          if (Array.isArray(history) && history.length > 0) {
            setMessages(history);
          } else {
            setMessages([{ role: "assistant", content: "Hey! 👋 I'm Clai, your ClaimsPro assistant. Ask me anything about claims, LOAs, or payments!" }]);
          }
        })
        .catch((err) => {
          console.error("Clai: failed to load chat history", err);
          setMessages([{ role: "assistant", content: "Hey! 👋 I'm Clai. (Couldn't load earlier messages, but go ahead and ask something!)" }]);
        });
    }
  }, [open, messages.length]);

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, open]);

  async function send() {
    const text = input.trim();
    if (!text || sending) return;
    setInput("");
    setMessages((m) => [...m, { role: "user", content: text }]);
    setSending(true);

    try {
      const res = await fetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: text }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error ? JSON.stringify(body.error) : `Request failed: ${res.status}`);
      }
      const data = await res.json();
      setMessages((m) => [...m, { role: "assistant", content: data.reply ?? "Sorry, I couldn't respond just now 😅" }]);
    } catch (err) {
      console.error("Clai: send failed", err);
      setMessages((m) => [...m, { role: "assistant", content: "Something went wrong on my end 😅 Please try again." }]);
    } finally {
      setSending(false);
    }
  }

  return (
    <div className="fixed bottom-6 right-6 z-50">
      {open && (
        <div className="w-80 h-[28rem] bg-white rounded-3xl shadow-2xl border border-slate-100 flex flex-col overflow-hidden mb-4">
          <div className="bg-navy text-white px-5 py-4 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className="text-lg">🤖</span>
              <span className="font-bold text-sm">Clai · Support</span>
            </div>
            <button onClick={() => setOpen(false)} className="text-slate-300 hover:text-white">
              <i className="fa-solid fa-xmark" />
            </button>
          </div>

          <div className="flex-1 overflow-y-auto p-4 space-y-3 bg-slate-50">
            {messages.map((m, i) => (
              <div key={m.id ?? i} className={`flex ${m.role === "user" ? "justify-end" : "justify-start"}`}>
                <div
                  className={`max-w-[85%] px-4 py-2 rounded-2xl text-sm ${
                    m.role === "user" ? "bg-teal text-white rounded-br-sm" : "bg-white text-slate-700 border border-slate-100 rounded-bl-sm"
                  }`}
                >
                  {m.content}
                </div>
              </div>
            ))}
            {sending && <div className="text-xs text-slate-400 italic">Clai is typing… 💭</div>}
            <div ref={endRef} />
          </div>

          <div className="p-3 border-t border-slate-100 flex gap-2">
            <input
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && send()}
              placeholder="Ask about your claim…"
              className="flex-1 px-4 py-2 rounded-full bg-slate-50 border border-slate-100 outline-none focus:border-teal text-sm"
            />
            <button onClick={send} className="w-10 h-10 rounded-full bg-navy text-white flex items-center justify-center hover:bg-teal transition">
              <i className="fa-solid fa-paper-plane text-xs" />
            </button>
          </div>
        </div>
      )}

      <button
        onClick={() => setOpen((o) => !o)}
        className="w-14 h-14 rounded-full bg-teal text-white shadow-xl flex items-center justify-center text-2xl hover:scale-105 transition"
      >
        {open ? <i className="fa-solid fa-xmark" /> : <i className="fa-solid fa-comment-dots" />}
      </button>
    </div>
  );
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/components/chat/ChatWidget.tsx"

$path = "src/components/providers/PortalChrome.tsx"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
"use client";
import { useSession } from "next-auth/react";
import { NotificationBell } from "@/components/ui/NotificationBell";
import { ChatWidget } from "@/components/chat/ChatWidget";

// Renders the notification bell + support chatbot on every page once a user
// is signed in; renders nothing on the public landing/login pages.
export function PortalChrome() {
  const { status, data: session } = useSession();
  if (status !== "authenticated") return null;

  return (
    <>
      <NotificationBell />
      {/* key={userId} forces a full remount (fresh state, no leftover chat
          history) if a different account logs in on the same browser without
          a full page reload. */}
      <ChatWidget key={session.user.id} />
    </>
  );
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/components/providers/PortalChrome.tsx"

$path = "src/components/ui/NotificationBell.tsx"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useSession } from "next-auth/react";
import { NotificationDTO } from "@/types";

const ICON: Record<string, string> = {
  STATUS_UPDATE: "fa-file-invoice",
  RENEWAL: "fa-rotate",
  PAYMENT: "fa-credit-card",
};

function homeForRole(role?: string) {
  if (role === "PROCESSOR" || role === "ADMIN") return "/admin";
  return "/claimant/claims";
}

export function NotificationBell() {
  const { data: session } = useSession();
  const [open, setOpen] = useState(false);
  const [items, setItems] = useState<NotificationDTO[]>([]);
  const [unread, setUnread] = useState(0);
  const boxRef = useRef<HTMLDivElement>(null);

  async function load() {
    const res = await fetch("/api/notifications");
    if (!res.ok) return;
    const data = await res.json();
    setItems(data.items);
    setUnread(data.unread);
  }

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
    const interval = setInterval(load, 30000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    function onClickOutside(e: MouseEvent) {
      if (boxRef.current && !boxRef.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", onClickOutside);
    return () => document.removeEventListener("mousedown", onClickOutside);
  }, []);

  async function markRead(id: string) {
    await fetch(`/api/notifications/${id}`, { method: "PATCH" });
    load();
  }

  return (
    <div className="fixed top-6 right-6 z-40" ref={boxRef}>
      <button
        onClick={() => setOpen((o) => !o)}
        className="relative w-11 h-11 rounded-full bg-white shadow-lg border border-slate-100 flex items-center justify-center hover:shadow-xl transition"
      >
        <i className="fa-solid fa-bell text-slate-600" />
        {unread > 0 && (
          <span className="absolute -top-1 -right-1 bg-red-500 text-white text-[10px] font-black w-5 h-5 rounded-full flex items-center justify-center">
            {unread > 9 ? "9+" : unread}
          </span>
        )}
      </button>

      {open && (
        <div className="absolute right-0 mt-3 w-80 bg-white rounded-2xl shadow-2xl border border-slate-100 overflow-hidden">
          <div className="px-5 py-4 border-b border-slate-50 font-bold text-navy text-sm">Notifications</div>
          <div className="max-h-96 overflow-y-auto divide-y divide-slate-50">
            {items.length === 0 && <p className="p-6 text-center text-slate-400 text-sm">You&apos;re all caught up.</p>}
            {items.map((n) => (
              <button
                key={n.id}
                onClick={() => !n.read && markRead(n.id)}
                className={`w-full text-left px-5 py-4 flex items-start gap-3 hover:bg-slate-50 transition ${!n.read ? "bg-teal-50/40" : ""}`}
              >
                <i className={`fa-solid ${ICON[n.type] ?? "fa-bell"} text-teal mt-0.5`} />
                <div>
                  <p className="text-sm text-slate-700">{n.message}</p>
                  <p className="text-[10px] text-slate-400 mt-1 uppercase font-bold">
                    {new Date(n.createdAt).toLocaleString()}
                  </p>
                </div>
              </button>
            ))}
          </div>
          <Link href={homeForRole(session?.user?.role)} className="block text-center text-xs font-bold text-teal py-3 hover:underline border-t border-slate-50">
            {session?.user?.role === "CLIENT" ? "View My Claims" : "Back to Dashboard"}
          </Link>
        </div>
      )}
    </div>
  );
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/components/ui/NotificationBell.tsx"

$path = "src/lib/loaDocument.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
// Builds the standalone HTML document shown in the LOA popup window —
// shared by the claims history page and the claim detail page so the
// markup (and QR code placement) only lives in one place.
//
// `content` includes the claimant's name (user-supplied data — currently set
// by an Admin, but a future self-registration flow could let anyone set it),
// so it MUST be HTML-escaped before going into document.write(). Without
// this, a name like `<img src=x onerror=...>` would execute as real script
// in the popup's context the moment anyone views that claim's LOA.
function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export function buildLoaHtml(content: string, qrCodeDataUrl?: string, payoutUrl?: string, providerLabel: string = "GCash"): string {
  const safeContent = escapeHtml(content);
  const safePayoutUrl = payoutUrl ? escapeHtml(payoutUrl) : undefined;
  const safeProviderLabel = escapeHtml(providerLabel);

  const qrSection = qrCodeDataUrl
    ? `
      <div style="margin-top:32px;padding-top:24px;border-top:1px dashed #ccc;text-align:center;">
        <img src="${qrCodeDataUrl}" alt="Scan to claim your payout" width="180" height="180" />
        <p style="font-family:sans-serif;font-size:13px;color:#475569;margin-top:8px;">
          Scan to claim your payout via ${safeProviderLabel}
        </p>
        ${safePayoutUrl ? `<p style="font-family:sans-serif;font-size:11px;color:#94a3b8;">${safePayoutUrl}</p>` : ""}
      </div>`
    : "";

  return `<pre style="font-family:serif;padding:50px 50px 10px;white-space:pre-wrap;line-height:1.6;">${safeContent}</pre>${qrSection}`;
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/lib/loaDocument.ts"

$path = "src/lib/prisma.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { PrismaClient } from "@prisma/client";
import { validateEnv } from "./env";

validateEnv();

// Singleton pattern: prevents exhausting DB connections from hot-reloaded
// serverless functions in dev, and keeps one client per Lambda instance in prod.
const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

export const prisma = globalForPrisma.prisma ?? new PrismaClient();

if (process.env.NODE_ENV !== "production") globalForPrisma.prisma = prisma;
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/lib/prisma.ts"

$path = "src/repositories/interfaces.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
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
  createForClaim(claimId: string, content: string, generatedById: string, provider: string): Promise<Loa>;
  count(): Promise<number>;
}

export interface INotificationRepository {
  createForUser(userId: string, type: "STATUS_UPDATE" | "RENEWAL" | "PAYMENT", message: string, claimId?: string): Promise<any>;
  listForUser(userId: string): Promise<any[]>;
  markRead(id: string, userId: string): Promise<any>;
  unreadCount(userId: string): Promise<number>;
}

export interface IPaymentRepository {
  create(data: {
    claimId: string;
    provider: "GCASH" | "MAYA" | "PAYPAL" | "BANK_TRANSFER";
    amount: number;
    providerRef?: string;
    bankName?: string;
    accountName?: string;
    accountNumber?: string;
  }): Promise<any>;
  findById(id: string): Promise<any>;
  updateStatus(id: string, status: "PENDING" | "PAID" | "FAILED"): Promise<any>;
  listForClaim(claimId: string): Promise<any[]>;
}

export interface IAuditLogRepository {
  log(data: { actorId?: string; actorName: string; actorRole: string; action: string; detail?: string }): Promise<void>;
  list(limit?: number): Promise<any[]>;
}

export interface IPayoutPreferenceRepository {
  findByUserId(userId: string): Promise<any | null>;
  upsert(userId: string, data: { provider: string; bankName?: string | null; accountName?: string | null; accountNumber?: string | null }): Promise<any>;
}

export interface IDocumentRepository {
  createForClaim(data: { claimId: string; fileName: string; fileUrl: string; mimeType: string; sizeBytes: number }): Promise<Document>;
  listForClaim(claimId: string): Promise<Document[]>;
  findById(id: string): Promise<Document | null>;
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/repositories/interfaces.ts"

$path = "src/repositories/loa.repository.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { PrismaClient, PaymentProvider } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { ILoaRepository } from "./interfaces";

export class PrismaLoaRepository implements ILoaRepository {
  constructor(private readonly db: PrismaClient = prisma) {}

  createForClaim(claimId: string, content: string, generatedById: string, provider: PaymentProvider) {
    return this.db.loa.create({ data: { claimId, content, generatedById, provider } });
  }

  count() {
    return this.db.loa.count();
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/repositories/loa.repository.ts"

$path = "src/repositories/payment.repository.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { PaymentProvider, PaymentStatus, PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { IPaymentRepository } from "./interfaces";

export class PrismaPaymentRepository implements IPaymentRepository {
  constructor(private readonly db: PrismaClient = prisma) {}

  create(data: {
    claimId: string;
    provider: PaymentProvider;
    amount: number;
    providerRef?: string;
    bankName?: string;
    accountName?: string;
    accountNumber?: string;
  }) {
    return this.db.payment.create({ data });
  }

  findById(id: string) {
    return this.db.payment.findUnique({ where: { id }, include: { claim: true } });
  }

  updateStatus(id: string, status: PaymentStatus) {
    return this.db.payment.update({ where: { id }, data: { status } });
  }

  listForClaim(claimId: string) {
    return this.db.payment.findMany({ where: { claimId }, orderBy: { createdAt: "desc" } });
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/repositories/payment.repository.ts"

$path = "src/services/chat.service.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { prisma } from "@/lib/prisma";
import { IClaimRepository } from "@/repositories/interfaces";
import { PrismaClaimRepository } from "@/repositories/claim.repository";
import { StatsService } from "./stats.service";

const SYSTEM_PROMPT = `You are Clai, the friendly support assistant for ClaimsPro, an insurance claims
platform. Help users understand how to submit claims, check claim status, generate a Letter of
Authorization once approved, and claim their payout via GCash, Maya, or PayPal once a claim is
approved for disbursement. Keep answers short (2-4 sentences), warm, and sprinkle in a relevant
emoji or two per message (not excessive). If asked something outside claims/insurance/the
platform, gently redirect. Never invent claim statuses or amounts - tell the user to check their
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
  { keywords: ["who are you", "what are you", "what can you do", "help me", "how do you work"], answer: "I'm Clai 🤖 - I can help explain how claims move through the system, and I can also look up your live counts - try asking 'how many claims do I have?' 📊" },
  { keywords: ["human", "agent", "real person", "representative"], answer: "I'm just a support bot for now, so I can't connect you to a live person 🙏 - for anything urgent, please reach out to your account contact directly." },
  { keywords: ["document", "upload", "evidence", "attach", "receipt", "file size"], answer: "You can attach evidence (PDF, PNG, or JPG, up to 10MB) when submitting a claim, or later from the claim's detail page 📎" },
  { keywords: ["notification", "notify", "bell", "alert"], answer: "The 🔔 bell (top-right) shows updates whenever a claim status changes or a payment goes through - click one to mark it read." },
  { keywords: ["renew", "renewal", "expire", "expiring"], answer: "Renewal reminders go out automatically as an approved policy nears its renewal window - keep an eye on your 🔔 notifications for that nudge." },
  { keywords: ["login", "log in", "password", "sign in", "account locked", "forgot password"], answer: "If you're having trouble signing in, double check your email and password - for a reset, please contact your administrator for now 🔑" },
  { keywords: ["medical", "hospitalization"], answer: "Medical Expense Coverage handles hospitalization and treatment-related costs - attach medical records or receipts when you submit 🏥" },
  { keywords: ["automotive", "car", "vehicle", "accident"], answer: "Automotive Damage claims cover accidental vehicle damage - photos and repair estimates make great supporting evidence 🚗" },
  { keywords: ["home", "homeowner", "property"], answer: "Homeowners Protection covers property damage claims - receipts, photos, and any assessor reports help speed up verification 🏠" },
];

const CLIENT_FAQ: { keywords: string[]; answer: string }[] = [
  { keywords: ["submit", "new claim", "file a claim", "how to claim"], answer: "To submit a claim, go to your Claimant dashboard, pick a policy category, enter your estimate, attach your documents, then hit Submit for Verification 📝✅" },
  { keywords: ["loa", "letter of authorization"], answer: "Once your claim is Approved, a View LOA button appears in your claims history - click it to generate your Letter of Authorization 📄✨" },
  { keywords: ["pay", "gcash", "maya", "paypal", "bank", "payment", "payout", "claim my money", "disbursement"], answer: "Once your claim is approved, head to its detail page to claim your payout via GCash, Maya, PayPal, or bank transfer - or scan the QR code on your LOA to jump straight into a GCash checkout 💸" },
];

const PROCESSOR_FAQ: { keywords: string[]; answer: string }[] = [
  { keywords: ["queue"], answer: "Your Verification Queue lists every claim needing action, newest first - click a reference ID to see full details and documents 📋" },
];

const ADMIN_FAQ: { keywords: string[]; answer: string }[] = [
  { keywords: ["add user", "create user", "create account", "new account", "provision"], answer: "Head to Identity Manager and use the 'Provision New Account' form - set a name, email, temporary password, and role 👤" },
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
    return "You haven't submitted any claims yet 📝 - head to New Claim Request to file your first one!";
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

  return `You've handled ${handled} claim${handled === 1 ? "" : "s"} total - ${counts.VERIFIED} Verified (awaiting approval), ${counts.APPROVED} Approved, ${counts.REJECTED} Rejected. There ${pendingInQueue === 1 ? "is" : "are"} also ${pendingInQueue} claim${pendingInQueue === 1 ? "" : "s"} still Pending in the shared queue 📋`;
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

  return "I'm not totally sure about that one 🤔 - try asking about submitting a claim, checking status, documents, LOAs, payments, or your live counts!";
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
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/services/chat.service.ts"

$path = "src/services/claim.service.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { ClaimStatus, PolicyCategory, Role } from "@prisma/client";
import { IClaimRepository, ClaimWithRelations } from "@/repositories/interfaces";
import { PrismaClaimRepository } from "@/repositories/claim.repository";
import { NotificationService } from "./notification.service";
import { AuditService } from "./audit.service";
import { ClaimValidationService } from "./claim-validation.service";

// Business rules live here (SRP). Route handlers stay thin "controllers" that
// only translate HTTP <-> service calls; the service never touches req/res.
export class ClaimService {
  constructor(
    private readonly claims: IClaimRepository = new PrismaClaimRepository(),
    private readonly notifications: NotificationService = new NotificationService(),
    private readonly audit: AuditService = new AuditService(),
    private readonly validation: ClaimValidationService = new ClaimValidationService()
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

  async transitionStatus(claimId: string, nextStatus: ClaimStatus, processorId: string, actor?: { name: string; role: string }) {
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
      // Awaited (not fire-and-forget): on a serverless runtime like Vercel, an
      // un-awaited promise can be cut off the instant the response is sent, so
      // a "best-effort" background write could silently never land.
      await this.notifications.notifyStatusChange(updated.userId, updated.referenceId, nextStatus, updated.id);
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
        detail: `${updated.referenceId} moved from ${claim.status} to ${nextStatus}`,
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
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/services/claim.service.ts"

$path = "src/services/loa.service.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { PaymentProvider } from "@prisma/client";
import { ILoaRepository } from "@/repositories/interfaces";
import { PrismaLoaRepository } from "@/repositories/loa.repository";
import { IClaimRepository } from "@/repositories/interfaces";
import { PrismaClaimRepository } from "@/repositories/claim.repository";
import { PayoutPreferenceService } from "./payout-preference.service";
import { ServiceError } from "./claim.service";

const PROVIDER_LABEL: Record<PaymentProvider, string> = {
  GCASH: "GCash",
  MAYA: "Maya",
  PAYPAL: "PayPal",
  BANK_TRANSFER: "Bank Transfer",
};

// Generates the Letter of Authorization text and persists it once a claim
// is APPROVED. Kept separate from ClaimService (SRP) since LOA formatting
// is a distinct responsibility from claim lifecycle rules.
export class LoaService {
  constructor(
    private readonly loas: ILoaRepository = new PrismaLoaRepository(),
    private readonly claims: IClaimRepository = new PrismaClaimRepository(),
    private readonly payoutPreferences: PayoutPreferenceService = new PayoutPreferenceService()
  ) {}

  async generateForClaim(claimId: string, generatedById: string) {
    const claim = await this.claims.findById(claimId);
    if (!claim) throw new ServiceError("Claim not found.", 404);
    if (claim.status !== "APPROVED") {
      throw new ServiceError("LOA can only be generated for approved claims.", 409);
    }
    // Already generated: return as-is. The provider named in the letter's
    // text is locked in at first generation — re-deriving it from whatever
    // the claimant's Settings preference happens to be *now* would risk the
    // letter's printed text and the QR silently disagreeing.
    if (claim.loa) return claim.loa;

    const preference = await this.payoutPreferences.get(claim.userId);
    const provider: PaymentProvider = preference?.provider ?? "GCASH";

    const content = this.buildLetter(claim.referenceId, claim.category, claim.user.name, provider);
    return this.loas.createForClaim(claimId, content, generatedById, provider);
  }

  private buildLetter(referenceId: string, category: string, claimantName: string, provider: PaymentProvider): string {
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
      `Scan the QR code below to claim your payout via ${PROVIDER_LABEL[provider]}.`,
      "",
      "Signature: ________________",
      "Claims Administrator",
    ].join("\n");
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/services/loa.service.ts"

$path = "src/services/notification.service.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { INotificationRepository } from "@/repositories/interfaces";
import { PrismaNotificationRepository } from "@/repositories/notification.repository";

// Central place for creating and reading notifications. Called by ClaimService
// (status changes), LoaService (LOA ready), PaymentService (payment result),
// and the renewal-reminder endpoint (policy renewal nudges).
export class NotificationService {
  constructor(private readonly notifications: INotificationRepository = new PrismaNotificationRepository()) {}

  notifyStatusChange(userId: string, referenceId: string, status: string, claimId: string) {
    const messages: Record<string, string> = {
      VERIFIED: `Your claim ${referenceId} has been verified and is awaiting final approval.`,
      APPROVED: `Great news - claim ${referenceId} has been approved.`,
      REJECTED: `Claim ${referenceId} was not approved. You can view details in your claims history.`,
    };
    const message = messages[status] ?? `Claim ${referenceId} status changed to ${status}.`;
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
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/services/notification.service.ts"

$path = "src/services/payment.service.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { PaymentProvider } from "@prisma/client";
import { IPaymentRepository, IClaimRepository } from "@/repositories/interfaces";
import { PrismaPaymentRepository } from "@/repositories/payment.repository";
import { PrismaClaimRepository } from "@/repositories/claim.repository";
import { getPaymentProvider } from "./payments/provider.factory";
import { NotificationService } from "./notification.service";
import { AuditService } from "./audit.service";
import { ServiceError } from "./claim.service";

export interface BankDetails {
  bankName: string;
  accountName: string;
  accountNumber: string;
}

export class PaymentService {
  constructor(
    private readonly payments: IPaymentRepository = new PrismaPaymentRepository(),
    private readonly claims: IClaimRepository = new PrismaClaimRepository(),
    private readonly notifications: NotificationService = new NotificationService(),
    private readonly audit: AuditService = new AuditService()
  ) {}

  async startCheckout(
    claimId: string,
    provider: PaymentProvider,
    amount: number,
    bankDetails?: BankDetails,
    actor?: { id: string; name: string; role: string }
  ) {
    const claim = await this.claims.findById(claimId);
    if (!claim) throw new ServiceError("Claim not found.", 404);
    if (claim.status !== "APPROVED") {
      throw new ServiceError("Payouts can only be claimed on approved claims.", 409);
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new ServiceError("Payout amount must be greater than zero.", 400);
    }
    if (provider === "BANK_TRANSFER") {
      if (!bankDetails?.bankName?.trim() || !bankDetails?.accountName?.trim() || !bankDetails?.accountNumber?.trim()) {
        throw new ServiceError("Bank name, account name, and account number are required for bank transfer.", 400);
      }
    }

    const payment = await this.payments.create({
      claimId,
      provider,
      amount,
      ...(provider === "BANK_TRANSFER" ? bankDetails : {}),
    });

    const checkout = await this.createCheckoutSafely(provider, payment.id, amount, claim.referenceId);

    if (actor) {
      await this.audit.log({
        actorId: actor.id,
        actorName: actor.name,
        actorRole: actor.role,
        action: "PAYOUT_INITIATED",
        detail: `${provider} payout of PHP ${amount.toLocaleString()} started for claim ${claim.referenceId}`,
      });
    }

    return { paymentId: payment.id, redirectUrl: checkout.redirectUrl };
  }

  // Used by the LOA/QR flow: the QR needs to land the claimant straight on a
  // checkout for whichever provider their LOA was generated for, not a page
  // they have to be logged in to see. Reuses an already-pending payment of
  // that same provider for the claim if one exists (so re-viewing the LOA
  // doesn't spawn a new "Pending" row in the payout history every time) but
  // always re-mints the checkout redirect, since real gateway checkout
  // sessions are short-lived and shouldn't be persisted/reused.
  async getOrCreateCheckoutForClaim(claimId: string, provider: PaymentProvider, amount: number, bankDetails?: BankDetails) {
    const claim = await this.claims.findById(claimId);
    if (!claim) throw new ServiceError("Claim not found.", 404);
    if (claim.status !== "APPROVED") {
      throw new ServiceError("Payouts can only be claimed on approved claims.", 409);
    }

    const existing = claim.payments.find((p: any) => p.provider === provider && p.status === "PENDING");
    const payment =
      existing ??
      (await this.payments.create({
        claimId,
        provider,
        amount,
        ...(provider === "BANK_TRANSFER" && bankDetails ? bankDetails : {}),
      }));

    const checkout = await this.createCheckoutSafely(provider, payment.id, Number(payment.amount), claim.referenceId);

    return { paymentId: payment.id, redirectUrl: checkout.redirectUrl };
  }

  // Wraps a gateway's createCheckout call so a failure (invalid/expired API
  // key, network error, gateway rejecting the request) becomes a clean,
  // actionable ServiceError instead of an unhandled exception that crashes
  // the request into an opaque 500 with no useful message for the caller.
  private async createCheckoutSafely(provider: PaymentProvider, paymentId: string, amount: number, referenceId: string) {
    const strategy = getPaymentProvider(provider);
    try {
      return await strategy.createCheckout({
        paymentId,
        amount,
        description: `ClaimsPro - ${referenceId}`,
      });
    } catch (err) {
      console.error(`Checkout creation failed for provider ${provider}:`, err);
      throw new ServiceError(
        `Could not start a ${provider} checkout right now. This usually means the payment gateway credentials in .env are invalid or misconfigured - check PAYMONGO_SECRET_KEY / PAYPAL_CLIENT_ID, or remove them to use the sandbox mock checkout instead.`,
        502
      );
    }
  }

  async confirmPayment(paymentId: string, success: boolean, actor?: { role: string }) {
    const payment = await this.payments.findById(paymentId);
    if (!payment) throw new ServiceError("Payment not found.", 404);

    // A GCash/Maya/PayPal "confirm" here stands in for a gateway webhook —
    // the claimant genuinely paid through that provider's own app, so letting
    // them trigger this is fine. A bank transfer has no such gateway: nothing
    // outside this app verifies the deposit actually happened, so only staff
    // (who can check the bank statement) may confirm one.
    if (payment.provider === "BANK_TRANSFER" && actor?.role !== "PROCESSOR" && actor?.role !== "ADMIN") {
      throw new ServiceError("Bank transfer payouts can only be verified by staff.", 403);
    }

    const status = success ? "PAID" : "FAILED";

    // Idempotency guard: this can legitimately be called more than once for the
    // same outcome — the mock checkout page confirms once, then the /return
    // page confirms again for parity with real gateways that redirect straight
    // there; real webhook providers also commonly redeliver. Skip the update
    // and (critically) the notification if the status has already landed.
    if (payment.status === status) {
      return payment;
    }

    const updated = await this.payments.updateStatus(paymentId, status);

    try {
      await this.notifications.notifyPayment(payment.claim.userId, payment.claim.referenceId, status, payment.claimId);
    } catch (err) {
      console.error("Failed to create payment notification:", err);
    }

    return updated;
  }

  listForClaim(claimId: string) {
    return this.payments.listForClaim(claimId);
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/services/payment.service.ts"

$path = "src/services/payments/provider.factory.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { PaymentProvider } from "@prisma/client";
import { IPaymentProvider } from "./provider.interface";
import { GcashProvider, MayaProvider } from "./paymongo.provider";
import { PaypalProvider } from "./paypal.provider";
import { BankTransferProvider } from "./bank-transfer.provider";

// Factory Method: isolates the mapping of "provider name" -> concrete class.
// PaymentService never instantiates a provider class directly, so adding a
// new gateway only ever touches this file plus the new provider class.
export function getPaymentProvider(name: PaymentProvider): IPaymentProvider {
  switch (name) {
    case "GCASH":
      return new GcashProvider();
    case "MAYA":
      return new MayaProvider();
    case "PAYPAL":
      return new PaypalProvider();
    case "BANK_TRANSFER":
      return new BankTransferProvider();
    default:
      throw new Error(`Unsupported payment provider: ${name}`);
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/services/payments/provider.factory.ts"

$path = "src/services/payments/provider.interface.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
// Strategy pattern: every payment provider (GCash, Maya, PayPal) implements
// this same contract. PaymentService depends only on this interface (OCP) —
// adding a new provider (e.g. GrabPay) means writing one new class and
// registering it in the factory, with no changes to PaymentService itself.
export interface CheckoutResult {
  redirectUrl: string;
  providerRef: string;
}

export interface IPaymentProvider {
  readonly name: "GCASH" | "MAYA" | "PAYPAL" | "BANK_TRANSFER";
  createCheckout(input: { paymentId: string; amount: number; description: string }): Promise<CheckoutResult>;
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/services/payments/provider.interface.ts"

$path = "src/types/index.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
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
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/types/index.ts"

$path = "tsconfig.json"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": [
      "dom",
      "dom.iterable",
      "esnext"
    ],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "react-jsx",
    "incremental": true,
    "plugins": [
      {
        "name": "next"
      }
    ],
    "paths": {
      "@/*": [
        "./src/*"
      ]
    }
  },
  "include": [
    "next-env.d.ts",
    "**/*.ts",
    "**/*.tsx",
    ".next/types/**/*.ts",
    ".next/dev/types/**/*.ts"
  ],
  "exclude": [
    "node_modules",
    "**/__tests__/**"
  ]
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote tsconfig.json"

$path = ".github/workflows/ci.yml"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    # These are dummy values only for CI's typecheck/build/test steps — no
    # real database or secret is used or needed here. validateEnv() (see
    # src/lib/env.ts) requires these to be present just to import the Prisma
    # module; nothing in this job actually connects to a database.
    env:
      DATABASE_URL: "postgresql://ci:ci@localhost:5432/ci"
      NEXTAUTH_SECRET: "ci-only-value-not-used-in-production"
      NEXTAUTH_URL: "http://localhost:3000"

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Node
        uses: actions/setup-node@v4
        with:
          node-version: "20.9"
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Generate Prisma client
        run: npx prisma generate

      - name: Type-check
        run: npx tsc --noEmit -p tsconfig.json

      - name: Lint
        run: npm run lint

      - name: Run unit tests
        run: npm test -- --ci

      - name: Production build
        run: npm run build

      - name: Audit dependencies (non-blocking)
        run: npm audit --audit-level=critical || true
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote .github/workflows/ci.yml"

$path = "eslint.config.mjs"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import nextPlugin from "eslint-config-next";

// eslint-config-next 16+ exports a native flat config (an array of config
// objects), so no FlatCompat/legacy-shim layer is needed here — this repo
// never had an .eslintrc at all before this, so there's no legacy config to
// migrate, just a fresh flat config to add.
export default [
  ...nextPlugin,
  {
    ignores: [
      "node_modules/**",
      ".next/**",
      "src/generated/**",
      "src/services/__tests__/**",
      "src/lib/__tests__/**",
      "src/lib/__mocks__/**",
      "coverage/**",
    ],
  },
];
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote eslint.config.mjs"

$path = "jest.config.js"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
/** @type {import('jest').Config} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/src"],
  testMatch: ["**/__tests__/**/*.test.ts"],
  moduleNameMapper: {
    "^@/lib/prisma$": "<rootDir>/src/lib/__mocks__/prisma.ts",
    "^@/(.*)$": "<rootDir>/src/$1",
  },
  clearMocks: true,
  globals: {
    "ts-jest": {
      tsconfig: "<rootDir>/tsconfig.test.json",
    },
  },
};
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote jest.config.js"

$path = "tsconfig.test.json"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "types": ["jest", "node"]
  },
  "include": ["src/**/__tests__/**/*.ts"],
  "exclude": ["node_modules"]
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote tsconfig.test.json"

$path = "src/lib/env.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
// Validated once, at module load, rather than deep inside whichever request
// happens to first need a given var - a missing DATABASE_URL should fail the
// deployment immediately and clearly, not as an opaque Prisma connection
// error on someone's first click in production.
const REQUIRED = ["DATABASE_URL", "NEXTAUTH_SECRET", "NEXTAUTH_URL"] as const;

// Each has a documented, working fallback (see .env.example) - missing these
// only degrades a specific feature, so we warn rather than fail the boot.
const OPTIONAL_WITH_FALLBACK: Record<string, string> = {
  BLOB_READ_WRITE_TOKEN: "document uploads will return a 503 instead of storing the file",
  ANTHROPIC_API_KEY: "the chat widget will use its rule-based FAQ fallback instead of real AI answers",
  PAYMONGO_SECRET_KEY: "GCash/Maya checkout will use the in-app sandbox screen instead of a real gateway",
  PAYPAL_CLIENT_ID: "PayPal checkout will use the in-app sandbox screen instead of a real gateway",
  CRON_SECRET: "the scheduled renewal-reminder job will be unauthenticated if triggered manually",
};

let validated = false;

export function validateEnv() {
  if (validated) return; // only needs to re-run once it has actually succeeded once

  const missing = REQUIRED.filter((key) => !process.env[key]);
  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variable(s): ${missing.join(", ")}. ` +
        `Set these in your environment (see .env.example) before starting the app.`
    );
  }

  for (const [key, consequence] of Object.entries(OPTIONAL_WITH_FALLBACK)) {
    if (!process.env[key]) {
      console.warn(`[env] ${key} is not set - ${consequence}.`);
    }
  }

  validated = true;
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/lib/env.ts"

$path = "src/lib/adminNav.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
export interface NavItem {
  icon: string;
  label: string;
  href: string;
}

const ADMIN_ONLY_LABELS = new Set(["Identity Manager", "Security Logs", "API Endpoints"]);

const FULL_NAV: NavItem[] = [
  { icon: "fa-chart-line", label: "Analytics Engine", href: "/admin" },
  { icon: "fa-clipboard-check", label: "Verification Queue", href: "/admin/queue" },
  { icon: "fa-users", label: "Identity Manager", href: "/admin/users" },
  { icon: "fa-shield-halved", label: "Security Logs", href: "/admin/security-logs" },
  { icon: "fa-code-branch", label: "API Endpoints", href: "/admin/api-endpoints" },
];

// The Analytics Engine and Verification Queue are the single shared
// dashboard used by both ADMIN and PROCESSOR — same URL space, same visual
// shell, not two separate portals. Account provisioning, the security audit
// trail, and internal API docs stay ADMIN-only (also enforced server-side
// in middleware.ts and each route), so PROCESSOR simply doesn't see those
// links rather than hitting a dead end after clicking them.
export function getAdminNav(role?: string): NavItem[] {
  if (role === "ADMIN") return FULL_NAV;
  return FULL_NAV.filter((item) => !ADMIN_ONLY_LABELS.has(item.label));
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/lib/adminNav.ts"

$path = "src/lib/claimantNav.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
export interface NavItem {
  icon: string;
  label: string;
  href: string;
}

export const CLAIMANT_NAV: NavItem[] = [
  { icon: "fa-house", label: "Dashboard", href: "/claimant" },
  { icon: "fa-file-invoice", label: "My Claims", href: "/claimant/claims" },
  { icon: "fa-gear", label: "Settings", href: "/claimant/settings" },
];
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/lib/claimantNav.ts"

$path = "src/lib/__mocks__/prisma.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
// Referenced only via jest.config.js's moduleNameMapper, never imported by
// application code. Keeps unit tests from ever instantiating a real
// PrismaClient — every service under test is constructed with fake
// repositories, so the real DB client should never be touched here.
export const prisma = new Proxy(
  {},
  {
    get() {
      throw new Error(
        "The real Prisma client was reached during a unit test. Inject a fake repository instead of relying on the default PrismaClient-backed one."
      );
    },
  }
);
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/lib/__mocks__/prisma.ts"

$path = "src/lib/__tests__/env.test.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
describe("validateEnv", () => {
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    jest.resetModules();
    process.env = { ...ORIGINAL_ENV };
  });

  afterAll(() => {
    process.env = ORIGINAL_ENV;
  });

  it("throws a clear error listing every missing required variable", () => {
    delete process.env.DATABASE_URL;
    delete process.env.NEXTAUTH_SECRET;
    process.env.NEXTAUTH_URL = "http://localhost:3000";

    const { validateEnv } = require("@/lib/env");
    expect(() => validateEnv()).toThrow(/DATABASE_URL/);
    expect(() => validateEnv()).toThrow(/NEXTAUTH_SECRET/);
  });

  it("does not throw when all required variables are present", () => {
    process.env.DATABASE_URL = "postgresql://x";
    process.env.NEXTAUTH_SECRET = "secret";
    process.env.NEXTAUTH_URL = "http://localhost:3000";

    const { validateEnv } = require("@/lib/env");
    expect(() => validateEnv()).not.toThrow();
  });

  it("warns (but does not throw) for missing optional variables", () => {
    process.env.DATABASE_URL = "postgresql://x";
    process.env.NEXTAUTH_SECRET = "secret";
    process.env.NEXTAUTH_URL = "http://localhost:3000";
    delete process.env.PAYMONGO_SECRET_KEY;
    const warnSpy = jest.spyOn(console, "warn").mockImplementation(() => {});

    const { validateEnv } = require("@/lib/env");
    validateEnv();
    expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining("PAYMONGO_SECRET_KEY"));
    warnSpy.mockRestore();
  });
});
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/lib/__tests__/env.test.ts"

$path = "src/repositories/audit-log.repository.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { IAuditLogRepository } from "./interfaces";

export class PrismaAuditLogRepository implements IAuditLogRepository {
  constructor(private readonly db: PrismaClient = prisma) {}

  async log(data: { actorId?: string; actorName: string; actorRole: string; action: string; detail?: string }) {
    await this.db.auditLog.create({ data });
  }

  list(limit = 100) {
    return this.db.auditLog.findMany({ orderBy: { createdAt: "desc" }, take: limit });
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/repositories/audit-log.repository.ts"

$path = "src/repositories/payout-preference.repository.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { PrismaClient, PaymentProvider } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { IPayoutPreferenceRepository } from "./interfaces";

export class PrismaPayoutPreferenceRepository implements IPayoutPreferenceRepository {
  constructor(private readonly db: PrismaClient = prisma) {}

  findByUserId(userId: string) {
    return this.db.payoutPreference.findUnique({ where: { userId } });
  }

  upsert(userId: string, data: { provider: PaymentProvider; bankName?: string | null; accountName?: string | null; accountNumber?: string | null }) {
    return this.db.payoutPreference.upsert({
      where: { userId },
      update: data,
      create: { userId, ...data },
    });
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/repositories/payout-preference.repository.ts"

$path = "src/services/audit.service.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { IAuditLogRepository } from "@/repositories/interfaces";
import { PrismaAuditLogRepository } from "@/repositories/audit-log.repository";

// Backs the Admin → Security Logs module. Called from the services that
// perform security-relevant actions (user provisioning, claim decisions,
// payouts) rather than from routes directly, so the log stays consistent
// regardless of which route triggered the action.
export class AuditService {
  constructor(private readonly logs: IAuditLogRepository = new PrismaAuditLogRepository()) {}

  async log(entry: { actorId?: string; actorName: string; actorRole: string; action: string; detail?: string }) {
    try {
      await this.logs.log(entry);
    } catch (err) {
      // Never let audit logging break the action it's describing.
      console.error("Failed to write audit log:", err);
    }
  }

  list(limit?: number) {
    return this.logs.list(limit);
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/services/audit.service.ts"

$path = "src/services/claim-validation.service.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { ClaimWithRelations } from "@/repositories/interfaces";

export type IssueSeverity = "blocking" | "warning";

export interface ClaimIssue {
  code: string;
  severity: IssueSeverity;
  message: string;
}

// Runs entirely against data already loaded with the claim (documents, LOA,
// payments) — nothing here is cached or persisted, so it can never go stale:
// every call reflects the claim's current state at the moment it's asked for.
// "blocking" issues are checked by ClaimService before a claim is allowed to
// move to APPROVED; "warning" issues are surfaced to staff but don't block.
export class ClaimValidationService {
  private static readonly STALE_AFTER_DAYS = 14;

  evaluate(claim: ClaimWithRelations): ClaimIssue[] {
    const issues: ClaimIssue[] = [];

    // --- Missing information -------------------------------------------------
    if (claim.documents.length === 0) {
      issues.push({
        code: "NO_DOCUMENTS",
        severity: "blocking",
        message: "No supporting documents have been uploaded for this claim.",
      });
    } else if (!claim.documents.some((d) => d.mimeType.startsWith("image/"))) {
      issues.push({
        code: "NO_PHOTO_EVIDENCE",
        severity: "warning",
        message: "No photographic evidence has been uploaded - only non-image documents are on file.",
      });
    }

    if (!Number.isFinite(Number(claim.estimate)) || Number(claim.estimate) <= 0) {
      issues.push({
        code: "MISSING_ESTIMATE",
        severity: "blocking",
        message: "The claim has no valid estimated amount.",
      });
    }

    if ((claim.status === "APPROVED" || claim.status === "VERIFIED") && !claim.processorId) {
      issues.push({
        code: "NO_PROCESSOR_OF_RECORD",
        severity: "blocking",
        message: "The claim has moved past PENDING but has no processor of record assigned.",
      });
    }

    // --- Inconsistent information ---------------------------------------------
    const corruptDocs = claim.documents.filter((d) => d.sizeBytes <= 0 || !d.fileUrl);
    if (corruptDocs.length > 0) {
      issues.push({
        code: "CORRUPT_DOCUMENT",
        severity: "blocking",
        message: `${corruptDocs.length} uploaded document(s) appear empty or corrupted (0 bytes or missing file reference).`,
      });
    }

    const paidTotal = claim.payments.filter((p) => p.status === "PAID").reduce((sum, p) => sum + Number(p.amount), 0);
    if (paidTotal > Number(claim.estimate)) {
      issues.push({
        code: "PAYOUT_EXCEEDS_ESTIMATE",
        severity: "blocking",
        message: `Total paid out (PHP ${paidTotal.toLocaleString()}) exceeds the claim's estimated amount (PHP ${Number(claim.estimate).toLocaleString()}).`,
      });
    }

    const pendingProviders = new Set(claim.payments.filter((p) => p.status === "PENDING").map((p) => p.provider));
    if (pendingProviders.size > 1) {
      issues.push({
        code: "MULTIPLE_PENDING_PAYOUTS",
        severity: "warning",
        message: `Payout requests are pending across ${pendingProviders.size} different methods (${[...pendingProviders].join(", ")}) - confirm only one is actually completed to avoid a double payout.`,
      });
    }

    if (claim.status === "APPROVED" && !claim.loa) {
      issues.push({
        code: "APPROVED_WITHOUT_LOA",
        severity: "warning",
        message: "The claim is approved but no Letter of Authorization has been generated yet.",
      });
    }

    // --- Staleness (prevents stale/outdated info from being acted on) --------
    if (claim.status === "PENDING" || claim.status === "VERIFIED") {
      const ageDays = (Date.now() - new Date(claim.updatedAt).getTime()) / (1000 * 60 * 60 * 24);
      if (ageDays > ClaimValidationService.STALE_AFTER_DAYS) {
        issues.push({
          code: "STALE_CLAIM",
          severity: "warning",
          message: `This claim has had no status update in ${Math.floor(ageDays)} days - verify the information on file is still current before acting on it.`,
        });
      }
    }

    return issues;
  }

  hasBlockingIssues(claim: ClaimWithRelations): boolean {
    return this.evaluate(claim).some((i) => i.severity === "blocking");
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/services/claim-validation.service.ts"

$path = "src/services/payout-preference.service.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { PaymentProvider } from "@prisma/client";
import { IPayoutPreferenceRepository } from "@/repositories/interfaces";
import { PrismaPayoutPreferenceRepository } from "@/repositories/payout-preference.repository";
import { ServiceError } from "./claim.service";

export interface PayoutPreferenceInput {
  provider: PaymentProvider;
  bankName?: string;
  accountName?: string;
  accountNumber?: string;
}

export class PayoutPreferenceService {
  constructor(private readonly preferences: IPayoutPreferenceRepository = new PrismaPayoutPreferenceRepository()) {}

  get(userId: string) {
    return this.preferences.findByUserId(userId);
  }

  async save(userId: string, input: PayoutPreferenceInput) {
    if (input.provider === "BANK_TRANSFER") {
      if (!input.bankName?.trim() || !input.accountName?.trim() || !input.accountNumber?.trim()) {
        throw new ServiceError("Bank name, account name, and account number are required for bank transfer.", 400);
      }
    }

    return this.preferences.upsert(userId, {
      provider: input.provider,
      // Explicit null (not undefined) when switching away from bank
      // transfer — Prisma treats `undefined` as "leave this field
      // untouched," so using it here would leave stale bank details
      // attached to a preference that's since been switched to
      // GCash/Maya/PayPal.
      bankName: input.provider === "BANK_TRANSFER" ? input.bankName!.trim() : null,
      accountName: input.provider === "BANK_TRANSFER" ? input.accountName!.trim() : null,
      accountNumber: input.provider === "BANK_TRANSFER" ? input.accountNumber!.trim() : null,
    });
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/services/payout-preference.service.ts"

$path = "src/services/payments/bank-transfer.provider.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { IPaymentProvider, CheckoutResult } from "./provider.interface";

// Unlike GCash/Maya/PayPal, a bank transfer has no gateway to hand off to —
// the claimant deposits to the bank details they submitted, and staff verify
// the deposit manually before marking the payment PAID. There's no live vs.
// mock split here (no external API to call either way); this always lands
// the claimant on a confirmation screen explaining the payout is pending
// manual verification.
export class BankTransferProvider implements IPaymentProvider {
  readonly name = "BANK_TRANSFER" as const;

  async createCheckout(input: { paymentId: string; amount: number; description: string }): Promise<CheckoutResult> {
    const appUrl = process.env.NEXTAUTH_URL ?? "http://localhost:3000";
    return {
      redirectUrl: `${appUrl}/pay/${input.paymentId}?provider=BANK_TRANSFER`,
      providerRef: `MANUAL-${input.paymentId}`,
    };
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/services/payments/bank-transfer.provider.ts"

$path = "src/services/__tests__/claim-validation.service.test.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { ClaimValidationService } from "@/services/claim-validation.service";
import { ClaimWithRelations } from "@/repositories/interfaces";

function baseClaim(overrides: Partial<ClaimWithRelations> = {}): ClaimWithRelations {
  return {
    id: "claim_1",
    referenceId: "CLM-2026-X001",
    category: "HOMEOWNERS",
    estimate: 5000 as any,
    status: "PENDING",
    userId: "user_1",
    processorId: null,
    createdAt: new Date(),
    updatedAt: new Date(),
    user: { id: "user_1", name: "Jane Dela Cruz", email: "jane@example.com" },
    documents: [{ id: "doc_1", claimId: "claim_1", fileName: "photo.jpg", fileUrl: "https://x/photo.jpg", mimeType: "image/jpeg", sizeBytes: 1024, uploadedAt: new Date() } as any],
    loa: null,
    payments: [],
    ...overrides,
  } as ClaimWithRelations;
}

describe("ClaimValidationService", () => {
  const service = new ClaimValidationService();

  it("flags a claim with no documents as blocking", () => {
    const claim = baseClaim({ documents: [] });
    const issues = service.evaluate(claim);
    expect(issues.map((i) => i.code)).toContain("NO_DOCUMENTS");
    expect(service.hasBlockingIssues(claim)).toBe(true);
  });

  it("warns (does not block) when documents exist but none are photos", () => {
    const claim = baseClaim({
      documents: [{ id: "doc_1", claimId: "claim_1", fileName: "notes.pdf", fileUrl: "https://x/notes.pdf", mimeType: "application/pdf", sizeBytes: 500, uploadedAt: new Date() } as any],
    });
    const issues = service.evaluate(claim);
    const issue = issues.find((i) => i.code === "NO_PHOTO_EVIDENCE");
    expect(issue?.severity).toBe("warning");
    expect(service.hasBlockingIssues(claim)).toBe(false);
  });

  it("flags a zero or missing estimate as blocking", () => {
    const claim = baseClaim({ estimate: 0 as any });
    expect(service.evaluate(claim).map((i) => i.code)).toContain("MISSING_ESTIMATE");
  });

  it("flags a VERIFIED/APPROVED claim with no processor of record as blocking", () => {
    const claim = baseClaim({ status: "VERIFIED", processorId: null });
    expect(service.evaluate(claim).map((i) => i.code)).toContain("NO_PROCESSOR_OF_RECORD");
  });

  it("flags corrupted (0-byte) documents as blocking", () => {
    const claim = baseClaim({
      documents: [{ id: "doc_1", claimId: "claim_1", fileName: "broken.jpg", fileUrl: "https://x/broken.jpg", mimeType: "image/jpeg", sizeBytes: 0, uploadedAt: new Date() } as any],
    });
    expect(service.evaluate(claim).map((i) => i.code)).toContain("CORRUPT_DOCUMENT");
  });

  it("flags when total paid exceeds the estimate", () => {
    const claim = baseClaim({
      estimate: 1000 as any,
      payments: [{ id: "p1", provider: "GCASH", amount: 1500 as any, status: "PAID" } as any],
    });
    expect(service.evaluate(claim).map((i) => i.code)).toContain("PAYOUT_EXCEEDS_ESTIMATE");
  });

  it("warns when multiple providers have pending payouts simultaneously", () => {
    const claim = baseClaim({
      payments: [
        { id: "p1", provider: "GCASH", amount: 500 as any, status: "PENDING" } as any,
        { id: "p2", provider: "MAYA", amount: 500 as any, status: "PENDING" } as any,
      ],
    });
    expect(service.evaluate(claim).map((i) => i.code)).toContain("MULTIPLE_PENDING_PAYOUTS");
  });

  it("warns when APPROVED without an LOA", () => {
    const claim = baseClaim({ status: "APPROVED", processorId: "staff_1", loa: null });
    expect(service.evaluate(claim).map((i) => i.code)).toContain("APPROVED_WITHOUT_LOA");
  });

  it("warns on a stale PENDING/VERIFIED claim (no update in 14+ days)", () => {
    const old = new Date();
    old.setDate(old.getDate() - 20);
    const claim = baseClaim({ status: "PENDING", updatedAt: old });
    expect(service.evaluate(claim).map((i) => i.code)).toContain("STALE_CLAIM");
  });

  it("returns no issues for a clean, complete PENDING claim", () => {
    const claim = baseClaim();
    expect(service.evaluate(claim)).toHaveLength(0);
    expect(service.hasBlockingIssues(claim)).toBe(false);
  });
});
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/services/__tests__/claim-validation.service.test.ts"

$path = "src/services/__tests__/claim.service.test.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
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
  return { claimRepo, notifications, audit };
}

describe("ClaimService.transitionStatus", () => {
  it("allows PENDING -> VERIFIED", async () => {
    const claim = makeClaim({ status: "PENDING" });
    const { claimRepo, notifications, audit } = makeMocks(claim);
    const service = new ClaimService(claimRepo as any, notifications, audit, new ClaimValidationService());

    const result = await service.transitionStatus("claim_1", "VERIFIED", "staff_1");
    expect(result.status).toBe("VERIFIED");
    expect(claimRepo.updateStatus).toHaveBeenCalledWith("claim_1", "VERIFIED", "staff_1");
  });

  it("rejects an invalid transition (PENDING -> APPROVED, skipping VERIFIED)", async () => {
    const claim = makeClaim({ status: "PENDING" });
    const { claimRepo, notifications, audit } = makeMocks(claim);
    const service = new ClaimService(claimRepo as any, notifications, audit, new ClaimValidationService());

    await expect(service.transitionStatus("claim_1", "APPROVED", "staff_1")).rejects.toThrow(ServiceError);
    expect(claimRepo.updateStatus).not.toHaveBeenCalled();
  });

  it("blocks VERIFIED -> APPROVED when the claim has no documents", async () => {
    const claim = makeClaim({ status: "VERIFIED", processorId: "staff_1", documents: [] });
    const { claimRepo, notifications, audit } = makeMocks(claim);
    const service = new ClaimService(claimRepo as any, notifications, audit, new ClaimValidationService());

    await expect(service.transitionStatus("claim_1", "APPROVED", "staff_1")).rejects.toThrow(/unresolved issues/i);
    expect(claimRepo.updateStatus).not.toHaveBeenCalled();
  });

  it("allows VERIFIED -> APPROVED when the claim is complete", async () => {
    const claim = makeClaim({ status: "VERIFIED", processorId: "staff_1" });
    const { claimRepo, notifications, audit } = makeMocks(claim);
    const service = new ClaimService(claimRepo as any, notifications, audit, new ClaimValidationService());

    const result = await service.transitionStatus("claim_1", "APPROVED", "staff_1", { name: "Staff", role: "PROCESSOR" });
    expect(result.status).toBe("APPROVED");
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: "CLAIM_STATUS_CHANGED" }));
  });

  it("still updates status even if the notification write fails", async () => {
    const claim = makeClaim({ status: "PENDING" });
    const { claimRepo, notifications, audit } = makeMocks(claim);
    notifications.notifyStatusChange.mockRejectedValue(new Error("db down"));
    const service = new ClaimService(claimRepo as any, notifications, audit, new ClaimValidationService());

    const result = await service.transitionStatus("claim_1", "VERIFIED", "staff_1");
    expect(result.status).toBe("VERIFIED");
  });

  it("throws 404 for a claim that doesn't exist", async () => {
    const { claimRepo, notifications, audit } = makeMocks(null);
    claimRepo.findById.mockResolvedValue(null);
    const service = new ClaimService(claimRepo as any, notifications, audit, new ClaimValidationService());

    await expect(service.transitionStatus("nope", "VERIFIED", "staff_1")).rejects.toMatchObject({ statusCode: 404 });
  });
});

describe("ClaimService.createClaim", () => {
  it("rejects a non-positive estimate", async () => {
    const { claimRepo, notifications, audit } = makeMocks(null);
    const service = new ClaimService(claimRepo as any, notifications, audit, new ClaimValidationService());

    await expect(service.createClaim("user_1", { category: "HOMEOWNERS" as any, estimate: 0 })).rejects.toThrow(ServiceError);
    await expect(service.createClaim("user_1", { category: "HOMEOWNERS" as any, estimate: NaN })).rejects.toThrow(ServiceError);
  });
});
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/services/__tests__/claim.service.test.ts"

$path = "src/services/__tests__/payment.service.test.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { PaymentService } from "@/services/payment.service";
import { ServiceError } from "@/services/claim.service";
import { getPaymentProvider } from "@/services/payments/provider.factory";

jest.mock("@/services/payments/provider.factory", () => ({
  getPaymentProvider: jest.fn(() => ({
    createCheckout: jest.fn().mockResolvedValue({ redirectUrl: "https://pay.example/checkout", providerRef: "ref_1" }),
  })),
}));

function makeMocks(claim: any, payment?: any) {
  const paymentRepo = {
    create: jest.fn().mockResolvedValue(payment ?? { id: "pay_1", claimId: claim?.id, provider: "GCASH", amount: 500, status: "PENDING" }),
    findById: jest.fn().mockResolvedValue(payment),
    updateStatus: jest.fn().mockImplementation((id, status) => Promise.resolve({ ...payment, status })),
    listForClaim: jest.fn(),
  };
  const claimRepo = { findById: jest.fn().mockResolvedValue(claim) } as any;
  const notifications = { notifyPayment: jest.fn().mockResolvedValue(undefined) } as any;
  const audit = { log: jest.fn().mockResolvedValue(undefined) } as any;
  return { paymentRepo, claimRepo, notifications, audit };
}

function makeApprovedClaim(overrides: any = {}) {
  return { id: "claim_1", referenceId: "CLM-2026-X001", status: "APPROVED", estimate: 5000, payments: [], ...overrides };
}

describe("PaymentService.startCheckout", () => {
  it("rejects a claim that isn't APPROVED", async () => {
    const claim = makeApprovedClaim({ status: "PENDING" });
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await expect(service.startCheckout("claim_1", "GCASH", 500)).rejects.toThrow(ServiceError);
  });

  it("rejects a non-positive amount", async () => {
    const claim = makeApprovedClaim();
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await expect(service.startCheckout("claim_1", "GCASH", 0)).rejects.toThrow(ServiceError);
  });

  it("requires bank details for BANK_TRANSFER", async () => {
    const claim = makeApprovedClaim();
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await expect(service.startCheckout("claim_1", "BANK_TRANSFER", 500)).rejects.toThrow(/bank name/i);
  });

  it("succeeds for BANK_TRANSFER with complete bank details", async () => {
    const claim = makeApprovedClaim();
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    const result = await service.startCheckout("claim_1", "BANK_TRANSFER", 500, {
      bankName: "BDO Unibank",
      accountName: "Jane Dela Cruz",
      accountNumber: "1234567890",
    });
    expect(result.redirectUrl).toBe("https://pay.example/checkout");
    expect(paymentRepo.create).toHaveBeenCalledWith(
      expect.objectContaining({ bankName: "BDO Unibank", accountName: "Jane Dela Cruz", accountNumber: "1234567890" })
    );
  });
});

describe("PaymentService.getOrCreateCheckoutForClaim", () => {
  it("reuses an existing PENDING payment of the same provider instead of creating a new one", async () => {
    const existing = { id: "pay_existing", provider: "GCASH", status: "PENDING", amount: 500 };
    const claim = makeApprovedClaim({ payments: [existing] });
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    const result = await service.getOrCreateCheckoutForClaim("claim_1", "GCASH", 500);
    expect(paymentRepo.create).not.toHaveBeenCalled();
    expect(result.paymentId).toBe("pay_existing");
  });

  it("creates a new payment when none is pending for that provider", async () => {
    const claim = makeApprovedClaim({ payments: [] });
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await service.getOrCreateCheckoutForClaim("claim_1", "GCASH", 500);
    expect(paymentRepo.create).toHaveBeenCalledWith(expect.objectContaining({ claimId: "claim_1", provider: "GCASH" }));
  });

  it("works for a non-GCash provider too (e.g. the LOA locked in Maya)", async () => {
    const claim = makeApprovedClaim({ payments: [] });
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await service.getOrCreateCheckoutForClaim("claim_1", "MAYA", 500);
    expect(paymentRepo.create).toHaveBeenCalledWith(expect.objectContaining({ claimId: "claim_1", provider: "MAYA" }));
  });

  it("passes bank details through when creating a BANK_TRANSFER checkout", async () => {
    const claim = makeApprovedClaim({ payments: [] });
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await service.getOrCreateCheckoutForClaim("claim_1", "BANK_TRANSFER", 500, {
      bankName: "BDO Unibank",
      accountName: "Jane Dela Cruz",
      accountNumber: "1234567890",
    });
    expect(paymentRepo.create).toHaveBeenCalledWith(
      expect.objectContaining({ claimId: "claim_1", provider: "BANK_TRANSFER", bankName: "BDO Unibank" })
    );
  });
});

describe("PaymentService.confirmPayment", () => {
  it("lets a claimant self-confirm a GCash payment (stands in for a gateway webhook)", async () => {
    const payment = { id: "pay_1", provider: "GCASH", status: "PENDING", claimId: "claim_1", claim: { userId: "user_1", referenceId: "CLM-1" } };
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(null, payment);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    const result = await service.confirmPayment("pay_1", true, { role: "CLIENT" });
    expect(result.status).toBe("PAID");
    expect(notifications.notifyPayment).toHaveBeenCalled();
  });

  it("blocks a non-staff actor from confirming a BANK_TRANSFER payment", async () => {
    const payment = { id: "pay_1", provider: "BANK_TRANSFER", status: "PENDING", claimId: "claim_1", claim: { userId: "user_1", referenceId: "CLM-1" } };
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(null, payment);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await expect(service.confirmPayment("pay_1", true, { role: "CLIENT" })).rejects.toMatchObject({ statusCode: 403 });
    expect(paymentRepo.updateStatus).not.toHaveBeenCalled();
  });

  it("allows a PROCESSOR to confirm a BANK_TRANSFER payment", async () => {
    const payment = { id: "pay_1", provider: "BANK_TRANSFER", status: "PENDING", claimId: "claim_1", claim: { userId: "user_1", referenceId: "CLM-1" } };
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(null, payment);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    const result = await service.confirmPayment("pay_1", true, { role: "PROCESSOR" });
    expect(result.status).toBe("PAID");
  });

  it("is idempotent — confirming an already-PAID payment again doesn't re-notify", async () => {
    const payment = { id: "pay_1", provider: "GCASH", status: "PAID", claimId: "claim_1", claim: { userId: "user_1", referenceId: "CLM-1" } };
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(null, payment);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    const result = await service.confirmPayment("pay_1", true, { role: "CLIENT" });
    expect(result.status).toBe("PAID");
    expect(paymentRepo.updateStatus).not.toHaveBeenCalled();
    expect(notifications.notifyPayment).not.toHaveBeenCalled();
  });

  it("throws 404 for a payment that doesn't exist", async () => {
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(null, null);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await expect(service.confirmPayment("nope", true)).rejects.toMatchObject({ statusCode: 404 });
  });
});

describe("PaymentService gateway failure handling", () => {
  it("converts a raw gateway error (e.g. an invalid PayMongo API key) into a clean ServiceError instead of an unhandled crash", async () => {
    (getPaymentProvider as jest.Mock).mockReturnValue({
      createCheckout: jest.fn().mockRejectedValue(new Error("PayMongo checkout failed: 401 Unauthorized")),
    });

    const claim = makeApprovedClaim();
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await expect(service.getOrCreateCheckoutForClaim("claim_1", "GCASH", 500)).rejects.toMatchObject({
      statusCode: 502,
    });
  });

  it("same protection applies to the manual startCheckout flow", async () => {
    (getPaymentProvider as jest.Mock).mockReturnValueOnce({
      createCheckout: jest.fn().mockRejectedValue(new Error("network error")),
    });

    const claim = makeApprovedClaim();
    const { paymentRepo, claimRepo, notifications, audit } = makeMocks(claim);
    const service = new PaymentService(paymentRepo as any, claimRepo, notifications, audit);

    await expect(service.startCheckout("claim_1", "MAYA", 500)).rejects.toMatchObject({ statusCode: 502 });
  });
});
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/services/__tests__/payment.service.test.ts"

$path = "src/services/__tests__/payout-preference.service.test.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { PayoutPreferenceService } from "@/services/payout-preference.service";
import { ServiceError } from "@/services/claim.service";

function makeMocks(existing: any = null) {
  const repo = {
    findByUserId: jest.fn().mockResolvedValue(existing),
    upsert: jest.fn().mockImplementation((userId, data) => Promise.resolve({ id: "pref_1", userId, ...data })),
  };
  return repo;
}

describe("PayoutPreferenceService.save", () => {
  it("saves a non-bank provider with bank fields nulled out", async () => {
    const repo = makeMocks();
    const service = new PayoutPreferenceService(repo as any);

    const result = await service.save("user_1", { provider: "GCASH" });
    expect(repo.upsert).toHaveBeenCalledWith("user_1", {
      provider: "GCASH",
      bankName: null,
      accountName: null,
      accountNumber: null,
    });
    expect(result.provider).toBe("GCASH");
  });

  it("rejects BANK_TRANSFER with missing bank details", async () => {
    const repo = makeMocks();
    const service = new PayoutPreferenceService(repo as any);

    await expect(service.save("user_1", { provider: "BANK_TRANSFER" })).rejects.toThrow(ServiceError);
    await expect(
      service.save("user_1", { provider: "BANK_TRANSFER", bankName: "BDO Unibank" })
    ).rejects.toThrow(/account name/i);
    expect(repo.upsert).not.toHaveBeenCalled();
  });

  it("saves BANK_TRANSFER with trimmed bank details", async () => {
    const repo = makeMocks();
    const service = new PayoutPreferenceService(repo as any);

    await service.save("user_1", {
      provider: "BANK_TRANSFER",
      bankName: "  BDO Unibank  ",
      accountName: "  Jane Dela Cruz  ",
      accountNumber: "  1234567890  ",
    });

    expect(repo.upsert).toHaveBeenCalledWith("user_1", {
      provider: "BANK_TRANSFER",
      bankName: "BDO Unibank",
      accountName: "Jane Dela Cruz",
      accountNumber: "1234567890",
    });
  });

  it("clears stale bank details when switching away from BANK_TRANSFER", async () => {
    const existing = { provider: "BANK_TRANSFER", bankName: "BDO Unibank", accountName: "Jane", accountNumber: "123" };
    const repo = makeMocks(existing);
    const service = new PayoutPreferenceService(repo as any);

    await service.save("user_1", { provider: "PAYPAL" });

    expect(repo.upsert).toHaveBeenCalledWith("user_1", {
      provider: "PAYPAL",
      bankName: null,
      accountName: null,
      accountNumber: null,
    });
  });
});

describe("PayoutPreferenceService.get", () => {
  it("returns null when the user has no saved preference", async () => {
    const repo = makeMocks(null);
    const service = new PayoutPreferenceService(repo as any);

    const result = await service.get("user_1");
    expect(result).toBeNull();
  });

  it("returns the existing preference when one is saved", async () => {
    const existing = { provider: "GCASH" };
    const repo = makeMocks(existing);
    const service = new PayoutPreferenceService(repo as any);

    const result = await service.get("user_1");
    expect(result).toEqual(existing);
  });
});
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/services/__tests__/payout-preference.service.test.ts"

$path = "src/services/__tests__/loa.service.test.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { LoaService } from "@/services/loa.service";
import { ServiceError } from "@/services/claim.service";

function makeApprovedClaim(overrides: any = {}) {
  return {
    id: "claim_1",
    referenceId: "CLM-2026-X001",
    category: "HOMEOWNERS",
    status: "APPROVED",
    userId: "user_1",
    user: { name: "Jane Dela Cruz" },
    loa: null,
    ...overrides,
  };
}

function makeMocks(claim: any, preference: any = null) {
  const loaRepo = {
    createForClaim: jest.fn().mockImplementation((claimId, content, generatedById, provider) =>
      Promise.resolve({ id: "loa_1", claimId, content, generatedById, provider, generatedAt: new Date() })
    ),
    count: jest.fn(),
  };
  const claimRepo = { findById: jest.fn().mockResolvedValue(claim) };
  const payoutPreferences = { get: jest.fn().mockResolvedValue(preference) };
  return { loaRepo, claimRepo, payoutPreferences };
}

describe("LoaService.generateForClaim", () => {
  it("defaults to GCASH and names it in the letter text when the claimant has no saved preference", async () => {
    const claim = makeApprovedClaim();
    const { loaRepo, claimRepo, payoutPreferences } = makeMocks(claim, null);
    const service = new LoaService(loaRepo as any, claimRepo as any, payoutPreferences as any);

    const loa = await service.generateForClaim("claim_1", "staff_1");
    expect(loa.provider).toBe("GCASH");
    expect(loa.content).toMatch(/via GCash/);
  });

  it("locks in the claimant's saved preference (e.g. Maya) instead of always defaulting to GCash", async () => {
    const claim = makeApprovedClaim();
    const { loaRepo, claimRepo, payoutPreferences } = makeMocks(claim, { provider: "MAYA" });
    const service = new LoaService(loaRepo as any, claimRepo as any, payoutPreferences as any);

    const loa = await service.generateForClaim("claim_1", "staff_1");
    expect(loa.provider).toBe("MAYA");
    expect(loa.content).toMatch(/via Maya/);
    expect(loaRepo.createForClaim).toHaveBeenCalledWith(expect.anything(), expect.anything(), expect.anything(), "MAYA");
  });

  it("locks in PayPal too, not just GCash/Maya", async () => {
    const claim = makeApprovedClaim();
    const { loaRepo, claimRepo, payoutPreferences } = makeMocks(claim, { provider: "PAYPAL" });
    const service = new LoaService(loaRepo as any, claimRepo as any, payoutPreferences as any);

    const loa = await service.generateForClaim("claim_1", "staff_1");
    expect(loa.provider).toBe("PAYPAL");
    expect(loa.content).toMatch(/via PayPal/);
  });

  it("returns the already-generated LOA as-is on a second call, without re-deriving the provider from a possibly-since-changed preference", async () => {
    const existingLoa = { id: "loa_existing", content: "already generated, names Maya", provider: "MAYA" };
    const claim = makeApprovedClaim({ loa: existingLoa });
    // Preference has since changed to GCash — the already-generated LOA must NOT
    // switch to GCash just because it's re-fetched.
    const { loaRepo, claimRepo, payoutPreferences } = makeMocks(claim, { provider: "GCASH" });
    const service = new LoaService(loaRepo as any, claimRepo as any, payoutPreferences as any);

    const loa = await service.generateForClaim("claim_1", "staff_1");
    expect(loa).toBe(existingLoa);
    expect(loa.provider).toBe("MAYA");
    expect(loaRepo.createForClaim).not.toHaveBeenCalled();
  });

  it("rejects a claim that isn't APPROVED", async () => {
    const claim = makeApprovedClaim({ status: "PENDING" });
    const { loaRepo, claimRepo, payoutPreferences } = makeMocks(claim);
    const service = new LoaService(loaRepo as any, claimRepo as any, payoutPreferences as any);

    await expect(service.generateForClaim("claim_1", "staff_1")).rejects.toThrow(ServiceError);
  });

  it("throws 404 for a claim that doesn't exist", async () => {
    const { loaRepo, claimRepo, payoutPreferences } = makeMocks(null);
    const service = new LoaService(loaRepo as any, claimRepo as any, payoutPreferences as any);

    await expect(service.generateForClaim("nope", "staff_1")).rejects.toMatchObject({ statusCode: 404 });
  });
});
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/services/__tests__/loa.service.test.ts"

$path = "src/app/(portal)/admin/api-endpoints/page.tsx"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
"use client";
import { useSession } from "next-auth/react";
import { Sidebar } from "@/components/ui/Sidebar";
import { getAdminNav } from "@/lib/adminNav";

// This is a static manifest, not something introspected at runtime — if you
// add or remove a route under src/app/api, update this list to match. Kept
// deliberately simple (no reflection over the filesystem) since this is an
// internal reference page, not a source of truth for routing itself.
const ENDPOINTS: { method: string; path: string; auth: string; description: string }[] = [
  { method: "GET/POST", path: "/api/claims", auth: "Session", description: "List claims (scoped to the caller's role) / submit a new claim" },
  { method: "GET/PATCH", path: "/api/claims/:id", auth: "Session", description: "Fetch a claim's detail / transition its status" },
  { method: "GET/POST", path: "/api/claims/:id/documents", auth: "Session", description: "List / upload supporting documents for a claim" },
  { method: "GET", path: "/api/claims/:id/documents/:docId", auth: "Session", description: "Download a specific document" },
  { method: "POST", path: "/api/claims/:id/loa", auth: "Session", description: "Generate the Letter of Authorization + GCash checkout QR" },
  { method: "POST", path: "/api/claims/:id/payments", auth: "Session", description: "Start a payout checkout (GCash, Maya, PayPal, or Bank Transfer)" },
  { method: "POST", path: "/api/payments/:id/confirm", auth: "Public (sandbox)", description: "Mark a sandbox payment PAID or FAILED" },
  { method: "GET", path: "/api/notifications", auth: "Session", description: "List the caller's notifications" },
  { method: "PATCH", path: "/api/notifications/:id", auth: "Session", description: "Mark a notification as read" },
  { method: "GET", path: "/api/notifications/renewals", auth: "Session", description: "Upcoming policy renewal reminders" },
  { method: "GET/POST", path: "/api/chat", auth: "Session", description: "Fetch / send support-chat messages" },
  { method: "GET", path: "/api/admin/stats", auth: "Admin/Processor", description: "System-wide claims & LOA metrics" },
  { method: "GET/POST", path: "/api/admin/users", auth: "Admin", description: "List accounts / provision a new account" },
  { method: "GET", path: "/api/admin/security-logs", auth: "Admin", description: "Audit trail of account and claim activity" },
  { method: "*", path: "/api/auth/[...nextauth]", auth: "Public", description: "NextAuth sign-in/session endpoints" },
];

export default function ApiEndpointsPage() {
  const { data: session } = useSession();
  return (
    <div className="bg-navy min-h-screen text-white flex">
      <Sidebar brand="ADMIN CORE" items={getAdminNav(session?.user?.role)} active="API Endpoints" />

      <main className="flex-1 p-16">
        <h1 className="text-5xl font-black mb-2 tracking-tighter">API Endpoints</h1>
        <p className="text-slate-400 uppercase text-[10px] tracking-[0.5em] mb-12">Internal Route Reference</p>

        <div className="bg-white/5 rounded-[2rem] border border-white/10 overflow-hidden max-w-5xl">
          <table className="w-full text-left">
            <thead className="text-[10px] text-slate-400 uppercase tracking-widest">
              <tr>
                <th className="p-6">Method</th>
                <th className="p-6">Path</th>
                <th className="p-6">Auth</th>
                <th className="p-6">Description</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {ENDPOINTS.map((e) => (
                <tr key={e.path + e.method}>
                  <td className="p-6"><span className="text-[10px] bg-teal-500/20 text-teal-400 px-3 py-1 rounded-full font-black uppercase">{e.method}</span></td>
                  <td className="p-6 font-mono text-sm">{e.path}</td>
                  <td className="p-6 text-slate-400 text-sm">{e.auth}</td>
                  <td className="p-6 text-slate-300 text-sm">{e.description}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </main>
    </div>
  );
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/(portal)/admin/api-endpoints/page.tsx"

$path = "src/app/(portal)/admin/security-logs/page.tsx"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
"use client";
import { useEffect, useState } from "react";
import { useSession } from "next-auth/react";
import { Sidebar } from "@/components/ui/Sidebar";
import { getAdminNav } from "@/lib/adminNav";

interface AuditLogEntry {
  id: string;
  actorId: string | null;
  actorName: string;
  actorRole: string;
  action: string;
  detail: string | null;
  createdAt: string;
}

const ACTION_LABEL: Record<string, string> = {
  USER_PROVISIONED: "Account Created",
  CLAIM_STATUS_CHANGED: "Claim Status Changed",
  PAYOUT_INITIATED: "Payout Initiated",
};

export default function SecurityLogsPage() {
  const { data: session } = useSession();
  const [logs, setLogs] = useState<AuditLogEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/admin/security-logs")
      .then(async (r) => {
        if (!r.ok) throw new Error((await r.json().catch(() => ({}))).error ?? "Could not load logs.");
        return r.json();
      })
      .then(setLogs)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="bg-navy min-h-screen text-white flex">
      <Sidebar brand="ADMIN CORE" items={getAdminNav(session?.user?.role)} active="Security Logs" />

      <main className="flex-1 p-16">
        <h1 className="text-5xl font-black mb-2 tracking-tighter">Security Logs</h1>
        <p className="text-slate-400 uppercase text-[10px] tracking-[0.5em] mb-12">Account &amp; Claim Activity Audit Trail</p>

        {error && <p className="text-red-400 text-sm font-bold mb-6">{error}</p>}

        <div className="bg-white/5 rounded-[2rem] border border-white/10 overflow-hidden max-w-5xl">
          <table className="w-full text-left">
            <thead className="text-[10px] text-slate-400 uppercase tracking-widest">
              <tr>
                <th className="p-6">When</th>
                <th className="p-6">Actor</th>
                <th className="p-6">Action</th>
                <th className="p-6">Detail</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {logs.map((log) => (
                <tr key={log.id}>
                  <td className="p-6 text-slate-400 text-sm whitespace-nowrap">{new Date(log.createdAt).toLocaleString()}</td>
                  <td className="p-6">
                    <div className="font-bold">{log.actorName}</div>
                    <div className="text-[10px] text-slate-500 uppercase font-black">{log.actorRole}</div>
                  </td>
                  <td className="p-6">
                    <span className="text-[10px] bg-teal-500/20 text-teal-400 px-3 py-1 rounded-full font-black uppercase">
                      {ACTION_LABEL[log.action] ?? log.action}
                    </span>
                  </td>
                  <td className="p-6 text-slate-300 text-sm">{log.detail ?? "N/A"}</td>
                </tr>
              ))}
              {!loading && logs.length === 0 && !error && (
                <tr><td colSpan={4} className="p-10 text-center text-slate-400">No activity recorded yet.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </main>
    </div>
  );
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/(portal)/admin/security-logs/page.tsx"

$path = "src/app/(portal)/admin/queue/page.tsx"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useSession } from "next-auth/react";
import { Sidebar } from "@/components/ui/Sidebar";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { getAdminNav } from "@/lib/adminNav";
import { ClaimDTO } from "@/types";

export default function VerificationQueuePage() {
  const { data: session } = useSession();
  const [claims, setClaims] = useState<ClaimDTO[]>([]);
  const [loading, setLoading] = useState(true);

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

  async function transition(id: string, status: string) {
    const res = await fetch(`/api/claims/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status }),
    });
    if (!res.ok) {
      const body = await res.json();
      alert(body.error ?? "Update failed.");
      return;
    }
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
                          c.issues.some((i) => i.severity === "blocking") ? "bg-red-500/20 text-red-400" : "bg-amber-500/20 text-amber-400"
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
                        <button onClick={() => transition(c.id, "VERIFIED")} className="bg-teal-500/20 text-teal-400 px-4 py-1.5 rounded-full text-xs font-black uppercase hover:bg-teal-500/30 transition">Verify</button>
                        <button onClick={() => transition(c.id, "REJECTED")} className="bg-red-500/20 text-red-400 px-4 py-1.5 rounded-full text-xs font-black uppercase hover:bg-red-500/30 transition">Reject</button>
                      </>
                    )}
                    {c.status === "VERIFIED" && (
                      <>
                        <button onClick={() => transition(c.id, "APPROVED")} className="bg-teal-500/20 text-teal-400 px-4 py-1.5 rounded-full text-xs font-black uppercase hover:bg-teal-500/30 transition">Approve</button>
                        <button onClick={() => transition(c.id, "REJECTED")} className="bg-red-500/20 text-red-400 px-4 py-1.5 rounded-full text-xs font-black uppercase hover:bg-red-500/30 transition">Reject</button>
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
    </div>
  );
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/(portal)/admin/queue/page.tsx"

$path = "src/app/(portal)/claimant/settings/page.tsx"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
"use client";
import { useEffect, useState } from "react";
import { Sidebar } from "@/components/ui/Sidebar";
import { CLAIMANT_NAV } from "@/lib/claimantNav";

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

interface PayoutPreference {
  provider: "GCASH" | "MAYA" | "PAYPAL" | "BANK_TRANSFER";
  bankName: string | null;
  accountName: string | null;
  accountNumber: string | null;
}

export default function SettingsPage() {
  const [loading, setLoading] = useState(true);
  const [provider, setProvider] = useState<"GCASH" | "MAYA" | "PAYPAL" | "BANK_TRANSFER">("GCASH");
  const [bankChoice, setBankChoice] = useState(PH_BANKS[0]);
  const [otherBankName, setOtherBankName] = useState("");
  const [accountName, setAccountName] = useState("");
  const [accountNumber, setAccountNumber] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    fetch("/api/settings/payout-preference")
      .then((r) => (r.ok ? r.json() : null))
      .then((pref: PayoutPreference | null) => {
        if (pref) {
          setProvider(pref.provider);
          if (pref.bankName) {
            const isKnownBank = PH_BANKS.slice(0, -1).includes(pref.bankName);
            setBankChoice(isKnownBank ? pref.bankName : "Other Bank");
            if (!isKnownBank) setOtherBankName(pref.bankName);
          }
          setAccountName(pref.accountName ?? "");
          setAccountNumber(pref.accountNumber ?? "");
        }
      })
      .catch((err) => console.error("Failed to load payout preference:", err))
      .finally(() => setLoading(false));
  }, []);

  async function handleSave() {
    setError(null);
    setSaved(false);

    const bankDetails =
      provider === "BANK_TRANSFER"
        ? {
            bankName: bankChoice === "Other Bank" ? otherBankName.trim() : bankChoice,
            accountName: accountName.trim(),
            accountNumber: accountNumber.trim(),
          }
        : {};

    if (provider === "BANK_TRANSFER" && (!bankDetails.bankName || !bankDetails.accountName || !bankDetails.accountNumber)) {
      setError("Please fill in the bank name, account name, and account number.");
      return;
    }

    setSaving(true);
    const res = await fetch("/api/settings/payout-preference", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ provider, ...bankDetails }),
    });
    setSaving(false);

    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      setError(typeof body.error === "string" ? body.error : "Could not save your payout preference.");
      return;
    }

    setSaved(true);
    setTimeout(() => setSaved(false), 3000);
  }

  return (
    <div className="flex bg-slate-50 min-h-screen">
      <Sidebar brand="CLAIMS PRO" items={CLAIMANT_NAV} active="Settings" dark={false} />

      <main className="flex-1 p-12">
        <header className="mb-12">
          <h1 className="text-4xl font-black text-navy">Settings</h1>
          <p className="text-slate-400 mt-2 italic">Manage your default payout method</p>
        </header>

        <div className="bg-white p-10 rounded-3xl shadow-sm border border-slate-100 max-w-3xl">
          <p className="text-[10px] font-black text-slate-400 uppercase mb-2">Default Payout Method</p>
          <p className="text-slate-400 text-sm mb-6">
            Set your preferred way to receive claim payouts. You can always choose a different method when actually claiming a specific payout.
          </p>

          {loading ? (
            <p className="text-slate-400 text-sm">Loading…</p>
          ) : (
            <>
              <div className="flex gap-4 flex-wrap mb-8">
                {PROVIDERS.map((p) => (
                  <button
                    key={p.key}
                    onClick={() => setProvider(p.key)}
                    className={`px-6 py-3 rounded-xl font-bold text-sm transition ${
                      provider === p.key ? `${p.color} text-white` : "bg-slate-50 text-slate-500 border border-slate-100 hover:bg-slate-100"
                    }`}
                  >
                    {p.label}
                  </button>
                ))}
              </div>

              {provider === "BANK_TRANSFER" && (
                <div className="space-y-4 mb-8 max-w-md">
                  <div>
                    <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Bank</label>
                    <select
                      value={bankChoice}
                      onChange={(e) => setBankChoice(e.target.value)}
                      className="w-full p-3 border border-slate-200 rounded-xl bg-slate-50 outline-none focus:border-teal"
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
                        className="w-full p-3 border border-slate-200 rounded-xl bg-slate-50 outline-none focus:border-teal"
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
                      className="w-full p-3 border border-slate-200 rounded-xl bg-slate-50 outline-none focus:border-teal"
                    />
                  </div>
                  <div>
                    <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Account Number</label>
                    <input
                      type="text"
                      value={accountNumber}
                      onChange={(e) => setAccountNumber(e.target.value)}
                      placeholder="Bank account number"
                      className="w-full p-3 border border-slate-200 rounded-xl bg-slate-50 outline-none focus:border-teal"
                    />
                  </div>
                </div>
              )}

              {error && <p className="text-red-500 text-xs font-bold mb-4">{error}</p>}
              {saved && <p className="text-teal text-xs font-bold mb-4">Saved!</p>}

              <button
                onClick={handleSave}
                disabled={saving}
                className="bg-navy text-white px-8 py-4 rounded-2xl font-bold hover:bg-teal transition-all disabled:opacity-50"
              >
                {saving ? "Saving…" : "Save Preference"}
              </button>
            </>
          )}
        </div>
      </main>
    </div>
  );
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/(portal)/claimant/settings/page.tsx"

$path = "src/app/api/admin/security-logs/route.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { AuditService } from "@/services/audit.service";

const auditService = new AuditService();

// GET /api/admin/security-logs — powers the Admin "Security Logs" module
export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session || session.user.role !== "ADMIN") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  try {
    const logs = await auditService.list(200);
    return NextResponse.json(logs);
  } catch (err) {
    console.error("Failed to load audit logs:", err);
    return NextResponse.json({ error: "Could not load security logs." }, { status: 500 });
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/api/admin/security-logs/route.ts"

$path = "src/app/api/settings/payout-preference/route.ts"
$dir = Split-Path -Parent $path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$content = @'
import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { z } from "zod";
import { authOptions } from "@/lib/auth";
import { PayoutPreferenceService } from "@/services/payout-preference.service";
import { ServiceError } from "@/services/claim.service";

const preferenceService = new PayoutPreferenceService();

const preferenceSchema = z.object({
  provider: z.enum(["GCASH", "MAYA", "PAYPAL", "BANK_TRANSFER"]),
  bankName: z.string().min(1).optional(),
  accountName: z.string().min(1).optional(),
  accountNumber: z.string().min(1).optional(),
});

// GET /api/settings/payout-preference — the caller's saved default payout method
export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const preference = await preferenceService.get(session.user.id);
  return NextResponse.json(preference);
}

// PUT /api/settings/payout-preference — save/update the caller's default payout method
export async function PUT(req: NextRequest) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const body = await req.json();
  const parsed = preferenceSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  try {
    const preference = await preferenceService.save(session.user.id, parsed.data);
    return NextResponse.json(preference);
  } catch (err) {
    if (err instanceof ServiceError) return NextResponse.json({ error: err.message }, { status: err.statusCode });
    throw err;
  }
}
'@
$fullPath = [System.IO.Path]::GetFullPath($path)
[System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
Write-Output "  wrote src/app/api/settings/payout-preference/route.ts"

Write-Output ""
Write-Output "Done. 66 files written, 1 removed."
Write-Output "Next steps:"
Write-Output "  1. npm install"
Write-Output "  2. npx prisma migrate dev --name add_bank_transfer_audit_log_payout_pref_loa_provider"
Write-Output "  3. npm run prisma:seed   (only if your DB needs demo accounts)"
Write-Output "  4. npx tsc --noEmit -p tsconfig.json"
Write-Output "  5. npm run lint"
Write-Output "  6. npm test"
Write-Output "  7. npm run build"
