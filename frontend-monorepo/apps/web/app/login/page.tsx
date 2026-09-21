"use client";

/**
 * 统一登录页 /login
 *
 * 三个 Tab（参考 kg-edu roleConfigs）：
 *   - 学生       → signInTenantUser / registerStudent（POST /api/auth/user/password/sign_in 或 /register）
 *   - 教师       → signInTenantUser（后端 role 必须是 teacher；不对则报错）
 *   - 管理       → signInSuperAdmin（超管专用入口）或 signInTenantUser（租户管理员）
 *
 * 登录成功后按 role 跳转：
 *   super_admin / tenant_admin → /admin
 *   teacher                   → /teacher
 *   student                   → /
 *
 * 不再使用 Antd（让登录页与学生端视觉一致，用 Tailwind 自研色板）。
 */

import { Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useAuth, homePathFor } from "@/lib/auth/context";
import type { Role } from "@/lib/auth/types";

type Tab = "student" | "teacher" | "admin";

interface TabConfig {
  key: Tab;
  label: string;
  subtitle: string;
  /** 此 tab 注册入口是否开放（仅学生支持自助注册） */
  allowRegister: boolean;
}

const TABS: TabConfig[] = [
  {
    key: "student",
    label: "学员",
    subtitle: "登录后选课学习，进度云端同步",
    allowRegister: true,
  },
  {
    key: "teacher",
    label: "教师",
    subtitle: "教师 / 机构管理员登录，课程创建与发布",
    allowRegister: false,
  },
  {
    key: "admin",
    label: "管理",
    subtitle: "超级管理员登录（跨租户运营）",
    allowRegister: false,
  },
];

const ADMIN_KIND: "super" | "tenant" = "super"; // 默认显示超管登录

export default function LoginPage() {
  return (
    <Suspense fallback={null}>
      <LoginContent />
    </Suspense>
  );
}

function LoginContent() {
  const router = useRouter();
  const params = useSearchParams();
  const {
    session,
    ready,
    loading,
    error,
    signInSuperAdmin,
    signInTenantUser,
    registerStudent,
    signOut,
  } = useAuth();
  const [tab, setTab] = useState<Tab>(
    (params.get("role") as Tab) ?? "student"
  );
  const [mode, setMode] = useState<"login" | "register">("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [localError, setLocalError] = useState<string | null>(null);

  // 已登录跳走（按角色）
  useEffect(() => {
    if (!ready) return;
    if (session) router.replace(homePathFor(session.role));
  }, [ready, session, router]);

  // 切 tab 时清错误
  useEffect(() => {
    setLocalError(null);
  }, [tab, mode]);

  const cfg = useMemo(() => TABS.find((t) => t.key === tab)!, [tab]);
  const valid = email.trim() !== "" && password.length >= 6;

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLocalError(null);

    const trimmedEmail = email.trim();
    let result: { ok: boolean; error?: string; role?: Role };

    if (tab === "admin") {
      // 当前默认只暴露超管入口；租户管理员请走教师 tab（同后端 sign_in 端点）
      result = await signInSuperAdmin(trimmedEmail, password);
    } else if (tab === "teacher") {
      result = await signInTenantUser(trimmedEmail, password);
      if (result.ok && result.role !== "teacher" && result.role !== "tenant_admin") {
        await signOut();
        setLocalError("该账号不是教师，请使用学员 tab 登录");
        return;
      }
    } else {
      // student
      if (mode === "register") {
        result = await registerStudent(trimmedEmail, password);
      } else {
        result = await signInTenantUser(trimmedEmail, password);
        if (result.ok && result.role && result.role !== "student") {
          // 教师/管理员误闯学员 tab：直接跳到对应门户
          router.replace(homePathFor(result.role));
          return;
        }
      }
    }

    if (result.ok && result.role) {
      router.replace(homePathFor(result.role));
    } else {
      setLocalError(result.error ?? "登录失败");
    }
  }

  return (
    <main className="mx-auto flex w-full max-w-md flex-col items-center px-4 py-16 sm:px-6">
      <Link href="/" className="flex items-center gap-2">
        <span className="flex h-10 w-10 items-center justify-center rounded-lg bg-cinnabar-500 font-song text-xl text-white">
          岐
        </span>
        <span className="font-song text-xl font-semibold tracking-wide text-ink-900">
          中医教学
        </span>
      </Link>
      <h1 className="mt-6 font-song text-2xl font-bold text-ink-900">登录</h1>
      <p className="mt-2 text-sm text-ink-600">{cfg.subtitle}</p>

      {/* Role tabs */}
      <div className="mt-6 flex w-full rounded-xl border border-rice-200 bg-white p-1">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            onClick={() => setTab(t.key)}
            className={[
              "flex-1 rounded-lg px-3 py-2 text-sm transition",
              tab === t.key
                ? "bg-cinnabar-500 font-medium text-white"
                : "text-ink-600 hover:bg-rice-50",
            ].join(" ")}
          >
            {t.label}
          </button>
        ))}
      </div>

      <form
        onSubmit={onSubmit}
        className="mt-6 flex w-full flex-col gap-4 rounded-2xl border border-rice-200 bg-white p-6 shadow-sm"
      >
        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-medium text-ink-900">邮箱</span>
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            placeholder={
              tab === "admin"
                ? "super-admin@example.com"
                : tab === "teacher"
                  ? "教师邮箱"
                  : "you@example.com"
            }
            className="rounded-lg border border-rice-200 bg-white px-3 py-2.5 text-sm outline-none transition focus:border-cinnabar-500 focus:ring-2 focus:ring-cinnabar-100"
          />
        </label>
        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-medium text-ink-900">密码</span>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            minLength={6}
            placeholder="至少 6 位"
            className="rounded-lg border border-rice-200 bg-white px-3 py-2.5 text-sm outline-none transition focus:border-cinnabar-500 focus:ring-2 focus:ring-cinnabar-100"
          />
        </label>

        {(localError || error) && (
          <div
            role="alert"
            className="rounded-lg border border-cinnabar-100 bg-cinnabar-50 px-3 py-2 text-sm text-cinnabar-700"
          >
            {localError || error}
          </div>
        )}

        <button
          type="submit"
          disabled={loading || !valid}
          className="rounded-lg bg-cinnabar-500 px-4 py-2.5 text-sm font-medium text-white transition hover:bg-cinnabar-600 disabled:opacity-50"
        >
          {loading
            ? "请稍候…"
            : mode === "register" && tab === "student"
              ? "注册并登录"
              : "登录"}
        </button>

        {cfg.allowRegister && (
          <button
            type="button"
            onClick={() => setMode(mode === "login" ? "register" : "login")}
            className="text-sm text-ink-600 underline underline-offset-2 transition hover:text-cinnabar-600"
          >
            {mode === "login" ? "没有账号？去注册" : "已有账号？去登录"}
          </button>
        )}
      </form>

      <Link href="/" className="mt-6 text-sm text-ink-400 transition hover:text-cinnabar-600">
        ← 先逛逛，不登录也能看课
      </Link>
    </main>
  );
}