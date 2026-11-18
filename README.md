# ClaimsPro

Insurance claims lifecycle management, rebuilt on Next.js (App Router) + TypeScript,
Tailwind CSS, Prisma ORM, and cloud PostgreSQL. Deploys to Vercel.

## Architecture

RESTful API + layered MVC-style backend:

```
Route Handler (controller)  →  Service (business logic)  →  Repository (data access)  →  Prisma → PostgreSQL
src/app/api/**/route.ts        src/services/*.service.ts     src/repositories/*.ts
```

- **Repositories** (`src/repositories/`) implement interfaces (`interfaces.ts`) — Dependency
  Inversion. Only place that touches Prisma directly.
- **Services** (`src/services/`) hold business rules: reference-ID generation, claim status
  transition rules, LOA text generation, dashboard aggregation. No HTTP concerns.
- **Route handlers** (`src/app/api/**/route.ts`) are thin controllers: parse/validate the
  request (Zod), call a service, map the result/errors to an HTTP response.
- **Pages** (`src/app/`) are the "View" — client components that call the REST API.

REST endpoints:

| Method | Path                       | Role            | Purpose                          |
|--------|----------------------------|-----------------|-----------------------------------|
| GET    | `/api/claims`              | any             | List own claims (client) / queue (staff) |
| POST   | `/api/claims`              | CLIENT          | Submit a new claim               |
| GET    | `/api/claims/:id`          | any             | Claim detail                     |
| PATCH  | `/api/claims/:id`          | PROCESSOR/ADMIN | Transition claim status          |
| POST   | `/api/claims/:id/loa`      | PROCESSOR/ADMIN | Generate Letter of Authorization |
| GET    | `/api/admin/stats`         | ADMIN           | Dashboard metrics                |
| *      | `/api/auth/[...nextauth]`  | —               | Login/session (NextAuth)         |

## 1. Prerequisites

- Node.js 18.18+ and npm
- A free cloud Postgres database: **[Neon](https://neon.tech)** or **[Supabase](https://supabase.com)**
- A GitHub account
- A [Vercel](https://vercel.com) account

## 2. Local setup

```bash
git clone <your-repo-url> claimspro
cd claimspro
npm install
cp .env.example .env
```

### 2a. Create the cloud database

**Neon**: create a project → copy the connection string shown (includes `?sslmode=require`) →
paste into both `DATABASE_URL` and `DIRECT_URL` in `.env` (Neon's pooled and direct URLs are
usually interchangeable for a small app; use the "Direct connection" string for `DIRECT_URL` if offered).

**Supabase**: Project Settings → Database → Connection string.
- `DATABASE_URL` = the **Transaction pooler** URI (port 6543, `?pgbouncer=true`)
- `DIRECT_URL` = the **Session/direct** URI (port 5432) — Prisma needs this for migrations.

### 2b. Generate an auth secret

```bash
openssl rand -base64 32
```
Paste the output into `NEXTAUTH_SECRET` in `.env`.

### 2c. Push the schema and seed demo data

```bash
npx prisma migrate dev --name init
npm run prisma:seed
```

This creates the `users`, `claims`, `documents`, and `letters_of_authorization` tables and
seeds three accounts (password for all: `Passw0rd!`):

| Role      | Email                     |
|-----------|---------------------------|
| Admin     | admin@claimspro.dev       |
| Processor | processor@claimspro.dev   |
| Client    | client@claimspro.dev      |

### 2d. Run it

```bash
npm run dev
```
Visit `http://localhost:3000`.

## 3. GitHub

```bash
git init
git add .
git commit -m "Initial commit: ClaimsPro Next.js rebuild"
git branch -M main
git remote add origin https://github.com/<you>/claimspro.git
git push -u origin main
```

## 4. Deploy to Vercel

1. [vercel.com/new](https://vercel.com/new) → Import your GitHub repo.
2. Add environment variables in the Vercel project settings: `DATABASE_URL`, `DIRECT_URL`,
   `NEXTAUTH_SECRET`, and `NEXTAUTH_URL` (set this to your production URL, e.g.
   `https://claimspro.vercel.app`).
3. Deploy. The `build` script runs `prisma generate` automatically.
4. Run the migration against your production database once (from your machine, pointed at the
   prod `.env`, or via a one-off `vercel env pull` + `npx prisma migrate deploy`).

## 5. Extending it

- **File uploads**: the `Document` model and upload dropzone UI are in place; wire the dropzone
  to [Vercel Blob](https://vercel.com/docs/storage/vercel-blob) or Supabase Storage and POST to
  a new `/api/claims/:id/documents` route.
- **Registration**: add a `POST /api/users` route using `PrismaUserRepository.create` (hash the
  password with `hashPassword` from `src/lib/password.ts`) if you want self-serve signup instead
  of admin-provisioned accounts.
- **Testing repositories in isolation**: because services depend on `IClaimRepository` /
  `IUserRepository` / `ILoaRepository`, you can inject an in-memory fake implementing the same
  interface in unit tests without touching Postgres.

---

## Changelog: bug fixes + new features

### Bugs fixed
- **`estimate <= 0` let `NaN` through** (`NaN <= 0` is `false` in JS) — now uses `Number.isFinite()`.
- **Reference-ID race condition** — two simultaneous submissions could generate the same `CLM-2026-Xn` ID. Generation now mixes in a random suffix and retries on a unique-constraint collision.
- **Claimant "Outcome" column mislabeled rejected claims** as "Awaiting..." — now shows "Not approved".
- **Wrong-role redirect bounced to `/login`** even for an already-authenticated user — now redirects to that user's own portal.
- **Dead admin sidebar links** (Identity Manager, Security Logs, API Endpoints all pointed at the same URL) — Identity Manager is now a real page; the other two show an honest "Soon" badge instead of a fake link.
- **`/api/admin/users` route didn't exist** despite the folder being present — implemented.

### New: file uploads
The evidence dropzone on the claim detail page (`/claims/:id`) now uploads to **Vercel Blob**. Requires `BLOB_READ_WRITE_TOKEN` (create a Blob store from your Vercel project's Storage tab). Without it configured, uploads fail with a clear 503 message instead of silently doing nothing.

### New: claim detail page
`/claims/:id` — shared by all three roles (authorization enforced server-side): shows claim info, uploaded documents, staff status-transition buttons, LOA access, and the payment section.

### New: Identity Manager (`/admin/users`)
Real user list + a form to provision Claimant/Processor/Admin accounts (`POST /api/admin/users`), backed by `PrismaUserRepository`.

### New: notifications
- Bell icon (top-right, any logged-in page) shows unread count and recent activity.
- A notification is created automatically whenever a claim's status changes or a payment completes/fails.
- **Renewal reminders**: `GET /api/notifications/renewals`, wired to run daily via `vercel.json`'s cron config. Vercel automatically sends `Authorization: Bearer <CRON_SECRET>` — set `CRON_SECRET` in your env to match. Finds approved claims nearing a 1-year renewal window and notifies the claimant.

### New: online payments (GCash / Maya / PayPal)
Strategy pattern in `src/services/payments/` — `IPaymentProvider` interface, one class per provider (`GcashProvider`, `MayaProvider` via PayMongo; `PaypalProvider` via PayPal's Orders API), selected through `getPaymentProvider()` (factory). On an approved claim's detail page, the claimant can pay a fee via any of the three.

**Without gateway credentials configured**, checkout uses an in-app sandbox page (`/pay/[id]`) with "Simulate Successful/Failed Payment" buttons — the full flow (payment record, claim linkage, notification) still works for local dev and demos. Add real credentials to go live:
- GCash/Maya: `PAYMONGO_SECRET_KEY` from [dashboard.paymongo.com](https://dashboard.paymongo.com)
- PayPal: `PAYPAL_CLIENT_ID` / `PAYPAL_CLIENT_SECRET` from [developer.paypal.com](https://developer.paypal.com), `PAYPAL_ENV=sandbox` or `live`

In production, replace the client-callable `/api/payments/:id/confirm` with a signed webhook handler from the real gateway instead of trusting a browser redirect.

### New: AI chatbot ("Clai") with emoji
Floating widget (bottom-right, any logged-in page). Set `ANTHROPIC_API_KEY` for real AI answers grounded in a ClaimsPro-specific system prompt; without a key, it falls back to a rule-based FAQ responder — both reply with light emoji. Conversation history is stored per-user in the `chat_messages` table.

## Applying the schema changes

After pulling this update, run:
```bash
npx prisma migrate dev --name add_notifications_payments_chat
```
This adds the `notifications`, `payments`, and `chat_messages` tables (plus the new `payments` relation on `claims`) without touching your existing data.

## Update: payout direction corrected + QR code on the LOA

Earlier the payment feature had the direction backwards — it treated GCash/Maya/PayPal as a **fee the claimant pays**. The original LOA text ("approved for **disbursement**") already implied the opposite: the company pays the claimant. This is now fixed throughout:

- The claim detail page section is now "**Claim Your Payout**" (was "Pay Associated Fee"), pre-filled with the claim's approved estimate
- Buttons read "Claim via GCash/Maya/PayPal" (was "Pay with...")
- The mock checkout and return pages, and all notification text, now say "payout claimed" instead of "payment received"
- **New**: the LOA now includes a scannable QR code (generated server-side with the `qrcode` package, no external service call) linking straight to the claim's payout page — so a claimant holding a printed or saved LOA can scan it with their phone and go directly to claim their disbursement via their preferred e-wallet
- No schema/migration changes — same `Payment` table, just corrected framing and the added QR code

New dependency: `qrcode` (+ `@types/qrcode`) — run `npm install` after pulling this update.
