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

export function buildLoaHtml(content: string, qrCodeDataUrl?: string, payoutUrl?: string): string {
  const safeContent = escapeHtml(content);
  const safePayoutUrl = payoutUrl ? escapeHtml(payoutUrl) : undefined;

  const qrSection = qrCodeDataUrl
    ? `
      <div style="margin-top:32px;padding-top:24px;border-top:1px dashed #ccc;text-align:center;">
        <img src="${qrCodeDataUrl}" alt="Scan to claim your payout" width="180" height="180" />
        <p style="font-family:sans-serif;font-size:13px;color:#475569;margin-top:8px;">
          Scan to claim your payout via GCash
        </p>
        ${safePayoutUrl ? `<p style="font-family:sans-serif;font-size:11px;color:#94a3b8;">${safePayoutUrl}</p>` : ""}
      </div>`
    : "";

  return `<pre style="font-family:serif;padding:50px 50px 10px;white-space:pre-wrap;line-height:1.6;">${safeContent}</pre>${qrSection}`;
}