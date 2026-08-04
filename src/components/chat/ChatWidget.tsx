"use client";
import { useEffect, useRef, useState } from "react";

interface Message {
  id?: string;
  role: "user" | "assistant";
  content: string;
}

// Floating support chatbot ("Clai") available across every authenticated
// portal page. Calls /api/chat, which uses the Claude API when configured
// and otherwise falls back to a friendly rule-based FAQ responder — either
// way, replies use a light touch of emoji as requested.
export function ChatWidget() {
  const [open, setOpen] = useState(false);
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [sending, setSending] = useState(false);
  const endRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (open && messages.length === 0) {
      fetch("/api/chat")
        .then((r) => (r.ok ? r.json() : Promise.reject(new Error(`History fetch failed: ${r.status}`))))
        .then((history) => {
          if (Array.isArray(history) && history.length > 0) {
            setMessages(history);
          } else {
            setMessages([{ role: "assistant", content: "Hey! 👋 I'm Clai, your ClaimsPro assistant. Ask me anything about claims, LOAs, or payments!" }]);
          }
        })
        .catch((err) => {
          console.error("Clai: failed to load chat history", err);
          setMessages([{ role: "assistant", content: "Hey! 👋 I'm Clai. (Couldn't load earlier messages, but go ahead and ask something!)" }]);
        });
    }
  }, [open, messages.length]);

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, open]);

  async function send() {
    const text = input.trim();
    if (!text || sending) return;
    setInput("");
    setMessages((m) => [...m, { role: "user", content: text }]);
    setSending(true);

    try {
      const res = await fetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: text }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error ? JSON.stringify(body.error) : `Request failed: ${res.status}`);
      }
      const data = await res.json();
      setMessages((m) => [...m, { role: "assistant", content: data.reply ?? "Sorry, I couldn't respond just now 😅" }]);
    } catch (err) {
      console.error("Clai: send failed", err);
      setMessages((m) => [...m, { role: "assistant", content: "Something went wrong on my end 😅 Please try again." }]);
    } finally {
      setSending(false);
    }
  }

  return (
    <div className="fixed bottom-6 right-6 z-50">
      {open && (
        <div className="w-80 h-[28rem] bg-white rounded-3xl shadow-2xl border border-slate-100 flex flex-col overflow-hidden mb-4">
          <div className="bg-navy text-white px-5 py-4 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className="text-lg">🤖</span>
              <span className="font-bold text-sm">Clai · Support</span>
            </div>
            <button onClick={() => setOpen(false)} className="text-slate-300 hover:text-white">
              <i className="fa-solid fa-xmark" />
            </button>
          </div>

          <div className="flex-1 overflow-y-auto p-4 space-y-3 bg-slate-50">
            {messages.map((m, i) => (
              <div key={m.id ?? i} className={`flex ${m.role === "user" ? "justify-end" : "justify-start"}`}>
                <div
                  className={`max-w-[85%] px-4 py-2 rounded-2xl text-sm ${
                    m.role === "user" ? "bg-teal text-white rounded-br-sm" : "bg-white text-slate-700 border border-slate-100 rounded-bl-sm"
                  }`}
                >
                  {m.content}
                </div>
              </div>
            ))}
            {sending && <div className="text-xs text-slate-400 italic">Clai is typing… 💭</div>}
            <div ref={endRef} />
          </div>

          <div className="p-3 border-t border-slate-100 flex gap-2">
            <input
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && send()}
              placeholder="Ask about your claim…"
              className="flex-1 px-4 py-2 rounded-full bg-slate-50 border border-slate-100 outline-none focus:border-teal text-sm"
            />
            <button onClick={send} className="w-10 h-10 rounded-full bg-navy text-white flex items-center justify-center hover:bg-teal transition">
              <i className="fa-solid fa-paper-plane text-xs" />
            </button>
          </div>
        </div>
      )}

      <button
        onClick={() => setOpen((o) => !o)}
        className="w-14 h-14 rounded-full bg-teal text-white shadow-xl flex items-center justify-center text-2xl hover:scale-105 transition"
      >
        {open ? <i className="fa-solid fa-xmark" /> : "💬"}
      </button>
    </div>
  );
}
