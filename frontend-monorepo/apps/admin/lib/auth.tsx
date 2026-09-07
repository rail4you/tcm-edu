"use client";

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

export type AdminRole = "super_admin" | "tenant_admin";

export interface AdminSession {
  token: string;
  role: AdminRole;
  /** "public" for super_admin, "tenant_<slug>" for tenant admins */
  tenant: string;
  name: string;
  email: string;
}

interface AuthContextValue {
  session: AdminSession | null;
  loading: boolean;
  loginSuperAdmin: (email: string, password: string) => Promise<{ ok: boolean; error?: string }>;
  loginTenantAdmin: (email: string, password: string) => Promise<{ ok: boolean; error?: string }>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

const LS_KEY = "tcm_admin_session";
// rpcHooks.beforeRequest 读的是 auth_token，保持同步写入。
const TOKEN_KEY = "auth_token";

function readStored(): AdminSession | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem(LS_KEY);
    return raw ? (JSON.parse(raw) as AdminSession) : null;
  } catch {
    return null;
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<AdminSession | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setSession(readStored());
    setLoading(false);
  }, []);

  const persist = useCallback((s: AdminSession | null) => {
    setSession(s);
    if (typeof window === "undefined") return;
    if (s) {
      localStorage.setItem(LS_KEY, JSON.stringify(s));
      localStorage.setItem(TOKEN_KEY, s.token);
    } else {
      localStorage.removeItem(LS_KEY);
      localStorage.removeItem(TOKEN_KEY);
    }
  }, []);

  const loginSuperAdmin = useCallback(
    async (email: string, password: string) => {
      try {
        const res = await fetch("/api/auth/super_admin_sign_in", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ email, password }),
        });
        const data = await res.json();
        const auth = data?.authentication;
        if (res.ok && auth?.status === "success" && auth?.bearer) {
          persist({
            token: auth.bearer,
            role: "super_admin",
            tenant: auth.tenant ?? "public",
            name: auth.admin?.name ?? "",
            email: auth.admin?.email ?? email,
          });
          return { ok: true };
        }
        return { ok: false, error: auth?.reason === "invalid_credentials" ? "邮箱或密码错误" : "登录失败" };
      } catch {
        return { ok: false, error: "网络错误，请稍后重试" };
      }
    },
    [persist]
  );

  const loginTenantAdmin = useCallback(
    async (email: string, password: string) => {
      try {
        const res = await fetch("/api/auth/user/password/sign_in", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ user: { email, password } }),
        });
        const data = await res.json();
        const auth = data?.authentication;
        if (res.ok && auth?.status === "success" && auth?.bearer) {
          if (auth.role !== "tenant_admin") {
            return { ok: false, error: "该账号不是租户管理员，请使用对应的客户端登录" };
          }
          const meRes = await fetch("/api/auth/me", {
            headers: { Authorization: `Bearer ${auth.bearer}` },
          });
          const me = await meRes.json();
          persist({
            token: auth.bearer,
            role: "tenant_admin",
            tenant: auth.tenant ?? me?.data?.tenant ?? "tenant_default",
            name: me?.data?.email ?? email,
            email,
          });
          return { ok: true };
        }
        return { ok: false, error: "邮箱或密码错误" };
      } catch {
        return { ok: false, error: "网络错误，请稍后重试" };
      }
    },
    [persist]
  );

  const logout = useCallback(() => {
    persist(null);
  }, [persist]);

  const value = useMemo(
    () => ({ session, loading, loginSuperAdmin, loginTenantAdmin, logout }),
    [session, loading, loginSuperAdmin, loginTenantAdmin, logout]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}

/** Dashboard 路由守卫：未登录跳 /login；role 不符显示无权限（由布局菜单配合隐藏入口）。 */
export function useRequireAuth(allowedRoles?: AdminRole[]) {
  const { session, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (loading) return;
    if (!session) {
      router.replace("/login");
      return;
    }
    if (allowedRoles && !allowedRoles.includes(session.role)) {
      router.replace("/");
    }
  }, [session, loading, allowedRoles, router]);

  return { session, loading };
}
