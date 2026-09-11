/** @type {import('next').NextConfig} */

// Font Awesome (layout.tsx) is the only cross-origin resource this app
// loads in the browser â€” everything else (images, uploaded documents) is
// proxied through our own /api routes, so 'self' covers it.
// Next.js's dev server needs 'unsafe-eval' (React Fast Refresh) and a
// websocket connection (HMR) that production doesn't â€” kept dev-only so
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
  // âš ï¸ The CSP below is untested against a live browser render (this was
  // written without one available) â€” script-src 'unsafe-inline' is kept in
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
