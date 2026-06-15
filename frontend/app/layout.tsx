import type { Metadata } from "next";
import { AuthProvider } from "./auth-context";
import "./globals.css";

export const metadata: Metadata = {
  title: "ash-ts-demo",
  description:
    "Phoenix + Ash + AshTypescript backend with a Next.js static-export frontend.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-full bg-zinc-50 text-zinc-900 dark:bg-zinc-950 dark:text-zinc-100">
        <AuthProvider>{children}</AuthProvider>
      </body>
    </html>
  );
}
