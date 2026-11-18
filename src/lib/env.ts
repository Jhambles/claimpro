// Validated once, at module load, rather than deep inside whichever request
// happens to first need a given var - a missing DATABASE_URL should fail the
// deployment immediately and clearly, not as an opaque Prisma connection
// error on someone's first click in production.
const REQUIRED = ["DATABASE_URL", "NEXTAUTH_SECRET", "NEXTAUTH_URL"] as const;

// Each has a documented, working fallback (see .env.example) - missing these
// only degrades a specific feature, so we warn rather than fail the boot.
const OPTIONAL_WITH_FALLBACK: Record<string, string> = {
  BLOB_READ_WRITE_TOKEN: "document uploads and signup ID photos will return a 503 instead of being stored",
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
