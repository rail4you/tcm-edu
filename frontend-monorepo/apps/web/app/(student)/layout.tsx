"use client";

/**
 * 学生路由组 layout（(student)/**）：
 *   - 注入 Navbar / Footer / ToastProvider
 *   - 已登录的非学生角色（teacher / tenant_admin / super_admin）闯进 /、/courses、/learn…
 *     时自动跳到对应门户（/teacher 或 /admin），避免教师/管理员误闯学生首页
 *
 * 学生端是公开站，匿名用户也能访问，不做强制登录守卫。
 */

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import Navbar from "@/components/navbar";
import Footer from "@/components/footer";
import { ToastProvider } from "@/components/toast";
import { useAuth } from "@/lib/auth/context";
import { ROLE_HOME } from "@/lib/auth/types";

export default function StudentLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const { session, ready } = useAuth();

  // 已登录非学生角色 → 跳自己的门户
  useEffect(() => {
    if (!ready || !session) return;
    if (session.role !== "student") {
      router.replace(ROLE_HOME[session.role]);
    }
  }, [ready, session, router]);

  return (
    <div className="min-h-screen bg-rice-50 font-sans text-ink-900">
      <ToastProvider>
        <Navbar />
        {children}
        <Footer />
      </ToastProvider>
    </div>
  );
}