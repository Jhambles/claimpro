import { withAuth } from "next-auth/middleware";
import { NextResponse } from "next/server";

// Route-level guard: redirects unauthenticated users to /login and blocks
// users from areas that don't match their role.
//
// /admin and /admin/queue are the single shared dashboard for both ADMIN and
// PROCESSOR â€” one login, one URL space, one visual shell, not two separate
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
      (!isAdminOnlySubpage && !isSharedDashboard && !isClaimant); // /claims/[id] etc. â€” handled by page-level checks

    if (!hasAccess) {
      // Already authenticated, just somewhere they can't go â€” send them to
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
