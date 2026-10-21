"use client";
import { useState } from "react";

export type DecisionStatus = "VERIFIED" | "APPROVED" | "REJECTED";

const MIN_REASON_LENGTH = 5;
const MAX_REASON_LENGTH = 500;

const COPY: Record<DecisionStatus, { title: string; prompt: string; button: string; buttonClass: string }> = {
  VERIFIED: {
    title: "Verify this claim",
    prompt: "Why are you verifying this claim?",
    button: "Confirm Verify",
    buttonClass: "bg-navy hover:bg-teal",
  },
  APPROVED: {
    title: "Approve this claim",
    prompt: "Why are you approving this claim?",
    button: "Confirm Approve",
    buttonClass: "bg-teal hover:opacity-90",
  },
  REJECTED: {
    title: "Reject this claim",
    prompt: "Why are you rejecting this claim?",
    button: "Confirm Reject",
    buttonClass: "bg-red-500 hover:bg-red-600",
  },
};

// Rendered only while a decision is pending (parent mounts it on click and
// unmounts it on cancel/success), so its state always starts fresh.
// onConfirm should throw an Error with a readable message to keep the pop-up
// open and show that message (e.g. the server's "unresolved issues" text).
export function DecisionModal({
  status,
  referenceId,
  onCancel,
  onConfirm,
}: {
  status: DecisionStatus;
  referenceId?: string;
  onCancel: () => void;
  onConfirm: (reason: string) => Promise<void>;
}) {
  const [reason, setReason] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const copy = COPY[status];
  const trimmed = reason.trim();
  const tooShort = trimmed.length < MIN_REASON_LENGTH;

  async function confirm() {
    if (tooShort) {
      setError(`Please state a reason (at least ${MIN_REASON_LENGTH} characters).`);
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      await onConfirm(trimmed);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong. Please try again.");
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-[60] bg-black/50 flex items-center justify-center p-6" role="dialog" aria-modal="true">
      <div className="bg-white rounded-3xl shadow-2xl w-full max-w-lg p-8 text-slate-800">
        <h2 className="text-2xl font-black text-navy">{copy.title}</h2>
        {referenceId && <p className="font-mono text-xs text-slate-400 mt-1">{referenceId}</p>}

        <label className="text-[10px] font-black text-slate-400 uppercase block mt-6 mb-2">{copy.prompt}</label>
        <textarea
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          maxLength={MAX_REASON_LENGTH}
          rows={4}
          autoFocus
          placeholder="State your reason - the claimant will be able to see this."
          className="w-full p-4 border border-slate-200 rounded-xl bg-slate-50 outline-none focus:border-teal text-sm resize-none"
        />
        <div className="text-right text-[10px] text-slate-400 mt-1">
          {reason.length}/{MAX_REASON_LENGTH}
        </div>

        {error && <p className="text-red-500 text-xs font-bold mt-3">{error}</p>}

        <div className="flex justify-end gap-3 mt-6">
          <button
            onClick={onCancel}
            disabled={submitting}
            className="px-6 py-3 rounded-xl border border-slate-200 text-slate-500 font-bold text-sm hover:bg-slate-50 transition disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            onClick={confirm}
            disabled={submitting || tooShort}
            className={`${copy.buttonClass} text-white px-6 py-3 rounded-xl font-bold text-sm transition disabled:opacity-40 disabled:cursor-not-allowed`}
          >
            {submitting ? "Savingâ€¦" : copy.button}
          </button>
        </div>
      </div>
    </div>
  );
}
