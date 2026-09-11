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
// dashboard used by both ADMIN and PROCESSOR â€” same URL space, same visual
// shell, not two separate portals. Account provisioning, the security audit
// trail, and internal API docs stay ADMIN-only (also enforced server-side
// in middleware.ts and each route), so PROCESSOR simply doesn't see those
// links rather than hitting a dead end after clicking them.
export function getAdminNav(role?: string): NavItem[] {
  if (role === "ADMIN") return FULL_NAV;
  return FULL_NAV.filter((item) => !ADMIN_ONLY_LABELS.has(item.label));
}
