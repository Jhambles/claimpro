import { withAuth } from "next-auth/middleware";
import { NextResponse } from "next/server";

// Route-level guard: redirects unauthenticated users to /login and blocks
// users from portals that don't match their role, mirroring the three
// "Access Portals" from the original landing page.
export default withAuth(
  function middleware(req) {
    const { pathname } = req.nextUrl;
    const role = req.nextauth.token?.role;

    const roleForPath =
      pathname.startsWith("/admin") ? "ADMIN" :
      pathname.startsWith("/processor") ? "PROCESSOR" :
      pathname.startsWith("/claimant") ? "CLIENT" : null;

    if (roleForPath && role !== roleForPath) {
      // Already authenticated, just in the wrong portal — send them to the
      // one their role actually owns instead of bouncing to /login (which,
      // for an already-logged-in user, previously looked like a silent loop).
      const ownPortal: Record<string, string> = { CLIENT: "/claimant", PROCESSOR: "/processor", ADMIN: "/admin" };
      const destination = ownPortal[role as string] ?? "/login";
      return NextResponse.redirect(new URL(destination, req.url));
    }
    return NextResponse.next();
  },
  { callbacks: { authorized: ({ token }) => !!token } }
);

export const config = {
  matcher: ["/admin/:path*", "/processor/:path*", "/claimant/:path*", "/claims/:path*"],
};
