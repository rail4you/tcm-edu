"use client";

/**
 * 统一 AuthContext — 单一 Next.js app 承载三端，登录态共享。
 *
 * 与原先三分套（student/auth-context.tsx + admin/lib/auth.tsx + teacher/lib/auth.tsx）合并：
 *   - 单 AuthProvider，单一 localStorage key（统一 tcm_session）
 *   - 单一 Bearer token 写到 localStorage.auth_token（rpc-client 同源读取）
 *   - 登录端点：超管走 /api/auth/super_admin_sign_in；其他走 /api/auth/user/password/sign_in
 *   - /me 兜底认领已存在的 token（dev 调试、跨标签页同步）
 *
 * 角色 → 跳转路径：
 *   super_admin / tenant_admin → /admin
 *   teacher                   → /teacher
 *   student                   → /
 */

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { useRouter } from "next/navigation";
import {
  clearAuthToken,
  readAuthToken,
  writeAuthToken,
} from "@tcm-edu/rpc-client";
import { ROLE_HOME, type Role, type Session } from "./types";

const LS_KEY = "tcm_session";

interface AuthContextValue {
  session: Session | null;
  /** false until the first effect reads localStorage */
  ready: boolean;
  loading: boolean;
  error: string | null;
  /** 超管登录（POST /api/auth/super_admin_sign_in） */
  signInSuperAdmin: (email: string, password: string) => Promise<SignInResult>;
  /** 租户用户登录：教师/租户管理员/学生（POST /api/auth/user/password/sign_in） */
  signInTenantUser: (email: string, password: string) => Promise<SignInResult>;
  /** 学生注册（POST /api/auth/user/password/register） */
  registerStudent: (email: string, password: string) => Promise<SignInResult>;
  /** 清 session + token */
  signOut: () => Promise<void>;
}

interface SignInResult {
  ok: boolean;
  error?: string;
  /** 登录成功后由 caller 读取以决定跳转 */
  role?: Role;
}

interface MeResponse {
  id: string;
  email: string;
  tenant: string;
  role?: string;
}

const AuthContext = createContext<AuthContextValue | null>(null);

function readStored(): Session | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem(LS_KEY);
    return raw ? (JSON.parse(raw) as Session) : null;
  } catch {
    return null;
  }
}

function persist(s: Session | null) {
  if (typeof window === "undefined") return;
  if (s) {
    localStorage.setItem(LS_KEY, JSON.stringify(s));
    writeAuthToken(s.token);
  } else {
    localStorage.removeItem(LS_KEY);
    clearAuthToken();
  }
}

async function fetchMe(token: string): Promise<MeResponse | null> {
  try {
    const res = await fetch("/api/auth/me", {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) return null;
    const data = await res.json();
    return (data.data ?? null) as MeResponse | null;
  } catch {
    return null;
  }
}

/** 把后端字符串 role 收敛到 4 种之一，未知返回 null */
function normalizeRole(raw: string | undefined): Role | null {
  switch (raw) {
    case "super_admin":
      return "super_admin";
    case "tenant_admin":
      return "tenant_admin";
    case "teacher":
      return "teacher";
    case "student":
      return "student";
    default:
      return null;
  }
}

async function adoptToken(token: string): Promise<Session | null> {
  const me = await fetchMe(token);
  if (!me) return null;
  const role = normalizeRole(me.role);
  if (!role) return null;
  return {
    token,
    role,
    tenant: me.tenant ?? "public",
    userId: me.id,
    name: me.email,
    email: me.email,
  };
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const router = useRouter();
  const [session, setSession] = useState<Session | null>(null);
  const [ready, setReady] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // 启动：用本地 session，否则用共享 token 经 /me 认领
  useEffect(() => {
    const stored = readStored();
    if (stored) {
      setSession(stored);
      setReady(true);
      return;
    }
    const token = readAuthToken();
    if (!token) {
      setReady(true);
      return;
    }
    adoptToken(token)
      .then((s) => {
        if (s) {
          persist(s);
          setSession(s);
        }
      })
      .catch(() => {})
      .finally(() => setReady(true));
  }, []);

  // RPC 401 时 rpcHooks 广播 auth:logout
  useEffect(() => {
    const handler = () => {
      persist(null);
      setSession(null);
    };
    window.addEventListener("auth:logout", handler);
    return () => window.removeEventListener("auth:logout", handler);
  }, []);

  const setFromAuth = useCallback((auth: { bearer?: string; role?: string; tenant?: string }, email: string): Session | null => {
    if (!auth?.bearer) return null;
    const role = normalizeRole(auth.role);
    if (!role) return null;
    const session: Session = {
      token: auth.bearer,
      role,
      tenant: auth.tenant ?? "public",
      userId: "",
      name: email,
      email,
    };
    return session;
  }, []);

  const signInSuperAdmin = useCallback(
    async (email: string, password: string): Promise<SignInResult> => {
      setLoading(true);
      setError(null);
      try {
        const res = await fetch("/api/auth/super_admin_sign_in", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ email, password }),
        });
        const data = await res.json();
        const auth = data.authentication;
        if (res.ok && auth?.status === "success" && auth.bearer) {
          let s = setFromAuth(auth, email);
          if (!s) return { ok: false, error: "登录响应缺少 role" };
          // 超管不带 user_id，需要 /me 拿 id
          const me = await fetchMe(s.token);
          if (me) {
            s = { ...s, userId: me.id, tenant: me.tenant };
          }
          persist(s);
          setSession(s);
          return { ok: true, role: s.role };
        }
        const reason = auth?.reason === "invalid_credentials" ? "邮箱或密码错误" : "登录失败";
        setError(reason);
        return { ok: false, error: reason };
      } catch {
        setError("网络错误，请稍后重试");
        return { ok: false, error: "网络错误，请稍后重试" };
      } finally {
        setLoading(false);
      }
    },
    [setFromAuth]
  );

  const signInTenantUser = useCallback(
    async (email: string, password: string): Promise<SignInResult> => {
      setLoading(true);
      setError(null);
      try {
        const res = await fetch("/api/auth/user/password/sign_in", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ user: { email, password } }),
        });
        const data = await res.json();
        const auth = data.authentication;
        if (res.ok && auth?.status === "success" && auth.bearer) {
          const me = await fetchMe(auth.bearer);
          if (!me) return { ok: false, error: "获取用户信息失败" };
          const role = normalizeRole(me.role ?? auth.role);
          if (!role) return { ok: false, error: "该账号角色未知" };
          const session: Session = {
            token: auth.bearer,
            role,
            tenant: me.tenant ?? auth.tenant ?? "public",
            userId: me.id,
            name: me.email,
            email: me.email,
          };
          persist(session);
          setSession(session);
          return { ok: true, role };
        }
        const reason = auth?.reason || data.error || "邮箱或密码错误";
        setError(reason);
        return { ok: false, error: reason };
      } catch {
        setError("网络错误，请稍后重试");
        return { ok: false, error: "网络错误，请稍后重试" };
      } finally {
        setLoading(false);
      }
    },
    []
  );

  const registerStudent = useCallback(
    async (email: string, password: string): Promise<SignInResult> => {
      setLoading(true);
      setError(null);
      try {
        const res = await fetch("/api/auth/user/password/register", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            user: { email, password, password_confirmation: password },
          }),
        });
        const data = await res.json();
        const auth = data.authentication;
        if (res.ok && auth?.status === "success" && auth.bearer) {
          const me = await fetchMe(auth.bearer);
          if (!me) return { ok: false, error: "获取用户信息失败" };
          const session: Session = {
            token: auth.bearer,
            role: "student",
            tenant: me.tenant ?? "public",
            userId: me.id,
            name: me.email,
            email: me.email,
          };
          persist(session);
          setSession(session);
          return { ok: true, role: "student" };
        }
        const reason = auth?.reason || data.error || "注册失败";
        setError(reason);
        return { ok: false, error: reason };
      } catch {
        setError("网络错误，请稍后重试");
        return { ok: false, error: "网络错误，请稍后重试" };
      } finally {
        setLoading(false);
      }
    },
    []
  );

  const signOut = useCallback(async () => {
    const token = session?.token;
    try {
      if (token) {
        await fetch("/api/auth/sign_out", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${token}`,
          },
        });
      }
    } catch {
      /* ignore */
    }
    persist(null);
    setSession(null);
    setError(null);
    router.replace("/login");
  }, [session?.token, router]);

  const value = useMemo(
    () => ({
      session,
      ready,
      loading,
      error,
      signInSuperAdmin,
      signInTenantUser,
      registerStudent,
      signOut,
    }),
    [session, ready, loading, error, signInSuperAdmin, signInTenantUser, registerStudent, signOut]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}

/** 暴露给登录页：登录成功后用此决定跳转路径 */
export function homePathFor(role: Role): string {
  return ROLE_HOME[role];
}