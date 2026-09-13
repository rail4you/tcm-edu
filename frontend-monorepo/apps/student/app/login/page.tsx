"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { useAuth } from "@/app/auth-context";

export default function LoginPage() {
  const router = useRouter();
  const { isAuthenticated, ready, login, register, loading, error } = useAuth();
  const [mode, setMode] = useState<"login" | "register">("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  useEffect(() => {
    if (ready && isAuthenticated) router.replace("/");
  }, [isAuthenticated, ready, router]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const fn = mode === "login" ? login : register;
    const result = await fn(email.trim(), password);
    if (result.success) router.replace("/");
  }

  const valid = email.trim() !== "" && password.length >= 6;

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
      <h1 className="mt-6 font-song text-2xl font-bold text-ink-900">
        {mode === "login" ? "欢迎回来" : "注册学员账号"}
      </h1>
      <p className="mt-2 text-sm text-ink-600">
        {mode === "login"
          ? "登录后选课学习，进度云端同步"
          : "注册即学，密码至少 6 位"}
      </p>

      <form
        onSubmit={handleSubmit}
        className="mt-8 flex w-full flex-col gap-4 rounded-2xl border border-rice-200 bg-white p-6 shadow-sm"
      >
        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-medium text-ink-900">邮箱</span>
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            placeholder="you@example.com"
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

        {error && (
          <div
            role="alert"
            className="rounded-lg border border-cinnabar-100 bg-cinnabar-50 px-3 py-2 text-sm text-cinnabar-700"
          >
            {error}
          </div>
        )}

        <button
          type="submit"
          disabled={loading || !valid}
          className="rounded-lg bg-cinnabar-500 px-4 py-2.5 text-sm font-medium text-white transition hover:bg-cinnabar-600 disabled:opacity-50"
        >
          {loading ? "请稍候…" : mode === "login" ? "登录" : "注册并登录"}
        </button>

        <button
          type="button"
          onClick={() => setMode(mode === "login" ? "register" : "login")}
          className="text-sm text-ink-600 underline underline-offset-2 transition hover:text-cinnabar-600"
        >
          {mode === "login" ? "没有账号？去注册" : "已有账号？去登录"}
        </button>
      </form>

      <Link href="/" className="mt-6 text-sm text-ink-400 transition hover:text-cinnabar-600">
        ← 先逛逛，不登录也能看课
      </Link>
    </main>
  );
}
