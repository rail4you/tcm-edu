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
import {
  clearAuthToken,
  readAuthToken,
  writeAuthToken,
} from "@tcm-edu/rpc-client";

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

  const persist = useCallback((s: AdminSession | null) => {
    setSession(s);
    if (typeof window === "undefined") return;
    if (s) {
      localStorage.setItem(LS_KEY, JSON.stringify(s));
      writeAuthToken(s.token);
    } else {
      localStorage.removeItem(LS_KEY);
      // 显式退出 = 三端一起退（dev 联调可预期；401 由 rpcHooks 统一清）。
      clearAuthToken();
    }
  }, []);

  useEffect(() => {
    const stored = readStored();
    if (stored) {
      setSession(stored);
      setLoading(false);
      return;
    }
    // 跨端联调：本端无 session 时，用共享 cookie 的 token 经 /me 认领
    //（仅 super_admin / tenant_admin；学生 token 会被拒绝）。
    const token = readAuthToken();
    if (!token) {
      setLoading(false);
      return;
    }
    fetch("/api/auth/me", { headers: { Authorization: `Bearer ${token}` } })
      .then((r) => (r.ok ? r.json() : null))
      .then((me) => {
        const role = me?.data?.role as AdminRole | undefined;
        if (role === "super_admin" || role === "tenant_admin") {
          persist({
            token,
            role,
            tenant: me.data.tenant ?? "public",
            name: me.data.email ?? "",
            email: me.data.email ?? "",
          });
        }
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [persist]);

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

  // RPC 401（token 失效）时 rpcHooks 会清 localStorage 并广播 auth:logout，
  // 这里跟进清 session，路由守卫会自动跳 /login。
  useEffect(() => {
    const handler = () => persist(null);
    window.addEventListener("auth:logout", handler);
    return () => window.removeEventListener("auth:logout", handler);
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
