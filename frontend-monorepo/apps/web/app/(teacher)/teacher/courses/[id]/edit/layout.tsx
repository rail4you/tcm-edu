import type { Metadata } from "next";

/**
 * 动态段 layout：为 `output: export` 提供静态参数占位。
 *
 * SPA 实际通过 Phoenix FallbackController 提供服务（dev 用 rewrites），
 * 这里的 placeholders 只为了让 `next build`（静态导出）通过。
 */
export function generateStaticParams() {
  return [{ id: "placeholder" }];
}

export const metadata: Metadata = { title: "编辑课程 · 杏宁树" };

export default function EditCourseLayout({
  children
}: Readonly<{ children: React.ReactNode }>) {
  return <>{children}</>;
}