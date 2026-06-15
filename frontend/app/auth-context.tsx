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

interface AuthState {
  /** Whether we have a stored token (doesn't guarantee validity) */
  isAuthenticated: boolean;
  /** The current bearer token, if any */
  token: string | null;
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
}

interface LoginResult {
  success: boolean;
  error?: string;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setToken] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Hydrate from localStorage on mount
  useEffect(() => {
    const stored = localStorage.getItem(AUTH_TOKEN_KEY);
    if (stored) setToken(stored);
  }, []);

  // Listen for forced logout events (from the RPC afterRequest hook)
  useEffect(() => {
    const handler = () => setToken(null);
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
          return { success: true };
        }

        const reason =
          data.authentication?.reason || data.error || "Sign in failed";
        setError(reason);
        return { success: false, error: reason };
      } catch (e) {
        const msg = "Network error";
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

        if (
          data.authentication?.status === "success" &&
          data.authentication?.bearer
        ) {
          const newToken = data.authentication.bearer as string;
          localStorage.setItem(AUTH_TOKEN_KEY, newToken);
          setToken(newToken);
          return { success: true };
        }

        const reason =
          data.authentication?.reason || data.error || "Registration failed";
        setError(reason);
        return { success: false, error: reason };
      } catch (e) {
        const msg = "Network error";
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
    setError(null);
  }, [token]);

  return (
    <AuthContext.Provider
      value={{
        isAuthenticated: token !== null,
        token,
        login,
        register,
        logout,
        loading,
        error,
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
