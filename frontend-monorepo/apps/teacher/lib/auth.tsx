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

export type TeacherRole = "teacher" | "tenant_admin";

export interface TeacherSession {
  token: string;
  role: TeacherRole;
  /** "tenant_<slug>" */
  tenant: string;
  userId: string;
  name: string;
  email: string;
}

interface AuthContextValue {
  session: TeacherSession | null;
  loading: boolean;
  login: (email: string, password: string) => Promise<{ ok: boolean; error?: string }>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

const LS_KEY = "tcm_teacher_session";

function readStored(): TeacherSession | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem(LS_KEY);
    return raw ? (JSON.parse(raw) as TeacherSession) : null;
  } catch {
    return null;
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<TeacherSession | null>(null);
  const [loading, setLoading] = useState(true);

  const persist = useCallback((s: TeacherSession | null) => {
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

  // 初次挂载：本端 session 优先，否则用共享 cookie 经 /me 认领
  //（仅 teacher / tenant_admin；学生 token 会被拒绝）。
  useEffect(() => {
    const stored = readStored();
    if (stored) {
      setSession(stored);
      setLoading(false);
      return;
    }
    const token = readAuthToken();
    if (!token) {
      setLoading(false);
      return;
    }
    fetch("/api/auth/me", { headers: { Authorization: `Bearer ${token}` } })
      .then((r) => (r.ok ? r.json() : null))
      .then((me) => {
        const role = me?.data?.role as TeacherRole | undefined;
        if (role === "teacher" || role === "tenant_admin") {
          persist({
            token,
            role,
            tenant: me.data.tenant ?? "tenant_default",
            userId: me.data.id ?? "",
            name: me.data.email ?? "",
            email: me.data.email ?? "",
          });
        }
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [persist]);

  const login = useCallback(
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
          if (auth.role !== "teacher" && auth.role !== "tenant_admin") {
            return { ok: false, error: "该账号不是教师，请使用对应的客户端登录" };
          }
          const meRes = await fetch("/api/auth/me", {
            headers: { Authorization: `Bearer ${auth.bearer}` },
          });
          const me = await meRes.json();
          persist({
            token: auth.bearer,
            role: auth.role,
            tenant: auth.tenant ?? me?.data?.tenant ?? "tenant_default",
            userId: me?.data?.id ?? "",
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
    () => ({ session, loading, login, logout }),
    [session, loading, login, logout]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}

/** Dashboard 路由守卫：未登录跳 /login。 */
export function useRequireAuth() {
  const { session, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (loading) return;
    if (!session) {
      router.replace("/login");
    }
  }, [session, loading, router]);

  return { session, loading };
}
