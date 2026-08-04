import type { Metadata } from "next";
import { SessionProvider } from "@/components/providers/SessionProvider";
import { PortalChrome } from "@/components/providers/PortalChrome";
import "./globals.css";

export const metadata: Metadata = {
  title: "ClaimsPro | Accelerate Your Claims",
  description: "Cloud-native insurance claims lifecycle management.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <link
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css"
          rel="stylesheet"
        />
      </head>
      <body className="bg-white font-sans text-slate-900">
        <SessionProvider>
          {children}
          <PortalChrome />
        </SessionProvider>
      </body>
    </html>
  );
}
