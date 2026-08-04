const STYLES: Record<string, string> = {
  PENDING: "bg-yellow-100 text-yellow-700",
  VERIFIED: "bg-blue-100 text-blue-700",
  APPROVED: "bg-teal-100 text-teal-700",
  REJECTED: "bg-red-100 text-red-700",
  PAID: "bg-teal-100 text-teal-700",
  FAILED: "bg-red-100 text-red-700",
};

export function StatusBadge({ status }: { status: string }) {
  return (
    <span className={`text-[10px] px-3 py-1 rounded-full font-black uppercase ${STYLES[status] ?? "bg-slate-100 text-slate-600"}`}>
      {status}
    </span>
  );
}
