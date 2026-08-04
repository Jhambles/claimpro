"use client";
import { useSession } from "next-auth/react";
import { NotificationBell } from "@/components/ui/NotificationBell";
import { ChatWidget } from "@/components/chat/ChatWidget";

// Renders the notification bell + support chatbot on every page once a user
// is signed in; renders nothing on the public landing/login pages.
export function PortalChrome() {
  const { status } = useSession();
  if (status !== "authenticated") return null;

  return (
    <>
      <NotificationBell />
      <ChatWidget />
    </>
  );
}
