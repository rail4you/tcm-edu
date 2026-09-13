"use client";

/**
 * 兼容层：把新的统一 AuthContext 暴露成学生端原先 useAuth 的 API。
 *
 * 学生端组件里大量 `import { useAuth } from "@/app/auth-context"` 的代码，
 * 通过这个 shim 可以只改 import 路径，不改函数签名。
 *
 * 仅用于学生端公开组件；对管理/教师端请直接用 `@/lib/auth/context` 的新 API。
 */

import { useAuth as useNewAuth } from "./context";
import type { Session } from "./types";

export interface CompatUser {
  id: string;
  email: string;
  role: "admin" | "user";
  permissions: string[];
  tenantRole?: Session["role"];
  tenant?: string;
}

export interface CompatAuth {
  isAuthenticated: boolean;
  ready: boolean;
  token: string | null;
  user: CompatUser | null;
  loading: boolean;
  error: string | null;
  isAdmin: boolean;
  /** 旧名 signOut → 新名 signOut */
  logout: () => Promise<void>;
  /** 旧名 login → 新名 signInTenantUser（学生注册走 registerStudent） */
  login: (email: string, password: string) => Promise<{ success: boolean; error?: string }>;
  register: (email: string, password: string) => Promise<{ success: boolean; error?: string }>;
}

/** 派生 CompatUser（兼容 demo 页面的 role/permissions 字段） */
function toCompatUser(s: Session | null): CompatUser | null {
  if (!s) return null;
  const isAdminLike = s.role === "super_admin" || s.role === "tenant_admin";
  return {
    id: s.userId,
    email: s.email,
    role: isAdminLike ? "admin" : "user",
    permissions: [],
    tenantRole: s.role,
    tenant: s.tenant,
  };
}

export function useAuth(): CompatAuth {
  const ctx = useNewAuth();
  const user = toCompatUser(ctx.session);

  return {
    isAuthenticated: ctx.session !== null,
    ready: ctx.ready,
    token: ctx.session?.token ?? null,
    user,
    loading: ctx.loading,
    error: ctx.error,
    isAdmin: ctx.session?.role === "super_admin" || ctx.session?.role === "tenant_admin",
    logout: ctx.signOut,
    login: async (email, password) => {
      const r = await ctx.signInTenantUser(email, password);
      return r.ok ? { success: true } : { success: false, error: r.error };
    },
    register: async (email, password) => {
      const r = await ctx.registerStudent(email, password);
      return r.ok ? { success: true } : { success: false, error: r.error };
    },
  };
}

/** 兼容旧的 can() 权限位（学生端 posts 页面还在用） */
export function can(user: CompatUser | null, permission: string): boolean {
  if (!user) return false;
  if (user.role === "admin") return true;
  return user.permissions.includes(permission);
}

export type { Session };
export type TenantRole = Session["role"];