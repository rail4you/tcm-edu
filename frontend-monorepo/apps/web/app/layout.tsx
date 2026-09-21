import type { Metadata } from "next";
import { AuthProvider } from "@/lib/auth/context";
import "./globals.css";

/**
 * 根布局：三端共享。
 *
 * - 学生端（route group `(student)`）的子 layout 会注入 Navbar/Footer/ToastProvider
 * - 管理/教师端（`(admin)/admin`、`(teacher)/teacher`）的子 layout 注入 AntdRegistry + ProLayout
 *
 * 这里只放：字体变量（系统 CJK 字体栈，避免构件期下载 Google Fonts）、AuthProvider、全局样式。
 */

export const metadata: Metadata = {
  title: "杏宁树 · 智能医学教育平台",
  description: "中医在线教学平台：系统化课程、名师讲授、学练结合。",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN">
      <body className="min-h-screen antialiased">
        <AuthProvider>{children}</AuthProvider>
      </body>
    </html>
  );
}