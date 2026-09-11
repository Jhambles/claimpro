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
