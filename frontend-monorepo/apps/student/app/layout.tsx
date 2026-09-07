import type { Metadata } from "next";
import { Noto_Sans_SC, Noto_Serif_SC } from "next/font/google";
import { AuthProvider } from "./auth-context";
import Navbar from "@/components/navbar";
import Footer from "@/components/footer";
import "./globals.css";

const song = Noto_Serif_SC({
  subsets: ["latin"],
  weight: ["600", "700", "900"],
  variable: "--font-song",
  display: "swap",
});

const sans = Noto_Sans_SC({
  subsets: ["latin"],
  weight: ["400", "500", "700"],
  variable: "--font-sans-sc",
  display: "swap",
});

export const metadata: Metadata = {
  title: "中医教学 · 传承岐黄之术",
  description: "中医在线教学平台：系统化课程、名师讲授、学练结合。",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN" className={`${song.variable} ${sans.variable}`}>
      <body className="min-h-screen bg-rice-50 font-sans text-ink-900 antialiased">
        <AuthProvider>
          <Navbar />
          {children}
          <Footer />
        </AuthProvider>
      </body>
    </html>
  );
}
