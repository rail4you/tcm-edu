"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";

const AUTH_TOKEN_KEY = "auth_token";

/** 新租户角色（/api/auth/me 返回）。老 demo 页用的 "admin" | "user" 保留兼容。 */
export type TenantRole = "tenant_admin" | "teacher" | "student";

export interface UserProfile {
  id: string;
  email: string;
  role: "admin" | "user";
  permissions: string[];
  /** 新模型：租户内角色（登录后由 /me 回填） */
  tenantRole?: TenantRole;
  /** 如 tenant_default */
  tenant?: string;
}

export type Permission = "post:create" | "post:update" | "post:delete";

/** Check if a user profile has a specific permission. Admins have all permissions. */
export function can(profile: UserProfile | null, permission: Permission): boolean {
  if (!profile) return false;
  if (profile.role === "admin") return true;
  return profile.permissions.includes(permission);
}

interface AuthState {
  /** Whether we have a stored token (doesn't guarantee validity) */
  isAuthenticated: boolean;
  /** True after mount hydration (localStorage read). Guard redirects with this to avoid flash-redirect races. */
  ready: boolean;
  /** The current bearer token, if any */
  token: string | null;
  /** The current user's profile (null while loading or if not authed) */
  user: UserProfile | null;
  /** Sign in with email + password */
  login: (email: string, password: string) => Promise<LoginResult>;
  /** Register a new account */
  register: (email: string, password: string) => Promise<LoginResult>;
  /** Clear auth state */
  logout: () => Promise<void>;
  /** True while an auth request is in flight */
  loading: boolean;
  /** Last error message, if any */
  error: string | null;
  /** Whether the current user is an admin */
  isAdmin: boolean;
}

interface LoginResult {
  success: boolean;
  error?: string;
}

const AuthContext = createContext<AuthState | null>(null);

interface MeResponse {
  id: string;
  email: string;
  tenant: string;
  role?: TenantRole | string;
}

async function fetchProfile(token: string): Promise<UserProfile | null> {
  try {
    const res = await fetch("/api/auth/me", {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) return null;
    const data = await res.json();
    const me = data.data as MeResponse;
    const tenantRole = me.role as TenantRole | undefined;
    return {
      id: me.id,
      email: me.email,
      // 老 demo 页兼容：租户管理员视为 admin
      role: tenantRole === "tenant_admin" ? "admin" : "user",
      permissions: [],
      tenantRole,
      tenant: me.tenant,
    };
  } catch {
    return null;
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setToken] = useState<string | null>(null);
  const [user, setUser] = useState<UserProfile | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [ready, setReady] = useState(false);

  // Hydrate from localStorage on mount
  useEffect(() => {
    const stored = localStorage.getItem(AUTH_TOKEN_KEY);
    if (stored) {
      setToken(stored);
      fetchProfile(stored).then((profile) => {
        if (profile) setUser(profile);
      });
    }
    setReady(true);
  }, []);

  // Listen for forced logout events (from the RPC afterRequest hook)
  useEffect(() => {
    const handler = () => {
      setToken(null);
      setUser(null);
    };
    window.addEventListener("auth:logout", handler);
    return () => window.removeEventListener("auth:logout", handler);
  }, []);

  const login = useCallback(
    async (email: string, password: string): Promise<LoginResult> => {
      setLoading(true);
      setError(null);
      try {
        const res = await fetch("/api/auth/user/password/sign_in", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ user: { email, password } }),
        });
        const data = await res.json();

        if (data.authentication?.status === "success" && data.authentication?.bearer) {
          const newToken = data.authentication.bearer as string;
          localStorage.setItem(AUTH_TOKEN_KEY, newToken);
          setToken(newToken);
          // Fetch profile immediately
          const profile = await fetchProfile(newToken);
          if (profile) setUser(profile);
          return { success: true };
        }

        const reason =
          data.authentication?.reason || data.error || "邮箱或密码错误";
        setError(reason);
        return { success: false, error: reason };
      } catch {
        const msg = "网络错误，请稍后重试";
        setError(msg);
        return { success: false, error: msg };
      } finally {
        setLoading(false);
      }
    },
    []
  );

  const register = useCallback(
    async (email: string, password: string): Promise<LoginResult> => {
      setLoading(true);
      setError(null);
      try {
        const res = await fetch("/api/auth/user/password/register", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ user: { email, password, password_confirmation: password } }),
        });
        const data = await res.json();

        if (data.authentication?.status === "success" && data.authentication?.bearer) {
          const newToken = data.authentication.bearer as string;
          localStorage.setItem(AUTH_TOKEN_KEY, newToken);
          setToken(newToken);
          // Fetch profile immediately
          const profile = await fetchProfile(newToken);
          if (profile) setUser(profile);
          return { success: true };
        }

        const reason =
          data.authentication?.reason || data.error || "注册失败";
        setError(reason);
        return { success: false, error: reason };
      } catch {
        const msg = "网络错误，请稍后重试";
        setError(msg);
        return { success: false, error: msg };
      } finally {
        setLoading(false);
      }
    },
    []
  );

  const logout = useCallback(async () => {
    try {
      await fetch("/api/auth/sign_out", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
      });
    } catch {
      // Ignore network errors during logout
    }
    localStorage.removeItem(AUTH_TOKEN_KEY);
    setToken(null);
    setUser(null);
    setError(null);
  }, [token]);

  return (
    <AuthContext.Provider
      value={{
        isAuthenticated: token !== null,
        ready,
        token,
        user,
        login,
        register,
        logout,
        loading,
        error,
        isAdmin: user?.role === "admin",
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}
