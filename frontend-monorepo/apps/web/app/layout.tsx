import type { Metadata } from "next";
import { Noto_Sans_SC, Noto_Serif_SC } from "next/font/google";
import { AuthProvider } from "@/lib/auth/context";
import "./globals.css";

/**
 * 根布局：三端共享。
 *
 * - 学生端（route group `(student)`）的子 layout 会注入 Navbar/Footer/ToastProvider
 * - 管理/教师端（`(admin)/admin`、`(teacher)/teacher`）的子 layout 注入 AntdRegistry + ProLayout
 *
 * 这里只放：字体、AuthProvider、全局样式。
 */

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
      <body className="min-h-screen antialiased">
        <AuthProvider>{children}</AuthProvider>
      </body>
    </html>
  );
}